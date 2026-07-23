#Requires -Version 5.1
# Stage 3: sibling-safe orphan reclaim + hybrid primary PushConf.

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
Write-Host '=== Stage 3: orphan skip_sibling + hybrid ===' -ForegroundColor White
$git = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$orphan = Get-FunctionSource $git 'Remove-LocalOrphanTunnel'
$sib = Get-FunctionSource $git 'Get-SiblingConnectTunnelPids'
$acq = Get-FunctionSource $git 'Acquire-TunnelPort'
$push = Get-FunctionSource $git 'Push-ServerConnectConf'
$prim = Get-FunctionSource $git 'Test-IsPrimaryTunnelPublisher'

Assert ($sib.Length -gt 40) 'Get-SiblingConnectTunnelPids exists'
Assert ($orphan -match 'skip_sibling') 'Remove-LocalOrphanTunnel logs skip_sibling'
Assert ($orphan -match 'Get-SiblingConnectTunnelPids') 'Orphan cleanup merges sibling PIDs'
Assert ($acq -match 'sibling_live|sticky_shared') 'Acquire handles sibling_live / sticky_shared'
Assert ($acq -match 'Get-SiblingConnectTunnelPids') 'Acquire classifies siblings before sticky kill'
# Hybrid: UI_SLOT preferred over conf PORT reorder when slot set
Assert ($acq -match '(?s)CLAUDE_CONNECT_UI_SLOT[\s\S]{0,800}preferredPort') 'Acquire still reads UI slot + preferredPort'
Assert ($acq -match 'preferredPort.*UI slot|UI_SLOT|preferredInt') 'Acquire hybrid prefers UI slot ordering'
# Must not PushConf before orphan classify on sticky path
$stickyIdx = $acq.IndexOf('claim_sticky')
$orphanIdx = $acq.IndexOf('Remove-LocalOrphanTunnel')
$pushIdx = $acq.IndexOf('Push-ServerConnectConf')
Assert ($orphanIdx -ge 0 -and $pushIdx -ge 0 -and $orphanIdx -lt $pushIdx) 'Sticky path: orphan classify before PushConf'
Assert ($prim.Length -gt 20) 'Test-IsPrimaryTunnelPublisher exists'
Assert ($push -match 'Test-IsPrimaryTunnelPublisher|skip_non_primary') 'PushConf gates non-primary TUNNEL_PORT publish'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
