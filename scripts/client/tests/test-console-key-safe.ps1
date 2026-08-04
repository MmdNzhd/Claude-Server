#Requires -Version 5.1
# test-console-key-safe.ps1
# Proves redirected-stdin no longer throws (the UNHANDLED KeyAvailable crash).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== Console key safe (redirected stdin) ===' -ForegroundColor Cyan

$ui = Get-Content -LiteralPath (Get-ClientFile 'connect-ui.ps1') -Raw
$win = Get-Content -LiteralPath (Get-ClientFile 'windows\connect.ps1') -Raw
$gm = Get-Content -LiteralPath (Get-ClientFile 'git-mode.ps1') -Raw

Assert ($ui -match 'function Test-ConnectConsoleInteractive') 'connect-ui has Test-ConnectConsoleInteractive'
Assert ($ui -match 'function Clear-ConnectConsoleKeyBuffer') 'connect-ui has Clear-ConnectConsoleKeyBuffer'
Assert ($ui -match 'function Read-ConnectConsoleKey') 'connect-ui has Read-ConnectConsoleKey'
Assert ($ui -match 'IsInputRedirected') 'helper checks IsInputRedirected'
Assert ($win -notmatch '\[Console\]::KeyAvailable') 'connect.ps1 has zero raw KeyAvailable'
Assert ($win -match 'Clear-ConnectConsoleKeyBuffer') 'connect.ps1 drains via Clear-ConnectConsoleKeyBuffer'
Assert ($win -match 'Read-ConnectConsoleKey') 'connect.ps1 session loop uses Read-ConnectConsoleKey'
Assert ($win -match 'noninteractive_stdin') 'connect.ps1 logs noninteractive_stdin'
Assert ($gm -match 'Read-ConnectConsoleKey') 'git-mode prefers Read-ConnectConsoleKey'
# Fleet day-log pollution: UNHANDLED dumped multi-line PositionMessage (bare "+ while ..." lines).
Assert ($win -match 'PositionMessage' -and $win -match "-replace '\[\\r\\n\]\+'") 'UNHANDLED trap collapses PositionMessage newlines'
Assert ($ui -match "\`$Message = \(\(\`$Message \+ ''\) -replace '\[\\r\\n\]\+'") 'Write-ConnectLog collapses message newlines'
Assert ($ui -match 'askEnter' -and $ui -match 'Test-ConnectConsoleInteractive') 'Wait-ConnectExit gates Read-Host via askEnter/interactive'

# Live: child with redirected stdin must NOT throw on helpers
$proof = Join-Path $env:TEMP ("cc-keysafe-proof-{0}.ps1" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$uiPath = (Get-ClientFile 'connect-ui.ps1')
@(
    '$ErrorActionPreference = ''Stop'''
    ". '$($uiPath -replace '''', '''''')'"
    # Minimal stubs so connect-ui load does not die on missing log helpers mid-dot-source
    'try { Clear-ConnectConsoleKeyBuffer } catch { Write-Output ("THROW_CLEAR=" + $_.Exception.Message); exit 2 }'
    'try { $k = Read-ConnectConsoleKey; Write-Output ("KEY_NULL=" + ($null -eq $k)) } catch { Write-Output ("THROW_READ=" + $_.Exception.Message); exit 3 }'
    'try { $i = Test-ConnectConsoleInteractive; Write-Output ("INTERACTIVE=" + $i) } catch { Write-Output ("THROW_INTER=" + $_.Exception.Message); exit 4 }'
    'Write-Output ''PROOF_OK'''
    'exit 0'
) | Set-Content -LiteralPath $proof -Encoding ASCII

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'powershell.exe'
$psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$proof`""
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
try { $p.StandardInput.Close() } catch {}
$out = $p.StandardOutput.ReadToEnd()
$err = $p.StandardError.ReadToEnd()
$p.WaitForExit(15000) | Out-Null
Remove-Item -LiteralPath $proof -Force -ErrorAction SilentlyContinue

Assert ($out -match 'PROOF_OK') ("redirected-stdin helper proof OK (exit=$($p.ExitCode))")
Assert ($out -notmatch 'THROW_') 'no THROW_* from helpers under redirected stdin'
Assert ($err -notmatch 'KeyAvailable|Console\.In\.Peek') 'stderr has no KeyAvailable crash'
if ($out -match 'INTERACTIVE=') {
    Assert ($out -match 'INTERACTIVE=False') 'IsInputRedirected path reports non-interactive'
}

Write-Host ''
Write-Host ("RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { Write-Host $out; if ($err) { Write-Host $err }; exit 1 }
exit 0
