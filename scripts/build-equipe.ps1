# Gera o app "MistakeMap Equipe" (desenvolvimento e administração).
#
# É o mesmo código do app dos alunos compilado com MISTAKEMAP_TEAM_BUILD=true:
# - no Android, instala ao lado do app dos alunos (com.example.appmistakemap.equipe);
# - só aceita contas com papel admin ou developer no banco;
# - mostra os atalhos "Conta de desenvolvimento" e "Conta de admin" no login;
# - não cria contas. Este build local não usa o Shorebird; o de CI
#   (.github/workflows/team-app.yml) usa e se atualiza sozinho.
#
# As contas vêm de appmistakemap\.env.team.local (ou .env.test.local), que o
# Git ignora. Modelo: appmistakemap\.env.team.local.example. Não distribua o
# APK/EXE fora da equipe: o que estiver no arquivo vai compilado dentro dele.
#
# Uso (na raiz do repositório):
#   .\scripts\build-equipe.ps1              # Android (APK) e Windows
#   .\scripts\build-equipe.ps1 -Alvo apk
#   .\scripts\build-equipe.ps1 -Alvo windows
#   .\scripts\build-equipe.ps1 -Alvo run    # roda no dispositivo conectado
param(
    [ValidateSet('todos', 'apk', 'windows', 'run')]
    [string]$Alvo = 'todos'
)
$ErrorActionPreference = 'Stop'

$app = Join-Path $PSScriptRoot '..\appmistakemap' | Resolve-Path
$arquivo = @('.env.team.local', '.env.test.local') |
    ForEach-Object { Join-Path $app $_ } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
if (-not $arquivo) {
    throw "Crie appmistakemap\.env.team.local a partir de .env.team.local.example."
}

$defines = @(
    "--dart-define-from-file=$arquivo",
    '--dart-define=MISTAKEMAP_TEAM_BUILD=true'
)

Push-Location $app
try {
    if ($Alvo -eq 'run') {
        flutter run @defines --android-project-arg=equipe=true
        return
    }
    if ($Alvo -in 'todos', 'apk') {
        flutter build apk --release @defines --android-project-arg=equipe=true
        $apk = Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk'
        $destino = Join-Path ([Environment]::GetFolderPath('Desktop')) 'MistakeMap-Equipe-android.apk'
        Copy-Item $apk $destino -Force
        Write-Host "APK da equipe: $destino"
    }
    if ($Alvo -in 'todos', 'windows') {
        # Pasta própria: o build normal do Windows não sobrescreve o da equipe.
        flutter build windows --release @defines
        $origem = Join-Path $app 'build\windows\x64\runner\Release'
        $destino = Join-Path ([Environment]::GetFolderPath('Desktop')) 'MistakeMap-Equipe-windows'
        if (Test-Path $destino) { Remove-Item $destino -Recurse -Force }
        Copy-Item $origem $destino -Recurse
        Write-Host "Windows da equipe: $destino\appmistakemap.exe"
    }
} finally {
    Pop-Location
}
