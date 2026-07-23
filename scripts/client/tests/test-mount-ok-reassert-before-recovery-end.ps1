#Requires -Version 5.1
# Stage 5: Complete-PostTunnelRecovery re-probes mount before RECOVERY_END.

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
Write-Host '=== Stage 5: MountOk reassert before RECOVERY_END ===' -ForegroundColor White
$win = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$fn = Get-FunctionSource $win 'Complete-PostTunnelRecovery'
Assert ($fn.Length -gt 80) 'Complete-PostTunnelRecovery exists'
Assert ($fn -match 'Test-ProjectMountHealthy|mountpoint') 'Re-probes live mount before RECOVERY_END'
Assert ($fn -match 'RECOVERY_MOUNTOK_REASSERT|MOUNTOK_REASSERT') 'Logs reassert result'
# Must adjust MountOk when live=false before writing RECOVERY_END
$reIdx = $fn.IndexOf('RECOVERY_MOUNTOK_REASSERT')
if ($reIdx -lt 0) { $reIdx = $fn.IndexOf('MOUNTOK_REASSERT') }
$endIdx = $fn.IndexOf('RECOVERY_END')
Assert ($reIdx -ge 0 -and $endIdx -ge 0 -and $reIdx -lt $endIdx) 'Reassert happens before RECOVERY_END log'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
