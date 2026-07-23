#Requires -Version 5.1
# Stage 5: PushConf refuses ACTIVE_MOUNT overwrite when other project still mounted.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}
function Get-FunctionSource {
    param([string]$Source, [string]$Name)
    $m = [regex]::Match($Source, "(?ms)^function\s+$([regex]::Escape($Name))\s*\{.*?(?=^function\s+|\z)")
    if ($m.Success) { return $m.Value }
    return ''
}

Write-Host ''
Write-Host '=== Stage 5: ACTIVE_MOUNT_GUARD ===' -ForegroundColor White
$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$push = Get-FunctionSource $gm 'Push-ServerConnectConf'
Assert ($push.Length -gt 100) 'Push-ServerConnectConf exists'
Assert ($push -match 'ACTIVE_MOUNT_GUARD') 'Logs ACTIVE_MOUNT_GUARD'
Assert ($push -match 'other_still_mounted|still_mounted') 'Guard reason other_still_mounted'
Assert ($push -match 'Test-ProjectMountHealthy') 'Guard checks live mount of current ACTIVE_MOUNT'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
