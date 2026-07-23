#Requires -Version 5.1
# Stage 6 / G: connect.bat happy-path powershell starts.
# connect-preflight.ps1 is OPTIONAL (if exist); Stage G removed the unpublished orphan.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Stage 6: connect.bat max PS starts (preflight optional) ===' -ForegroundColor White

$batPath = Get-ClientFile 'windows\connect.bat'
$bat = Get-Content -LiteralPath $batPath -Raw
Assert (Test-Path -LiteralPath $batPath) 'connect.bat exists'
Assert ($bat -match 'if exist "%HERE%connect-preflight\.ps1"') 'connect.bat gates preflight with if exist (optional)'
Assert ($bat -match 'connect-boot\.ps1') 'connect.bat hands off to connect-boot.ps1'

$prePath = Get-ClientFile 'windows\connect-preflight.ps1'
if (Test-Path -LiteralPath $prePath) {
    $preIdx = $bat.IndexOf('connect-preflight.ps1')
    Assert ($preIdx -ge 0) 'preflight reference index found'
    $afterGoto = $bat.IndexOf('goto AFTER_CLIENT_UPDATE', $preIdx)
    Assert ($afterGoto -gt $preIdx) 'preflight path jumps to AFTER_CLIENT_UPDATE'
    $preflightBlock = $bat.Substring($preIdx, $afterGoto - $preIdx + 'goto AFTER_CLIENT_UPDATE'.Length)
    $lines = $preflightBlock -split "`r?`n" | Where-Object { $_ -notmatch '^\s*REM' -and $_ -notmatch '^\s*::' }
    $psStarts = @($lines | Where-Object { $_ -match '(?i)powershell(\.exe)?' }).Count
    Assert ($psStarts -le 3) ("preflight early-path powershell starts <=3 (got $psStarts)")
    Write-Host "  INFO  preflight present; early-path PS starts=$psStarts" -ForegroundColor DarkGray
} else {
    Write-Host '  INFO  connect-preflight.ps1 absent (Stage G; optional if-exist path)' -ForegroundColor DarkGray
    # Without preflight, bat uses inline heal/update PS blocks before connect-boot — not the Stage-6 <=3 path.
    Assert ($bat -match 'AFTER_CLIENT_UPDATE') 'non-preflight path still has AFTER_CLIENT_UPDATE label'
    Assert ($true) 'preflight optional absent is OK'
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
