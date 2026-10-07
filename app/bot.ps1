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
Write-Host 'ENTER envia | SHIFT+ENTER quebra linha | colar multi-linha funciona' -ForegroundColor DarkGray
Write-Host "Digite 'sair' para encerrar." -ForegroundColor DarkGray
Write-Host ''
Write-Host 'Carregando modelo...' -ForegroundColor DarkGray
Write-Host ''

# Esta build b11386 funciona de forma confiavel no modo de terminal nativo.
$cliArgs = @(
    '-m', $Model,
    '-c', '4096',
    '-n', '500',
    '-t', '4',
    '-tb', '4',
    '--temp', '0',
    '--no-warmup',
    '--simple-io',
    '--system-prompt-file', $System
)

function Quote-Arg($a) {
    if ($a -match '\s|"') { '"' + ($a -replace '"', '\"') + '"' } else { $a }
}

# Converte o buffer multi-linha do usuario para o formato que o llama-cli
# entende no modo padrao (sem --multiline-input):
# toda linha intermediaria termina com '\' = continua, ultimo ENTER = envia.
function ConvertTo-LlamaInput([string]$text) {
    $lines = $text -split "`n"
    if ($lines.Count -eq 1) {
        $last = $lines[0]
        # Linha final terminando em '\' ou '/' seria interpretada como
        # continuacao; forca o envio com um espaco extra (inofensivo em C).
        if ($last.EndsWith('\') -or $last.EndsWith('/')) { $last += ' ' }
        return $last + "`n"
    }
    $out = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].TrimEnd("`r")
        if ($i -lt $lines.Count - 1) {
            if ($line.EndsWith('\')) { [void]$out.Append($line) }
            else { [void]$out.Append($line + '\') }
            [void]$out.Append("`n")
        } else {
            if ($line.EndsWith('\') -or $line.EndsWith('/')) { $line += ' ' }
            [void]$out.Append($line + "`n")
        }
    }
    return $out.ToString()
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Cli
$psi.Arguments = (($cliArgs | ForEach-Object { Quote-Arg $_ }) -join ' ')
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.CreateNoWindow = $false

try {
    $proc = [System.Diagnostics.Process]::Start($psi)
} catch {
    Write-Host ''
    Write-Host "Erro ao iniciar llama-cli: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$stdin = $proc.StandardInput
$stdin.AutoFlush = $true

try {
    while (-not $proc.HasExited) {
        $sb = New-Object System.Text.StringBuilder
        $cancelled = $false

        while ($true) {
            if ($proc.HasExited) { break }
            $key = [Console]::ReadKey($true)

            # CTRL+C: com buffer vazio sai, com texto limpa o buffer.
            if (($key.Modifiers -band [System.ConsoleModifiers]::Control) -ne 0 -and ($key.Key -eq 'C' -or $key.Key -eq 'D')) {
                if ($sb.Length -eq 0) {
                    try { $stdin.Close() } catch {}
                    try { if (-not $proc.HasExited) { $proc.WaitForExit(3000) } } catch {}
                    return
                } else {
                    $sb.Length = 0
                    [Console]::WriteLine('')
                    [Console]::WriteLine('[entrada cancelada]')
                    $cancelled = $true
                    break
                }
            }

            if ($key.Key -eq 'Enter') {
                $isShift = ($key.Modifiers -band [System.ConsoleModifiers]::Shift) -ne 0
                if ($isShift) {
                    # SHIFT+ENTER = quebra de linha, nao envia.
                    [void]$sb.Append("`n")
                    [Console]::Write("`r`n")
                    continue
                }
                # Colagem multi-linha: o console ja tem as proximas teclas
                # enfileiradas, entao esse ENTER faz parte do texto colado.
                if ([System.Console]::KeyAvailable) {
                    [void]$sb.Append("`n")
                    [Console]::Write("`r`n")
                    continue
                }
                # ENTER sozinho = envia.
                [Console]::Write("`r`n")
                break
            }
            elseif ($key.Key -eq 'Backspace') {
                if ($sb.Length -gt 0) {
                    $last = $sb.ToString()[$sb.Length - 1]
                    $sb.Length = $sb.Length - 1
                    if ($last -eq "`n") {
                        # Apagou uma quebra de linha: volta ao fim da linha anterior.
                        try {
                            $txt = $sb.ToString()
                            $idx = $txt.LastIndexOf("`n")
                            $col = if ($idx -eq -1) { $txt.Length } else { $txt.Length - $idx - 1 }
                            $top = [System.Console]::CursorTop - 1
                            if ($top -lt 0) { $top = 0 }
                            if ($col -lt 0) { $col = 0 }
                            [System.Console]::SetCursorPosition($col, $top)
                        } catch {}
                    } else {
                        [System.Console]::Write("`b `b")
                    }
                }
                continue
            }
            elseif ($key.Key -eq 'Escape') {
                $sb.Length = 0
                [Console]::WriteLine('')
                [Console]::WriteLine('[entrada cancelada]')
                $cancelled = $true
                break
            }
            else {
                $ch = $key.KeyChar
                # Ignora teclas especiais (setas, F1-F12, etc.).
                if ($ch -eq [char]0) { continue }
                if ([char]::IsControl($ch)) { continue }
                [void]$sb.Append($ch)
                [System.Console]::Write($ch)
            }
        }

        if ($proc.HasExited) { break }
        if ($cancelled) { continue }

        $text = $sb.ToString()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        $trim = $text.Trim()
        if ($trim -eq 'sair' -or $trim -eq 'exit' -or $trim -eq '/bye' -or $trim -eq '/exit' -or $trim -eq 'q') {
            try { $stdin.Close() } catch {}
            break
        }

        $payload = ConvertTo-LlamaInput $text
        try {
            $stdin.Write($payload)
        } catch {
            Write-Host ''
            Write-Host 'llama-cli encerrou a entrada.' -ForegroundColor Red
            break
        }
    }

    try { if (-not $proc.HasExited) { $proc.WaitForExit() } } catch {}
    $exitCode = try { $proc.ExitCode } catch { 0 }
    if ($exitCode -ne 0) {
        Write-Host ''
        Write-Host "llama-cli terminou com codigo $exitCode." -ForegroundColor Red
        exit $exitCode
    }
}
finally {
    try { if ($stdin) { $stdin.Close() } } catch {}
    try { if ($proc -and -not $proc.HasExited) { $proc.Kill() } } catch {}
    try { if ($proc) { $proc.Dispose() } } catch {}
}
