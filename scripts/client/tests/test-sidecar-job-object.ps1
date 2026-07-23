# test-sidecar-job-object.ps1 - #14 Job Object on Connect-spawned sidecar tree
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Sidecar Job Object #14 (static) ===' -ForegroundColor Cyan
$s = Get-Content (Get-ClientFile 'windows\cursor-proxy-sidecar.ps1') -Raw
Assert ($s -match 'Initialize-CursorProxySidecarJob') 'Initialize-CursorProxySidecarJob present'
Assert ($s -match 'Add-CursorProxySidecarJobProcess') 'Add-CursorProxySidecarJobProcess present'
Assert ($s -match 'Stop-CursorProxySidecarJob') 'Stop-CursorProxySidecarJob present'
Assert ($s -match 'JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE') 'KILL_ON_JOB_CLOSE flag'
Assert ($s -match 'CreateKillOnCloseJob') 'CreateKillOnCloseJob helper'
Assert ($s -match 'PassThru') 'Start-Process uses PassThru for assign'
Assert ($s -match 'AssignProcessToJobObject') 'AssignProcessToJobObject P/Invoke'
# Must not look like killing arbitrary powershell
Assert ($s -notmatch 'Get-Process\s+powershell') 'Does not enumerate all powershell for kill-via-job'
if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
