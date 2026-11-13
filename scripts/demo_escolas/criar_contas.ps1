# Cria (ou redefine a senha de) todas as contas de scripts/demo_escolas/contas.json
# no Supabase de produção e grava as senhas SÓ no PC, em
# appmistakemap/.env.contas-demo.local (ignorado pelo Git).
#
# Uso (no PC do dono, com o Supabase CLI logado):
#   powershell -ExecutionPolicy Bypass -File scripts\demo_escolas\criar_contas.ps1
#
# A chave service_role é lida do CLI na hora e fica só na memória deste
# processo: nunca vai para arquivo, log, app ou GitHub. As senhas não são
# impressas na tela.
#   (-AppDir aponta a pasta appmistakemap onde ficam os .env locais; padrão:
#   a do próprio clone.)
#   -SomenteNovas: cria só as contas que ainda não existem e acrescenta as
#   senhas delas ao .env.contas-demo.local; as contas que já existem mantêm a
#   senha e só têm nome e cargo atualizados.
param(
  [string]$ProjectRef = 'bmdjicshcjpknuaywaph',
  [string]$AppDir = (Join-Path $PSScriptRoot '..\..\appmistakemap'),
  [switch]$SomenteNovas
)
$ErrorActionPreference = 'Stop'
$AppDir = (Resolve-Path $AppDir).Path
$contas = (Get-Content (Join-Path $PSScriptRoot 'contas.json') -Raw -Encoding UTF8 | ConvertFrom-Json).contas

$keys = supabase projects api-keys --project-ref $ProjectRef -o json | ConvertFrom-Json
$service = ($keys | Where-Object { $_.name -eq 'service_role' } | Select-Object -First 1).api_key
if (-not $service) { throw 'Não consegui ler a chave service_role pelo Supabase CLI (rode supabase login).' }
$base = "https://$ProjectRef.supabase.co/auth/v1/admin"
$h = @{ apikey = $service; Authorization = "Bearer $service"; 'Content-Type' = 'application/json' }

function New-SenhaDemo {
  $alfabeto = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
  $bytes = New-Object byte[] 18
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $s = -join ($bytes | ForEach-Object { $alfabeto[$_ % $alfabeto.Length] })
  return "Mm-$s-9"
}

$existentes = @{}
$pagina = 1
do {
  $r = Invoke-RestMethod -Method Get -Uri "$base/users?page=$pagina&per_page=200" -Headers $h
  foreach ($u in $r.users) { $existentes[$u.email.ToLower()] = $u.id }
  $pagina++
} while ($r.users.Count -eq 200)

$destino = Join-Path $AppDir '.env.contas-demo.local'
if ($SomenteNovas -and (Test-Path $destino)) {
  $linhas = @(Get-Content $destino -Encoding UTF8)
  $linhas += "# Contas novas acrescentadas em $(Get-Date -Format 'yyyy-MM-dd HH:mm'):"
  $linhas += ''
} else {
  $linhas = @(
    '# Contas de demonstração do MistakeMap (Oficina Volt, Rede Nexo, equipe e individual).',
    "# Gerado por scripts/demo_escolas/criar_contas.ps1 em $(Get-Date -Format 'yyyy-MM-dd HH:mm'). NÃO versionar.",
    ''
  )
}
if (Test-Path $destino) {
  Copy-Item $destino "$destino.bak-$(Get-Date -Format 'yyyyMMdd-HHmm')"
}
# Grava o arquivo depois de cada conta: se a API falhar no meio, as senhas já
# trocadas continuam registradas.
function Save-Contas { [IO.File]::WriteAllLines($destino, $linhas, (New-Object Text.UTF8Encoding $false)) }

$senhaIndividual = $null
foreach ($c in $contas) {
  $senha = New-SenhaDemo
  $tipo = if ($c.chave -eq 'INDIVIDUAL') { 'dev_test' } else { 'demo_comercial' }
  $meta = @{ account_type = $tipo; full_name = $c.nome }
  if ($c.cargo) { $meta.job_title = $c.cargo }
  $email = $c.email.ToLower()
  if ($SomenteNovas -and $existentes.ContainsKey($email)) {
    $corpo = @{ user_metadata = $meta } | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Method Put -Uri "$base/users/$($existentes[$email])" -Headers $h -Body ([Text.Encoding]::UTF8.GetBytes($corpo)) | Out-Null
    Write-Output "mantida (cargo atualizado): $email"
    continue
  }
  if ($existentes.ContainsKey($email)) {
    $corpo = @{ password = $senha; email_confirm = $true; user_metadata = $meta } | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Method Put -Uri "$base/users/$($existentes[$email])" -Headers $h -Body ([Text.Encoding]::UTF8.GetBytes($corpo)) | Out-Null
    Write-Output "senha redefinida: $email"
  } else {
    $corpo = @{ email = $email; password = $senha; email_confirm = $true; user_metadata = $meta } | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Method Post -Uri "$base/users" -Headers $h -Body ([Text.Encoding]::UTF8.GetBytes($corpo)) | Out-Null
    Write-Output "criada: $email"
  }
  if ($c.chave -eq 'INDIVIDUAL') { $senhaIndividual = $senha }
  $titulo = if ($c.cargo) { "$($c.nome), $($c.cargo)" } else { $c.nome }
  $linhas += "# $titulo ($($c.escola)): $($c.demonstra)"
  $linhas += "DEMO_$($c.chave)_EMAIL=$email"
  $linhas += "DEMO_$($c.chave)_SENHA=$senha"
  $linhas += ''
  Save-Contas
}
Write-Output "senhas gravadas em $destino"

# A conta individual também é a conta dos testes (MISTAKEMAP_TEST_*).
$teste = Join-Path $AppDir '.env.test.local'
if ($senhaIndividual -and (Test-Path $teste)) {
  $conteudo = Get-Content $teste -Encoding UTF8
  $conteudo = $conteudo | ForEach-Object {
    if ($_ -match '^MISTAKEMAP_TEST_PASSWORD=') { "MISTAKEMAP_TEST_PASSWORD=$senhaIndividual" } else { $_ }
  }
  [IO.File]::WriteAllLines($teste, $conteudo, (New-Object Text.UTF8Encoding $false))
  Write-Output "senha da conta de teste atualizada em $teste"
}
