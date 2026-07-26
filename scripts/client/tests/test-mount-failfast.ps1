#Requires -Version 5.1
# Regression contracts for fail-fast mount health checks.

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
function Get-ShellFunctionSource {
    param([string]$Source, [string]$Name)
    $m = [regex]::Match($Source, "(?ms)^$([regex]::Escape($Name))\(\)\s*\{.*?^\}")
    if ($m.Success) { return $m.Value }
    return ''
}

Write-Host ''
Write-Host '=== Mount fail-fast contracts ===' -ForegroundColor White

$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$gitMode = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$mount = Get-Content (Get-ServerFile 'server\claude-mount.sh') -Raw

$sshX = Get-FunctionSource $connect 'SshX'
Assert ($sshX.Length -gt 100) 'SshX exists'
Assert ($sshX -match 'NoRetryOnTimeout') 'SshX supports NoRetryOnTimeout'
Assert ($sshX -match '(?s)Exit\s*-eq\s*124.*?-not\s+\$NoRetryOnTimeout') 'SshX skips timeout retry when requested'

$mountHealth = Get-FunctionSource $gitMode 'Test-ProjectMountHealthy'
Assert ($mountHealth.Length -gt 100) 'Test-ProjectMountHealthy exists'
Assert ($mountHealth -match '(?s)SshX.*check.*NoRetryOnTimeout|SshX.*NoRetryOnTimeout.*check') 'Mount health check disables timeout retry'

# Mount step backgrounded (2026-07-24) + skip sync check on BG up (2026-07-25):
# Cold BG path logs MOUNT_CHECK_SKIPPED and sets Ok=$false/Pending=$true.
# GIT_MODE=off skipRemount may still call Invoke-RecoverIfNeeded — allowed.
Assert ($connect -match 'Start-MountProjectBackground') 'Session mount path calls Start-MountProjectBackground'
Assert ($connect -match 'MOUNT_CHECK_SKIPPED reason=bg_up') 'BG up path logs MOUNT_CHECK_SKIPPED reason=bg_up'
Assert ($connect -match '\$skipRemount') 'skipRemount path still present'
Assert ($connect -match '\$skipRemount\s*=\s*(?:\[bool\]\s*)?\$recoverCheckOk') 'Session remount decision reuses recover health result'
Assert ($connect -match 'Invoke-RecoverIfNeeded') 'git=off path may still call Invoke-RecoverIfNeeded'
$bgKick = [regex]::Match(
    $connect,
    '(?ms)# User request \(2026-07-24\): don''t block.*?Start-MountProjectBackground.*?\$mountResult\s*=\s*\[pscustomobject\]@\{[^}]+\}'
).Value
if ($bgKick.Length -lt 80) {
    $bgKick = [regex]::Match(
        $connect,
        '(?ms)Step\s+"Mounting files".*?Start-MountProjectBackground.*?\$mountResult\s*=\s*\[pscustomobject\]@\{[^}]+\}'
    ).Value
}
Assert ($bgKick.Length -gt 80) 'Extracted BG kick branch'
Assert ($bgKick -match 'MOUNT_CHECK_SKIPPED reason=bg_up') 'BG kick logs MOUNT_CHECK_SKIPPED'
Assert ($bgKick -match 'Ok\s*=\s*\$false') 'BG mountResult Ok=$false'
Assert ($bgKick -match 'Pending\s*=\s*\$true') 'BG mountResult Pending=$true'
Assert ($bgKick -notmatch 'Test-ProjectMountHealthy') 'BG kick branch does not call Test-ProjectMountHealthy'

$isMounted = Get-ShellFunctionSource $mount '_is_mounted'
Assert ($isMounted.Length -gt 20) '_is_mounted exists'
Assert ($isMounted -match 'timeout\s+-k\s+') '_is_mounted kills timed-out probe after grace'
Assert ($isMounted -notmatch '(?m)^\s*timeout\s+2\s+ls\b') '_is_mounted does not use bare timeout 2 ls'


Write-Host ''
Write-Host '=== Recover / force-unmount ls probes must use timeout -k ===' -ForegroundColor White
Assert ($mount -match 'timeout -k 1 2') 'claude-mount.sh has timeout -k 1 2 probes'
Assert ($mount -notmatch '(?m)(?<!-k )\btimeout 2 ls\b') 'no bare timeout 2 ls left (recover/force-unmount)'
$recover = Get-ShellFunctionSource $mount 'cmd_recover'
if (-not $recover) {
    $i = $mount.IndexOf('cmd_recover()')
    if ($i -ge 0) { $recover = $mount.Substring($i, [Math]::Min(2500, $mount.Length - $i)) }
}
Assert ($recover.Length -gt 20) 'extracted cmd_recover'
Assert ($recover -notmatch '(?<!-k )\btimeout 2 ls\b') 'cmd_recover has no bare timeout 2 ls'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
