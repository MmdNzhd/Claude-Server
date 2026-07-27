#Requires -Version 5.1
# test-windows-mcp-hard-batch.ps1
# HARD batch gate for windows-mcp laptop bootstrap invariants:
#   no cmd /c netstat, CreateNoWindow netstat fallback, orphan cmd reaper,
#   port ensure on scheduled task, winget WindowStyle Hidden,
#   python -m windows_mcp serve (no cmd wrapper), Unblock-File MOTW,
#   never Set-MpPreference.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== HARD: windows-mcp batch invariants ===' -ForegroundColor White
Write-Host ''

$mcpPath = Get-ClientFile 'windows\windows-mcp-laptop.ps1'
$workerPath = Join-Path $script:RepoRoot 'publish\_setup-worker-body.ps1'
$launchPath = Join-Path $script:RepoRoot 'publish\_setup-launch-body.ps1'

$mcp = Get-Content -LiteralPath $mcpPath -Raw
$worker = Get-Content -LiteralPath $workerPath -Raw
$launch = Get-Content -LiteralPath $launchPath -Raw

$listenFn = Get-FunctionSource $mcp 'Test-WindowsMcpListening'
$directFn = Get-FunctionSource $mcp 'Start-WindowsMcpProcessDirect'
$reaperFn = Get-FunctionSource $mcp 'Stop-WindowsMcpOrphanCmdWrappers'
$taskFn = Get-FunctionSource $mcp 'Ensure-WindowsMcpTask'
$wingetFn = Get-FunctionSource $mcp 'Invoke-WindowsMcpWingetInstall'
$startFn = Get-FunctionSource $mcp 'Start-WindowsMcpIfNeeded'

Assert ($listenFn -match '\$psi\.FileName = \(Join-Path \$env:SystemRoot ''System32\\netstat\.exe''\)') `
    'Listen fallback ProcessStartInfo targets netstat.exe (not cmd /c)'
Assert ($listenFn -match 'CreateNoWindow\s*=\s*\$true' -and $listenFn -match 'UseShellExecute\s*=\s*\$false') `
    'Listen netstat fallback is headless (CreateNoWindow + UseShellExecute=false)'
Assert ($mcp -notmatch '(?i)cmd\s+/c\s+["'']?netstat') 'Module has no cmd /c netstat anywhere'

Assert ($reaperFn -and $reaperFn -match 'Test-WindowsMcpListening') `
    'Orphan reaper runs only after listen probe succeeds'
Assert ($reaperFn -match 'start-server\.cmd' -and $reaperFn -match 'windows-mcp' -and $reaperFn -match 'orphan_cmd_reaped') `
    'Orphan reaper targets cmd.exe start-server.cmd wrappers and logs reaped pid'

Assert ($taskFn -and $taskFn -match 'needInstall' -and $taskFn -match 'start-server\.cmd' -and $taskFn -match '--port') `
    'Ensure-WindowsMcpTask reinstalls when start-server.cmd port is stale'

Assert ($wingetFn -and $wingetFn -match 'Start-Process' -and $wingetFn -match 'WindowStyle\s+Hidden') `
    'Winget install uses Start-Process -WindowStyle Hidden'
Assert ($wingetFn -match 'WaitForExit\(600000\)' -and $wingetFn -match 'winget_timeout') `
    'Winget install is bounded (10m) and kills on timeout'

Assert ($directFn -and $directFn -match '-m windows_mcp serve') `
    'Direct start uses python -m windows_mcp serve'
Assert ($directFn -notmatch '(?m)^[^\#]*cmd\.exe' -and $directFn -notmatch '(?m)^[^\#]*start-server\.cmd') `
    'Direct start never wraps via cmd.exe or start-server.cmd (code lines only)'
Assert ($directFn -match 'CreateNoWindow\s*=\s*\$true' -and $directFn -match 'ProcessWindowStyle\]::Hidden') `
    'Direct start ProcessStartInfo is fully hidden'

Assert ($startFn -match 'Stop-WindowsMcpOrphanCmdWrappers' -and $startFn -match 'Start-WindowsMcpProcessDirect') `
    'Start-WindowsMcpIfNeeded uses direct start and orphan reaper'
Assert (-not [regex]::IsMatch($startFn, '(?m)^\s*try\s*\{\s*schtasks\s+/Run')) `
    'Start-WindowsMcpIfNeeded has no schtasks /Run (visible cmd)'
Assert ($mcp -match 'Write-WindowsMcpHiddenLogonLauncher') `
    'Hidden logon VBS launcher helper is shipped'
Assert ($mcp -match 'start-server-hidden\.vbs') `
    'Hidden logon trampoline uses start-server-hidden.vbs'

Assert ($worker -match 'Unblock-File' -and $worker -match 'Get-ChildItem' -and $worker -match 'unblock_motw') `
    'setup-worker clears MOTW via Unblock-File on installed files'

$defenderHay = ($mcp + "`n" + $worker + "`n" + $launch)
Assert ($defenderHay -notmatch '(?i)Set-MpPreference') `
    'windows-mcp + setup bodies never call Set-MpPreference'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
Write-Host 'HARD windows-mcp batch: ALL PASS' -ForegroundColor Green
exit 0
