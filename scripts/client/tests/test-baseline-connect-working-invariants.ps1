#Requires -Version 5.1
# Baseline safety-net: lock CURRENT working Connect behavior (structural source).
# Must PASS on today's tree without product changes. Does NOT lock known bugs.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}
function Get-FunctionSource {
    param([string]$Source, [string]$Name)
    $m = [regex]::Match($Source, "(?ms)^function\s+$([regex]::Escape($Name))\b.*?(?=^function\s+|\z)")
    if ($m.Success) { return $m.Value }
    return ''
}

Write-Host ''
Write-Host '=== Baseline Connect working invariants (current truth) ===' -ForegroundColor White

$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$gitMode = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$connectUi = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
$editorLaunch = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw

# 1) Start-MountProjectBackground exists and is called from session mount path
$bgFn = Get-FunctionSource $connect 'Start-MountProjectBackground'
Assert ($bgFn.Length -gt 100) 'Start-MountProjectBackground function exists'
Assert ($connect -match 'Start-MountProjectBackground\s+-ProjectId\s+\$go\.Id') 'session mount path calls Start-MountProjectBackground'
# BG up skips sync recover/check (MOUNT_CHECK_SKIPPED); recover only under GIT_MODE=off.
Assert ($connect -match 'MOUNT_CHECK_SKIPPED reason=bg_up') 'BG up path logs MOUNT_CHECK_SKIPPED reason=bg_up'
# Optional session_mount_ok TTL may sit between if ($gitModeOff) and the recover call.
Assert ($connect -match '(?ms)if\s*\(\s*\$gitModeOff\s*\)\s*\{.*?\$recoverCheckOk\s*=\s*Invoke-RecoverIfNeeded') `
    'Invoke-RecoverIfNeeded is gated by if ($gitModeOff) (not shared hide/server cold path)'
Assert ($connect -match '\$skipRemount') 'skipRemount path still present'
$bgResult = [regex]::Match(
    $connect,
    '(?ms)Start-MountProjectBackground\s+-ProjectId\s+\$go\.Id.*?\$mountResult\s*=\s*\[pscustomobject\]@\{[^}]+\}'
).Value
Assert ($bgResult.Length -gt 40) 'BG path assigns mountResult after Start-MountProjectBackground'
Assert ($bgResult -match 'Ok\s*=\s*\$false') 'BG mountResult Ok=$false (not false-green MountOk)'
Assert ($bgResult -match 'Pending\s*=\s*\$true') 'BG mountResult Pending=$true'

# 2) StepOk path includes 'started in background' for BG mount
Assert ($connect -match "StepOk\s+'started in background'") "StepOk path includes 'started in background' for BG mount"
Assert ($connect -match "started_in_background") 'BG mount result Out uses started_in_background marker'

# 3) Test-ProjectMountHealthy uses NoRetryOnTimeout
$mountHealth = Get-FunctionSource $gitMode 'Test-ProjectMountHealthy'
Assert ($mountHealth.Length -gt 50) 'Test-ProjectMountHealthy exists'
Assert ($mountHealth -match 'NoRetryOnTimeout') 'Test-ProjectMountHealthy uses NoRetryOnTimeout'

# 4) Trust path log contains 'SESSION: trusting launch result'
Assert ($connect -match "SESSION: trusting launch result") "trust path log contains 'SESSION: trusting launch result'"

# 5) Elevate-when-needed: no early Verb RunAs at top
Assert ($connect -match 'Elevate-when-needed') 'connect.ps1 documents elevate-when-needed'
$early = $connect.Substring(0, [Math]::Min(3500, $connect.Length))
Assert ($early -notmatch 'Verb RunAs') 'cold-start header has no Verb RunAs'
Assert ($connect -match 'Start-Process powershell\.exe -Verb RunAs') 'AdminFix on-demand RunAs path still present'

# 6) Day log opens with FileShare.ReadWrite
$initLog = Get-FunctionSource $connectUi 'Initialize-ConnectLog'
Assert ($initLog.Length -gt 100) 'Initialize-ConnectLog exists'
Assert ($initLog -match '\[System\.IO\.FileShare\]::ReadWrite') 'day log opens with FileShare.ReadWrite'

# 7) Sync-SessionTunnelProcess soft_fail budget / tunnel_down_debounce return $true
$syncTunnel = Get-FunctionSource $gitMode 'Sync-SessionTunnelProcess'
Assert ($syncTunnel.Length -gt 100) 'Sync-SessionTunnelProcess exists'
Assert ($gitMode -match 'TunnelSoftFailBudget') 'TunnelSoftFailBudget is defined'
Assert ($syncTunnel -match 'soft_fail') 'Sync-SessionTunnelProcess has soft_fail path'
Assert ($syncTunnel -match '(?s)tunnel_down_debounce.*?return\s+\$true') 'tunnel_down_debounce path returns $true (intentional debounce)'

# 8) Start-ProcessAsInteractiveUser uses Start-EditorProcessDirect (not Quiet)
$procAsUser = Get-FunctionSource $editorLaunch 'Start-ProcessAsInteractiveUser'
Assert ($procAsUser.Length -gt 100) 'Start-ProcessAsInteractiveUser exists'
Assert ($procAsUser -match 'Start-EditorProcessDirect\s+-FilePath') 'Start-ProcessAsInteractiveUser uses Start-EditorProcessDirect'
Assert ($procAsUser -notmatch 'Start-EditorProcessQuiet\s+-FilePath') 'Start-ProcessAsInteractiveUser does not use Quiet launcher'

# 9) @(Choose-Project -Mounts pipeline capture pattern
Assert ($connect -match 'function Choose-Project') 'Choose-Project function exists'
Assert ($connect -match '@\(Choose-Project -Mounts \$allMounts\)\[-1\]') 'pipeline-safe @(Choose-Project -Mounts ...)[-1] capture'

# 10) ConnectVersion / CONNECT_VERSION style version string present
Assert ($connect -match "ConnectVersion\s*=\s*'\d{8}\.\d+'") 'connect.ps1 has ConnectVersion dated string'
$macPath = Get-ClientFile 'mac\connect.sh'
if (Test-Path -LiteralPath $macPath) {
    $mac = Get-Content -LiteralPath $macPath -Raw
    Assert ($mac -match "CONNECT_VERSION='\d{8}\.\d+'") 'mac/connect.sh has CONNECT_VERSION dated string'
} else {
    Assert $true 'mac/connect.sh absent (skipped CONNECT_VERSION check)'
}

# Explicitly do NOT assert known-broken / not-yet-implemented items:
# - MountOk / Ok = $true after BG kick as product-correct forever
# - MOUNT_BG_BEGIN under parent FileStream
# - AUTH_STAMP_WAIT_SKIPPED
# - $script:EditorOpened = assignments
# (Skip mount check on BG IS asserted above via MOUNT_CHECK_SKIPPED + $gitModeOff gate.)


Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
