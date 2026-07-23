#Requires -Version 5.1
# Stage 1: Test-TunnelPortIsForeignPeer must not mutate session $Port.

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
Write-Host '=== Stage 1: foreign peer no global $Port mutation ===' -ForegroundColor White
$gitMode = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$foreign = Get-FunctionSource $gitMode 'Test-TunnelPortIsForeignPeer'
$stale = Get-FunctionSource $gitMode 'Clear-ServerStaleTunnelForward'
Assert ($foreign -notmatch '\$savedPort\s*=\s*\$Port') 'Foreign peer has no $savedPort=$Port dance'
Assert ($foreign -notmatch '(?m)^\s*\$Port\s*=') 'Foreign peer assigns no $Port='
Assert ($foreign -match 'Test-TunnelPortTcpOpen\s+-TargetPort') 'Foreign uses TcpOpen -TargetPort'
Assert ($stale -match 'Test-TunnelPortTcpOpen\s+-TargetPort') 'Stale clear uses TcpOpen -TargetPort'
Assert ($stale -notmatch '(?m)^\s*\$Port\s*=\s*\$TargetPort') 'Stale clear does not set $Port=$TargetPort'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
