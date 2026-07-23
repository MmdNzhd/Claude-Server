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

$sessionMount = [regex]::Match(
    $connect,
    '(?ms)\$recoverCheckOk\s*=\s*Invoke-RecoverIfNeeded.*?\$mountResult\s*=\s*Invoke-MountProject'
).Value
Assert ($sessionMount.Length -gt 100) 'Session mount path exists'
Assert ($sessionMount -match '\$skipRemount\s*=\s*(?:\[bool\]\s*)?\$recoverCheckOk') 'Session remount decision reuses recover health result'
Assert ($sessionMount -notmatch 'Test-ProjectMountHealthy') 'Session mount path does not repeat health check'

$isMounted = Get-ShellFunctionSource $mount '_is_mounted'
Assert ($isMounted.Length -gt 20) '_is_mounted exists'
Assert ($isMounted -match 'timeout\s+-k\s+') '_is_mounted kills timed-out probe after grace'
Assert ($isMounted -notmatch '(?m)^\s*timeout\s+2\s+ls\b') '_is_mounted does not use bare timeout 2 ls'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
