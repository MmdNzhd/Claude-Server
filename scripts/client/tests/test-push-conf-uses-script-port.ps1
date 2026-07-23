#Requires -Version 5.1
# Stage 1: PushConf payload/dedupe must prefer $script:Port / Get-SessionTunnelPort.

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
Write-Host '=== Stage 1: PushConf uses session tunnel port ===' -ForegroundColor White
$gitMode = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$push = Get-FunctionSource $gitMode 'Push-ServerConnectConf'
Assert ($push -match '\$sessionPort\s*=\s*Get-SessionTunnelPort') 'PushConf assigns $sessionPort = Get-SessionTunnelPort'
Assert ($push -match '\$LaptopUser,\s*\$sessionPort') 'dedupeKey uses sessionPort'
Assert ($push -match '\$portEsc\s*=\s*\(\"\$sessionPort\"') 'portEsc from sessionPort'
Assert ($push -match "PORT='\`$portEsc'") 'remote body sets PORT via $portEsc'
Assert ($push -match 'PORT_SHADOW_DETECT') 'PORT_SHADOW_DETECT present'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
