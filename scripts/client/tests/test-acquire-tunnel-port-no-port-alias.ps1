#Requires -Version 5.1
# Stage 1 RED/GREEN: Acquire-TunnelPort must not use lowercase $port= (aliases $Port).

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0
$passed = 0

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
Write-Host '=== Stage 1: Acquire no $port alias + Get-SessionTunnelPort ===' -ForegroundColor White

$gitMode = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$acquire = Get-FunctionSource $gitMode 'Acquire-TunnelPort'
$getSess = Get-FunctionSource $gitMode 'Get-SessionTunnelPort'
$push = Get-FunctionSource $gitMode 'Push-ServerConnectConf'
$foreign = Get-FunctionSource $gitMode 'Test-TunnelPortIsForeignPeer'
$tcp = Get-FunctionSource $gitMode 'Test-TunnelPortTcpOpen'
$banner = Get-FunctionSource $gitMode 'Get-TunnelBanner'

Assert ($acquire.Length -gt 200) 'Acquire-TunnelPort function extracted'
Assert ($getSess.Length -gt 40) 'Get-SessionTunnelPort exists'
# Case-sensitive: lowercase $port= is the alias bug; $Port = $script:Port sync is required.
$hasLowerPortAssign = [regex]::IsMatch($acquire, '(?m)^\s*\$port\s*=')
Assert (-not $hasLowerPortAssign) 'Acquire-TunnelPort has no lowercase $port= assignments'
Assert ($acquire -match '\$candPort\s*=') 'Acquire-TunnelPort uses $candPort'
Assert ([regex]::IsMatch($acquire, '(?m)^\s*\$Port\s*=\s*\$script:Port')) 'Acquire syncs $Port = $script:Port after claim'
Assert ($push -match 'Get-SessionTunnelPort') 'Push-ServerConnectConf uses Get-SessionTunnelPort'
Assert ($push -match 'PORT_SHADOW_DETECT') 'Push-ServerConnectConf logs PORT_SHADOW_DETECT'
Assert ($foreign -notmatch '(?m)^\s*\$Port\s*=\s*\$TargetPort') 'Foreign peer does not assign $Port = $TargetPort'
Assert ($tcp -match 'TargetPort') 'Test-TunnelPortTcpOpen accepts TargetPort'
Assert ($banner -match 'TargetPort') 'Get-TunnelBanner accepts TargetPort'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
