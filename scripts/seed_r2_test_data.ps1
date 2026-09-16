# seed_r2_test_data.ps1
# Gera imagens placeholder e faz upload para o Cloudflare R2.
# Uso: .\scripts\seed_r2_test_data.ps1

$ErrorActionPreference = "Stop"

# --------------------------------------------------------------------------
# Configuracao R2 (mesmos valores do worker/.env)
# --------------------------------------------------------------------------
# Le as credenciais de worker/.env (gitignored). Elas NAO ficam neste arquivo,
# que e versionado num repositorio publico.
$EnvFile = Join-Path $PSScriptRoot "..\worker\.env"
if (-not (Test-Path $EnvFile)) { throw "worker/.env nao encontrado em: $EnvFile" }

$Cfg = @{}
Get-Content $EnvFile | Where-Object { $_ -match '^\s*[^#\s].*=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2
    $Cfg[$k.Trim()] = $v.Trim()
}

$Env:AWS_ACCESS_KEY_ID     = $Cfg['CLOUDFLARE_R2_ACCESS_KEY_ID']
$Env:AWS_SECRET_ACCESS_KEY = $Cfg['CLOUDFLARE_R2_SECRET_ACCESS_KEY']
$Env:AWS_DEFAULT_REGION    = "auto"
$ENDPOINT = $Cfg['CLOUDFLARE_R2_S3_ENDPOINT']
$BUCKET   = $Cfg['CLOUDFLARE_R2_BUCKET']

# --------------------------------------------------------------------------
# Dados imaginarios: 2 alunos, cada um com 3 tentativas, 1-2 imagens cada
# --------------------------------------------------------------------------
$TestData = @(
    @{ UserId = "user-aluno-alpha-0001"; Attempts = @(
        @{ Label = "Derivada parcial - calculo 2"; Assets = @("foto_caderno","enunciado") },
        @{ Label = "Limite indeterminado 0/0";     Assets = @("foto_caderno") },
        @{ Label = "Integral por partes";           Assets = @("foto_caderno","rascunho") }
    )},
    @{ UserId = "user-aluno-beta-0002";  Attempts = @(
        @{ Label = "Circuito RC serie - fisica";   Assets = @("foto_caderno") },
        @{ Label = "Lei de Kirchhoff malha dupla"; Assets = @("foto_caderno","enunciado") },
        @{ Label = "Vetor posicao e aceleracao";   Assets = @("foto_caderno") }
    )}
)

# --------------------------------------------------------------------------
# Funcao: cria uma imagem PNG 800x600 com texto usando System.Drawing
# --------------------------------------------------------------------------
Add-Type -AssemblyName System.Drawing

function New-PlaceholderImage {
    param(
        [string]$OutputPath,
        [string]$Titulo,
        [string]$Subtitulo,
        [System.Drawing.Color]$CorFundo
    )

    $bmp = New-Object System.Drawing.Bitmap(800, 600)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)

    # Fundo colorido
    $g.FillRectangle(
        (New-Object System.Drawing.SolidBrush($CorFundo)),
        0, 0, 800, 600
    )

    # Borda interna simulando papel
    $g.FillRectangle([System.Drawing.Brushes]::White, 40, 40, 720, 520)

    # Linhas de caderno
    $penLinha = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200, 180, 210, 240), 1)
    for ($y = 100; $y -lt 530; $y += 30) {
        $g.DrawLine($penLinha, 60, $y, 740, $y)
    }

    # Margem vermelha
    $penMargem = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180, 220, 80, 80), 2)
    $g.DrawLine($penMargem, 110, 50, 110, 550)

    # Titulo
    $fontTitulo = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $g.DrawString($Titulo, $fontTitulo, [System.Drawing.Brushes]::DarkSlateBlue, 130, 60)

    # Subtitulo / label
    $fontSub = New-Object System.Drawing.Font("Segoe UI", 12)
    $g.DrawString($Subtitulo, $fontSub, [System.Drawing.Brushes]::Gray, 130, 95)

    # Texto simulando resolucao manuscrita
    $fontManu = New-Object System.Drawing.Font("Segoe UI", 11)
    $linhas = @(
        "f(x,y) = x^2 + 3xy - y^2",
        "df/dx = 2x + 3y",
        "df/dy = 3x - 2y",
        "",
        "Ponto critico: (0,0)",
        "Hessiana H = | 2    3 |",
        "             | 3   -2 |",
        "det(H) = -4 - 9 = -13 < 0  => ponto de sela",
        "",
        "ERRO: sinal da derivada parcial em y invertido"
    )
    $yPos = 130
    foreach ($linha in $linhas) {
        $g.DrawString($linha, $fontManu, [System.Drawing.Brushes]::Black, 130, $yPos)
        $yPos += 30
    }

    # Marca d'agua [TESTE]
    $fontWm = New-Object System.Drawing.Font("Segoe UI", 48, [System.Drawing.FontStyle]::Bold)
    $brush  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(18, 100, 100, 200))
    $g.TranslateTransform(400, 300)
    $g.RotateTransform(-30)
    $g.DrawString("[DADO DE TESTE]", $fontWm, $brush, -260, -30)
    $g.ResetTransform()

    $g.Dispose()
    $bmp.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

# --------------------------------------------------------------------------
# Cores por aluno para diferenciar visualmente
# --------------------------------------------------------------------------
$Cores = @(
    [System.Drawing.Color]::FromArgb(255, 230, 240, 255),  # azul claro
    [System.Drawing.Color]::FromArgb(255, 230, 255, 235)   # verde claro
)

# --------------------------------------------------------------------------
# Loop principal: gera imagem → upload → limpa
# --------------------------------------------------------------------------
$tmpDir = Join-Path $env:TEMP "mistakemap_seed"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

$total  = 0
$falhas = 0

foreach ($i in 0..($TestData.Count - 1)) {
    $aluno = $TestData[$i]
    $cor   = $Cores[$i % $Cores.Count]

    Write-Host "`n=== Aluno: $($aluno.UserId) ===" -ForegroundColor Cyan

    foreach ($tentativa in $aluno.Attempts) {
        Write-Host "  Tentativa: $($tentativa.Label)" -ForegroundColor Yellow

        foreach ($assetLabel in $tentativa.Assets) {
            $uuid      = [System.Guid]::NewGuid().ToString()
            $objPath   = "uploads/$($aluno.UserId)/$uuid.png"
            $localFile = Join-Path $tmpDir "$uuid.png"

            # Gerar imagem
            New-PlaceholderImage `
                -OutputPath $localFile `
                -Titulo     $tentativa.Label `
                -Subtitulo  "Asset: $assetLabel | Aluno: $($aluno.UserId.Split('-')[2])" `
                -CorFundo   $cor

            # Upload para R2
            Write-Host "    -> $objPath" -NoNewline
            try {
                aws s3 cp $localFile "s3://$BUCKET/$objPath" `
                    --endpoint-url $ENDPOINT `
                    --no-progress 2>&1 | Out-Null
                Write-Host "  OK" -ForegroundColor Green
                $total++
            } catch {
                Write-Host "  FALHA: $_" -ForegroundColor Red
                $falhas++
            }

            Remove-Item $localFile -Force
        }
    }
}

Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n==============================" -ForegroundColor Cyan
Write-Host "Uploads: $total ok, $falhas falhas" -ForegroundColor $(if ($falhas -eq 0) {"Green"} else {"Yellow"})
Write-Host "Bucket:  https://dash.cloudflare.com/954f3233c7c998b8e862c1a59673d9a0/r2/default/buckets/$BUCKET"
