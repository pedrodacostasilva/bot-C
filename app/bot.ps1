$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Cli = Join-Path $Root 'runtime\llama\llama-cli.exe'
$Model = Join-Path $Root 'model\model.gguf'
$VC = Join-Path $Root 'portable_vc'
$System = Join-Path $Root 'app\system.txt'

if (-not (Test-Path -LiteralPath $Cli)) { throw "llama-cli.exe nao encontrado: $Cli" }
if (-not (Test-Path -LiteralPath $Model)) { throw "Modelo nao encontrado: $Model" }
if (-not (Test-Path -LiteralPath $System)) { throw "Prompt do sistema nao encontrado: $System" }

# DLLs locais, sem instalacao administrativa.
# PATH e herdado pelo processo filho; SetDllDirectory nao e necessario aqui.
if (Test-Path -LiteralPath $VC) {
    $env:PATH = "$VC;$env:PATH"
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

Write-Host '============================================' -ForegroundColor Cyan
Write-Host '              C-BOT 0.5B V8' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host 'IA local | somente C | sem servidor | sem RAG'
Write-Host 'Modelo: Qwen2.5-Coder-0.5B Q2_K'
Write-Host 'Limite: 500 tokens'
Write-Host 'Modelo fica carregado durante a sessao'
Write-Host ''
Write-Host 'Carregando modelo...' -ForegroundColor DarkGray
Write-Host ''

# Esta build b11386 funciona de forma confiavel no modo de terminal nativo.
# Nao redirecionamos stdin/stdout: a propria llama-cli controla o prompt.
$cliArgs = @(
    '-m', $Model,
    '-c', '1024',
    '-n', '500',
    '-t', '4',
    '-tb', '4',
    '--temp', '0',
    '--no-warmup',
    '--simple-io',
    '--system-prompt-file', $System
)

try {
    & $Cli @cliArgs
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Host ''
        Write-Host "llama-cli terminou com codigo $exitCode." -ForegroundColor Red
        exit $exitCode
    }
}
catch {
    Write-Host ''
    Write-Host "Erro ao iniciar llama-cli: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
