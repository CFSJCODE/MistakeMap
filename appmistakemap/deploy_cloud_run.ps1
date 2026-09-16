# ==============================================================================
# Script de Deploy para Google Cloud Run (100% no Nível Gratuito / Free Tier)
# ==============================================================================

param (
    [string]$ProjectId = "",
    [string]$ServiceName = "mistakemap-web",
    [string]$Region = "us-central1"
)

# Define métricas de ambiente para conformidade
$env:CLOUDSDK_METRICS_ENVIRONMENT = "datacloud.antigravity"

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "   🚀 MistakeMap - Deploy no Google Cloud Run Free   " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

# 1. Verificar autenticação
$authAccount = gcloud auth list --filter=status:ACTIVE --format="value(account)"
if (-not $authAccount) {
    Write-Host "`n⚠️ Nenhuma conta autenticada no gcloud. Abrindo login..." -ForegroundColor Yellow
    gcloud auth login
}

# 2. Configurar ou solicitar Project ID
if ([string]::IsNullOrWhiteSpace($ProjectId)) {
    $currentProject = gcloud config get-value project 2>$null
    if (-not [string]::IsNullOrWhiteSpace($currentProject) -and $currentProject -ne "(unset)") {
        $ProjectId = $currentProject
    } else {
        Write-Host "`nInforme o ID do seu projeto no Google Cloud (GCP Project ID):" -ForegroundColor Green
        $ProjectId = Read-Host "Project ID"
    }
}

Write-Host "`n📌 Usando Projeto: $ProjectId" -ForegroundColor Green
gcloud config set project $ProjectId

# 3. Habilitar APIs necessárias (gratuitas)
Write-Host "`n⚙️ Habilitando APIs do Cloud Run e Cloud Build..." -ForegroundColor Cyan
gcloud services enable run.googleapis.com cloudbuild.googleapis.com

# 4. Deploy no Cloud Run com restrições ESTRITAS do Nível Gratuito
# - min-instances=0: Escala a zero quando ocioso (0 custo de CPU/RAM em repouso)
# - max-instances=1: Evita surpresas de tráfego/custos
# - memory=256Mi: Consumo mínimo de memória
# - cpu=1: 1 vCPU com alocação apenas durante requisições ativas
# - allow-unauthenticated: Acesso público web
Write-Host "`n📦 Compilando e publicando no Cloud Run ($Region)..." -ForegroundColor Cyan
gcloud run deploy $ServiceName `
    --source . `
    --region $Region `
    --platform managed `
    --allow-unauthenticated `
    --min-instances 0 `
    --max-instances 1 `
    --memory 256Mi `
    --cpu 1 `
    --cpu-throttling

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n=====================================================" -ForegroundColor Green
    Write-Host "   ✅ DEPLOY CONCLUÍDO COM SUCESSO!                  " -ForegroundColor Green
    Write-Host "=====================================================" -ForegroundColor Green
    
    # Obter URL pública do serviço
    $serviceUrl = gcloud run services describe $ServiceName --region $Region --format="value(status.url)"
    
    Write-Host "`n🔗 URL da sua Aplicação:" -ForegroundColor Yellow
    Write-Host "   $serviceUrl" -ForegroundColor White
    
    Write-Host "`n📊 Link do Painel de Gerenciamento do Cloud Run:" -ForegroundColor Yellow
    Write-Host "   https://console.cloud.google.com/run/detail/$Region/$ServiceName/metrics?project=$ProjectId" -ForegroundColor White
    
    Write-Host "`n🛡️ Configurações de Custo Zero Aplicadas:" -ForegroundColor Cyan
    Write-Host "   • Escala para 0 instâncias quando ocioso (--min-instances 0)"
    Write-Host "   • Limite máximo de 1 instância (--max-instances 1)"
    Write-Host "   • CPU Throttling ativado (só processa durante requisições)"
    Write-Host "   • Região us-central1 (incluída na cota gratuita do Free Tier)"
} else {
    Write-Host "`n❌ Ocorreu um erro durante o deploy." -ForegroundColor Red
}
