$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModelDest = Join-Path $Root 'model\model.gguf'
$LlamaDir = Join-Path $Root 'runtime\llama'
$VcDir = Join-Path $Root 'portable_vc'
$Downloads = Join-Path $env:USERPROFILE 'Downloads'
$ModelName = 'qwen2.5-coder-0.5b-instruct-q2_k.gguf'
$ModelUrl = 'https://huggingface.co/Qwen/Qwen2.5-Coder-0.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-0.5b-instruct-q2_k.gguf'
$RuntimeUrl = 'https://github.com/ggml-org/llama.cpp/releases/download/b11386/llama-b11386-bin-win-cpu-x64.zip'
$TempZip = Join-Path $Root 'runtime\llama-runtime.zip'

New-Item -ItemType Directory -Force -Path (Split-Path $ModelDest), $LlamaDir, $VcDir | Out-Null

# 1) Modelo: reaproveita o arquivo ja baixado em Downloads, ou baixa sozinho do HuggingFace.
if (-not (Test-Path $ModelDest)) {
    Write-Host 'Procurando modelo ja baixado...'
    $found = Get-ChildItem -Path $Downloads -Filter $ModelName -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 300MB } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($found) {
        Write-Host "Reutilizando: $($found.FullName)"
        Copy-Item $found.FullName $ModelDest -Force
    } else {
        Write-Host ''
        Write-Host 'Modelo nao encontrado em Downloads.'
        Write-Host 'Baixando modelo automaticamente do HuggingFace...'
        Write-Host $ModelUrl
        & curl.exe -L --fail --retry 3 --retry-delay 5 --connect-timeout 20 -o $ModelDest $ModelUrl
        if ($LASTEXITCODE -ne 0) {
            if (Test-Path $ModelDest) { Remove-Item $ModelDest -Force -ErrorAction SilentlyContinue }
            throw "Falha ao baixar o modelo. Codigo curl: $LASTEXITCODE"
        }
        Write-Host 'Modelo baixado com sucesso.'
    }
}

# 2) Runtime llama.cpp: novo, sem reaproveitar outras pastas do C-BOT antigo.
$Cli = Join-Path $LlamaDir 'llama-cli.exe'
if (-not (Test-Path $Cli)) {
    Write-Host ''
    Write-Host 'Baixando llama.cpp (Windows x64 / CPU)...'
    Write-Host $RuntimeUrl
    if (Test-Path $TempZip) { Remove-Item $TempZip -Force }
    & curl.exe -L --fail --retry 3 --connect-timeout 20 -o $TempZip $RuntimeUrl
    if ($LASTEXITCODE -ne 0) { throw "Falha ao baixar llama.cpp. Codigo curl: $LASTEXITCODE" }

    $Extract = Join-Path $Root 'runtime\llama_extracted'
    if (Test-Path $Extract) { Remove-Item $Extract -Recurse -Force }
    Expand-Archive -LiteralPath $TempZip -DestinationPath $Extract -Force

    $exe = Get-ChildItem -Path $Extract -Filter 'llama-cli.exe' -File -Recurse | Select-Object -First 1
    if (-not $exe) { throw 'llama-cli.exe nao foi encontrado dentro do pacote baixado.' }
    $SourceDir = $exe.Directory.FullName
    Copy-Item (Join-Path $SourceDir '*') $LlamaDir -Recurse -Force
    Remove-Item $Extract -Recurse -Force
    Remove-Item $TempZip -Force
}

# 3) DLLs VC++ portateis fornecidas junto deste pacote.
$vcFiles = @('vcruntime140.dll','vcruntime140_1.dll','msvcp140.dll')
foreach ($name in $vcFiles) {
    $src = Join-Path $VcDir $name
    if (-not (Test-Path $src)) { throw "DLL ausente: portable_vc\$name" }
    Copy-Item $src (Join-Path $LlamaDir $name) -Force
}

Write-Host ''
Write-Host 'Validando llama-cli...'
$env:PATH = "$VcDir;$LlamaDir;$env:PATH"
& $Cli --version
if ($LASTEXITCODE -ne 0) { throw "llama-cli nao iniciou. Codigo: $LASTEXITCODE" }

Write-Host ''
Write-Host '============================================'
Write-Host 'Instalacao concluida.'
Write-Host 'Modelo pronto.'
Write-Host 'Execute INICIAR.bat.'
Write-Host '============================================'
