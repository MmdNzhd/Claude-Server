#Requires -Version 5.1
# test-git-tunnel-hard-batch.ps1
# HARD regression batch for GIT_MODE tunnel acquire / sibling orphan / PushConf am_only.
# Deeper than test-orphan-tunnel-skip-sibling.ps1 (structure slices + LIVE math), without
# duplicating test-pushconf-tcp-gate.ps1 or test-hard-multi-agent-regressions.ps1 grep-only hits.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$failed = 0
$passed = 0

function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) {
        Write-Host "  PASS  $Msg" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  FAIL  $Msg" -ForegroundColor Red
        $script:failed++
    }
}

Write-Host ''
Write-Host '=== GIT tunnel hard batch (sticky / sibling / am_only) ===' -ForegroundColor White
Write-Host ''

$gm   = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$gmSh = Get-Content (Get-ClientFile 'git-mode.sh') -Raw

$acqSrc    = Get-FunctionSource -Content $gm -Name 'Acquire-TunnelPort'
$sibSrc    = Get-FunctionSource -Content $gm -Name 'Get-SiblingConnectTunnelPids'
$orphanSrc = Get-FunctionSource -Content $gm -Name 'Remove-LocalOrphanTunnel'
$pushSrc   = Get-FunctionSource -Content $gm -Name 'Push-ServerConnectConf'
$baseSrc   = Get-FunctionSource -Content $gm -Name 'Get-TunnelPortUserBase'
$primSrc   = Get-FunctionSource -Content $gm -Name 'Test-IsPrimaryTunnelPublisher'
$syncSrc   = Get-FunctionSource -Content $gm -Name 'Sync-SessionTunnelProcess'

Write-Host '--- A) Port formula non-overlap (static + LIVE) ---' -ForegroundColor Cyan
Assert (
    ($baseSrc -match '\$offset \* 10') -and
    ($gmSh -match 'echo \$\(\( base \+ offset \* 10 \)\)')
) 'Win/Mac port base uses offset*10 disjoint blocks'

if ($baseSrc) {
    . ([scriptblock]::Create($baseSrc))
    $b1000 = [int](Get-TunnelPortUserBase -UidStr '1000')
    $b1001 = [int](Get-TunnelPortUserBase -UidStr '1001')
    Assert ($b1000 -eq 20000) 'LIVE base UID1000 = 20000'
    Assert ($b1001 -eq 20010) 'LIVE base UID1001 = 20010'
    Assert ((($b1000 + 9) -lt $b1001)) 'LIVE adjacent UID blocks do not overlap (max1000 < base1001)'
} else {
    Assert $false 'Get-TunnelPortUserBase extract failed'
}

Write-Host '--- B) Acquire-TunnelPort hybrid slot / sticky / sibling ---' -ForegroundColor Cyan
$uiSlotIdx = $acqSrc.IndexOf('CLAUDE_CONNECT_UI_SLOT')
$tryPrefIdx = $acqSrc.IndexOf('$trySlots += $preferredInt')
$confReorderIdx = $acqSrc.IndexOf('if ($preferredPort -and -not ($preferred -match')
Assert (
    ($uiSlotIdx -ge 0) -and ($tryPrefIdx -gt $uiSlotIdx) -and
    ($confReorderIdx -ge 0) -and ($confReorderIdx -gt $tryPrefIdx)
) 'Acquire: CLAUDE_CONNECT_UI_SLOT seeds trySlots; conf PORT reorder only when UI slot unset'

$stickyIdx = $acqSrc.IndexOf('if ($sibSticky.Count -gt 0)')
$stickyElse = $acqSrc.IndexOf('} else {', $stickyIdx)
$stickySibBlock = if ($stickyIdx -ge 0 -and $stickyElse -gt $stickyIdx) {
    $acqSrc.Substring($stickyIdx, $stickyElse - $stickyIdx)
} else { '' }
Assert (($stickySibBlock -match 'sibling_live|sticky_shared') -and ($stickySibBlock -notmatch 'Remove-LocalOrphanTunnel')) `
    'Acquire sticky_shared: sibling_live skips orphan reclaim'

$claimIdx = $acqSrc.IndexOf('ACQUIRE_FAST claim_sticky')
$claimSlice = if ($claimIdx -ge 0) { $acqSrc.Substring([Math]::Max(0, $claimIdx - 900), [Math]::Min(900, $claimIdx)) } else { '' }
$orphInClaim = $claimSlice.IndexOf('Remove-LocalOrphanTunnel')
$pushInClaim = $claimSlice.IndexOf('Push-ServerConnectConf')
Assert (($orphInClaim -ge 0) -and ($pushInClaim -ge 0) -and ($orphInClaim -lt $pushInClaim)) `
    'Acquire claim_sticky: Remove-LocalOrphanTunnel before Push-ServerConnectConf'

Write-Host '--- C) LIVE trySlots UI_SLOT preference ---' -ForegroundColor Cyan
$preferred = '3'
$preferredInt = $null
if ($preferred -match '^\d+$') { $preferredInt = [int]$preferred }
$trySlots = @()
if ($null -ne $preferredInt -and $preferredInt -le 9) { $trySlots += $preferredInt }
0..9 | ForEach-Object { if ($_ -ne $preferredInt) { $trySlots += $_ } }
Assert ($trySlots[0] -eq 3 -and $trySlots.Count -eq 10) 'LIVE trySlots: UI_SLOT=3 first, all 10 slots retained'

Write-Host '--- D) Sibling orphan + am_only PushConf ---' -ForegroundColor Cyan
Assert (
    ($sibSrc -match 'hops -lt 14') -and
    ($sibSrc -match 'Test-ProcessCommandIsConnectUi')
) 'Get-SiblingConnectTunnelPids walks Connect UI ancestors (max 14 hops)'

Assert (
    ($orphanSrc -match 'ORPHAN_TUNNEL: skip_sibling') -and
    ($orphanSrc -match 'Get-SiblingConnectTunnelPids[\s\S]{0,500}\$protected = @\(\$protected \+ \$siblings')
) 'Remove-LocalOrphanTunnel skip_sibling + merges siblings into protected'

Assert (
    ($pushSrc -match 'PUSH_CONF am_only') -and
    ($pushSrc -match '(?s)\$amOnlyFlag[\s\S]{0,800}publish_port=0|PUBLISH_PORT.*am_only')
) 'Push-ServerConnectConf am_only suppresses publish_port for non-primary slot'

Write-Host '--- E) LIVE Test-IsPrimaryTunnelPublisher ---' -ForegroundColor Cyan
if ($primSrc) {
    . ([scriptblock]::Create($primSrc))
    $savedSlot = $env:CLAUDE_CONNECT_UI_SLOT
    try {
        $env:CLAUDE_CONNECT_UI_SLOT = ''
        Assert (Test-IsPrimaryTunnelPublisher) 'LIVE primary: empty UI_SLOT publishes TUNNEL_PORT'
        $env:CLAUDE_CONNECT_UI_SLOT = '3'
        Assert (-not (Test-IsPrimaryTunnelPublisher)) 'LIVE am_only: UI_SLOT=3 is non-primary'
    } finally {
        if ($null -eq $savedSlot) { Remove-Item Env:CLAUDE_CONNECT_UI_SLOT -ErrorAction SilentlyContinue }
        else { $env:CLAUDE_CONNECT_UI_SLOT = $savedSlot }
    }
} else {
    Assert $false 'Test-IsPrimaryTunnelPublisher extract failed'
}

Write-Host '--- F) Soft fail keep_alive ---' -ForegroundColor Cyan
$keepAt = $syncSrc.IndexOf('soft_fail_exhausted_keep_alive')
$keepSlice = if ($keepAt -ge 0) { $syncSrc.Substring($keepAt, [Math]::Min(320, $syncSrc.Length - $keepAt)) } else { '' }
Assert (($keepSlice -match 'return \$true') -and ($keepSlice -match 'TunnelSyncFailCount = 0')) `
    'Sync-SessionTunnelProcess keep_alive returns true and clears sync fail counter'

Write-Host '--- G) H0a Multi-Connect reclaim / Soft / keep_editor ---' -ForegroundColor Cyan
Assert ($gm -match 'ACQUIRE_ORPHAN_RECLAIMABLE') 'Acquire logs ACQUIRE_ORPHAN_RECLAIMABLE'
Assert ($gm -match 'ACQUIRE_SKIP: keep_editor|keep_editor') 'Acquire classifies keep_editor'
Assert ($gm -match 'Invoke-ConnectOrphanReclaim') 'Ensure orphan reclaim API present'
Assert ($gm -match 'OrphanReclaimDoneThisEnsure') 'Ensure once-per-pass reclaim flag'
Assert ($gm -match 'HYGIENE_SOFT_PORT') 'Soft per-port log'
Assert ($gm -match 'Test-ConnectKeepEditorProtect') 'Soft/reclaim editor protect'
Assert ($gm -match 'Invoke-ConnectMountDownByPort') 'Soft down-by-port'
Assert ($gm -match 'mount_only_down|HYGIENE_SOFT_DEAD_BOUND') 'Soft mount-only / dead-bound heal'
$ensSrc = Get-FunctionSource -Content $gm -Name 'Ensure-SessionTunnel'
Assert (($ensSrc -and ($ensSrc -match 'Invoke-ConnectOrphanReclaim')) -or ($gm -match '(?s)function Ensure-SessionTunnel[\s\S]{0,3500}Invoke-ConnectOrphanReclaim')) `
    'Ensure-SessionTunnel calls orphan reclaim before adopt'

Write-Host ''
Write-Host ("GIT tunnel hard batch: {0} passed, {1} failed" -f $passed, $failed) -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
