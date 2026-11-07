[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)]
  [ValidatePattern('^[a-z0-9]{20}$')]
  [string]$ProjectRef,
  [switch]$MigrationsApplied,
  [switch]$DeletionWorkerConfigured
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $MigrationsApplied) {
  throw 'Aplique e confira as migrations de estudo antes de publicar as funções. Nenhuma alteração foi enviada.'
}
foreach ($functionName in @('review-queue', 'study-platform', 'upload-url')) {
  if ($PSCmdlet.ShouldProcess($functionName, 'Publicar função com autenticação no próprio handler')) {
    & supabase functions deploy $functionName --project-ref $ProjectRef --no-verify-jwt --use-api --workdir $projectRoot
    if ($LASTEXITCODE -ne 0) { throw "Falha na publicação de $functionName." }
  }
}
if ($DeletionWorkerConfigured -and $PSCmdlet.ShouldProcess('account-data', 'Publicar worker com segredo dedicado')) {
  & supabase functions deploy account-data --project-ref $ProjectRef --no-verify-jwt --use-api --workdir $projectRoot
  if ($LASTEXITCODE -ne 0) { throw 'Falha na publicação do worker.' }
}
Write-Output 'Confira autenticação, CORS e migrations no ambiente publicado antes de liberar os fluxos aos estudantes.'
