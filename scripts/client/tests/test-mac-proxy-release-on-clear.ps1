#Requires -Version 5.1
# test-mac-proxy-release-on-clear.ps1
# Mac clear_session_mount must release cursor proxy owner (Win Clear-SessionMount parity).

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Mac proxy release on clear_session_mount ===' -ForegroundColor White

$gitModeSh = Get-Content (Get-ClientFile 'git-mode.sh') -Raw
$gitModePs1 = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw

# Extract clear_session_mount body (bash function)
$clearMac = ''
$m = [regex]::Match($gitModeSh, '(?ms)^clear_session_mount\(\)\s*\{.*?(?=^[a-zA-Z_][a-zA-Z0-9_]*\(\)\s*\{|\z)')
if ($m.Success) { $clearMac = $m.Value }

Assert ($clearMac.Length -gt 80) 'clear_session_mount function extracted from git-mode.sh'
Assert ($clearMac -match 'release_cursor_proxy_owner') `
    'clear_session_mount body calls release_cursor_proxy_owner (Win Release-CursorProxyOwner parity)'
Assert ($gitModeSh -match '(?m)^release_cursor_proxy_owner\(\)') 'release_cursor_proxy_owner is defined in git-mode.sh'

# Win reference contract still holds (do not regress)
$clearWin = ''
$mw = [regex]::Match($gitModePs1, '(?ms)^function\s+Clear-SessionMount\b.*?(?=^function\s+|\z)')
if ($mw.Success) { $clearWin = $mw.Value }
Assert ($clearWin -match 'Release-CursorProxyOwner') 'Win Clear-SessionMount still calls Release-CursorProxyOwner'

if ($failed -gt 0) {
    Write-Host "FAILED $failed" -ForegroundColor Red
    exit 1
}
Write-Host 'All Mac proxy-release-on-clear asserts passed' -ForegroundColor Green
exit 0
