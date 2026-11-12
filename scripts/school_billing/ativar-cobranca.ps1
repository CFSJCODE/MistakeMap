# Liga a cobrança da escola em produção, depois do deploy da migration
# 20261112170000 e da função billing-webhook. Idempotente: rodar de novo
# só confere e corrige.
#
#   1. Vault school_billing_cron_secret = SCHOOL_BILLING_CRON_SECRET
#      (o pg_cron usa esse valor para chamar a billing-webhook).
#   2. Webhook do Asaas apontando para a billing-webhook, com authToken =
#      ASAAS_WEBHOOK_TOKEN e os eventos PAYMENT_* e INVOICE_* que ela trata.
#
# Os valores vêm de appmistakemap\.env.asaas.local (ignorado pelo Git) e
# nunca são impressos. Precisa do Supabase CLI logado (supabase login).
# Uso: powershell -ExecutionPolicy Bypass -File scripts\school_billing\ativar-cobranca.ps1
$ErrorActionPreference = 'Stop'
$ref = 'bmdjicshcjpknuaywaph'
$webhookUrl = "https://$ref.supabase.co/functions/v1/billing-webhook"
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$envFile = Join-Path $root 'appmistakemap\.env.asaas.local'
if (-not (Test-Path $envFile)) { throw "Arquivo não encontrado: $envFile" }

$vars = @{}
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*([A-Z_]+)\s*=\s*(.*?)\s*$') {
    $vars[$Matches[1]] = $Matches[2].Trim('"', "'")
  }
}
foreach ($k in 'ASAAS_API_KEY', 'ASAAS_WEBHOOK_TOKEN', 'SCHOOL_BILLING_CRON_SECRET') {
  if (-not $vars[$k]) { throw "Falta $k em $envFile" }
}
if (-not $vars['ASAAS_API_KEY'].StartsWith('$aact_prod_')) {
  throw 'ASAAS_API_KEY não é chave de produção ($aact_prod_).'
}
$cron = $vars['SCHOOL_BILLING_CRON_SECRET']
if ($cron -notmatch '^[A-Za-z0-9_\-]{24,}$') {
  throw 'SCHOOL_BILLING_CRON_SECRET precisa ter 24+ caracteres (letras, números, - ou _).'
}

# 1. Vault (o valor vai num arquivo temporário, não na linha de comando).
$sql = @"
do `$`$
declare v text := '$cron';
begin
  if exists (select 1 from vault.secrets where name = 'school_billing_cron_secret') then
    perform vault.update_secret(
      (select id from vault.secrets where name = 'school_billing_cron_secret'), v);
  else
    perform vault.create_secret(v, 'school_billing_cron_secret');
  end if;
end `$`$;
"@
$tmp = Join-Path $env:TEMP ("mm-vault-" + [guid]::NewGuid() + '.sql')
try {
  Set-Content -Path $tmp -Value $sql -Encoding UTF8
  Push-Location (Join-Path $root 'appmistakemap\database')
  try {
    supabase db query --linked --project-ref $ref -f $tmp | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'supabase db query falhou.' }
  } finally { Pop-Location }
} finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
Write-Host 'ok: Vault school_billing_cron_secret gravado'

# 2. Webhook no Asaas.
$api = 'https://api.asaas.com/v3'
$headers = @{
  'access_token' = $vars['ASAAS_API_KEY']
  'User-Agent'   = 'MistakeMap'
  'Content-Type' = 'application/json'
}
$events = @(
  'PAYMENT_CONFIRMED', 'PAYMENT_RECEIVED', 'PAYMENT_OVERDUE',
  'PAYMENT_DELETED', 'PAYMENT_REFUNDED',
  'INVOICE_AUTHORIZED', 'INVOICE_ERROR', 'INVOICE_CANCELED'
)
$email = (Invoke-RestMethod -Method Get -Uri "$api/myAccount/commercialInfo" -Headers $headers).email
$body = @{
  name        = 'MistakeMap - cobranca da escola'
  url         = $webhookUrl
  email       = $email
  enabled     = $true
  interrupted = $false
  apiVersion  = 3
  authToken   = $vars['ASAAS_WEBHOOK_TOKEN']
  sendType    = 'SEQUENTIALLY'
  events      = $events
} | ConvertTo-Json -Depth 4
$list = Invoke-RestMethod -Method Get -Uri "$api/webhooks?limit=100" -Headers $headers
$existing = @($list.data | Where-Object { $_.url -eq $webhookUrl }) | Select-Object -First 1
if ($existing) {
  Invoke-RestMethod -Method Put -Uri "$api/webhooks/$($existing.id)" -Headers $headers -Body $body | Out-Null
  Write-Host 'ok: webhook do Asaas atualizado'
} else {
  Invoke-RestMethod -Method Post -Uri "$api/webhooks" -Headers $headers -Body $body | Out-Null
  Write-Host 'ok: webhook do Asaas cadastrado'
}
Write-Host 'Cobrança da escola ligada.'
