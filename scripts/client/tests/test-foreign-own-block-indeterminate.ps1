#Requires -Version 5.1
# Stage 2: own-block foreign indeterminate + TTL forget.

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
Write-Host '=== Stage 2: own-block FOREIGN_INDETERMINATE + TTL ===' -ForegroundColor White
$git = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$peer = Get-FunctionSource $git 'Test-TunnelPortIsForeignPeer'
$cached = Get-FunctionSource $git 'Test-CachedForeignTunnelPort'
$forget = Get-FunctionSource $git 'Remove-ForeignTunnelPort'
$own = Get-FunctionSource $git 'Test-TunnelPortInOwnUidBlock'

Assert ($own.Length -gt 30) 'Test-TunnelPortInOwnUidBlock exists'
Assert ($forget.Length -gt 20) 'Remove-ForeignTunnelPort exists'
Assert ($peer -match 'FOREIGN_INDETERMINATE') 'Foreign peer logs FOREIGN_INDETERMINATE'
Assert ($peer -match 'Test-TunnelPortInOwnUidBlock') 'Foreign peer checks own UID block'
Assert ($cached -match 'ForeignTunnelPortTtlSec|own_block_ttl|FOREIGN_PORT forget') 'Cached foreign has own-block TTL / forget'
Assert ($git -match '\$script:ForeignTunnelPortTtlSec\s*=\s*300') 'TTL default 300s'
# Own-block must not return true on tcpOpen alone (static: indeterminate path before aggressive true)
Assert ($peer -match '(?s)FOREIGN_INDETERMINATE.*?return \$false') 'Indeterminate returns not-foreign'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
