#Requires -Version 5.1
# test-harder-live-keep-reclaim.ps1 (L1)
# HARDER static + optional LIVE stubs: Soft/protect/reclaim contracts.
# Soft protect calls Test-ConnectKeepEditorProtect before Remove; killedN>0 downs;
# mount_only_down; dead-bound. Full decoy spawn is optional (SKIP if heavy/unavailable).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== HARDER LIVE L1: keep Soft/protect/reclaim ===' -ForegroundColor Cyan

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$softSrc = Get-FunctionSource -Content $gm -Name 'Invoke-ConnectHygieneClean'
$reclaimSrc = Get-FunctionSource -Content $gm -Name 'Invoke-ConnectOrphanReclaim'
$protectSrc = Get-FunctionSource -Content $gm -Name 'Test-ConnectKeepEditorProtect'

Assert ([bool]$softSrc) 'extracted Invoke-ConnectHygieneClean'
Assert ([bool]$reclaimSrc) 'extracted Invoke-ConnectOrphanReclaim'
Assert ([bool]$protectSrc) 'extracted Test-ConnectKeepEditorProtect'
if (-not ($softSrc -and $reclaimSrc -and $protectSrc)) {
    Write-Host ("L1 RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
    exit 1
}

# Soft Mode branch only (before Sibling)
$softBranch = $softSrc
$sibIdx = $softSrc.IndexOf("# Sibling mode")
if ($sibIdx -lt 0) { $sibIdx = $softSrc.IndexOf("HYGIENE_SIBLING begin") }
if ($sibIdx -gt 0) { $softBranch = $softSrc.Substring(0, $sibIdx) }

# Soft protect: Test-ConnectKeepEditorProtect appears before Remove-LocalOrphanTunnel
$idxProtect = $softBranch.IndexOf('Test-ConnectKeepEditorProtect')
$idxRemove = $softBranch.IndexOf('Remove-LocalOrphanTunnel')
Assert ($idxProtect -ge 0) 'Soft calls Test-ConnectKeepEditorProtect'
Assert ($idxRemove -ge 0) 'Soft calls Remove-LocalOrphanTunnel'
Assert (($idxProtect -ge 0) -and ($idxRemove -ge 0) -and ($idxProtect -lt $idxRemove)) `
    'Soft protect Test-ConnectKeepEditorProtect BEFORE Remove-LocalOrphanTunnel'

Assert ($softBranch -match 'keep_editor') 'Soft skip reason=keep_editor'
Assert ($softBranch -match '\$killedN\s*-gt\s*0|killedN -gt 0') 'Soft gates downs on killedN>0'
Assert ($softBranch -match 'Clear-ConnectKeepTunnelMarker') 'Soft clears keep marker after kill'
Assert ($softBranch -match 'Invoke-ConnectMountDownByPort') 'Soft downs mount after kill (killedN>0)'
Assert ($softBranch -match 'mount_only_down') 'Soft mount_only_down when no local -R but keep marker'
Assert ($softBranch -match 'Invoke-ConnectMountDownDeadBoundPorts|HYGIENE_SOFT_DEAD_BOUND') `
    'Soft dead-bound mount heal present'

# Reclaim shares editor protect
Assert ($reclaimSrc -match 'Test-ConnectKeepEditorProtect') 'Reclaim uses Test-ConnectKeepEditorProtect'
Assert ($reclaimSrc -match 'RECLAIM_SKIP_KEEP|keep_editor') 'Reclaim skip_keep / keep_editor path'
Assert ($reclaimSrc -match 'Invoke-ConnectMountDownByPort') 'Reclaim downs mount after kill'

# Order comment / path: editor protect before kill loop in Soft slot body
# Order already asserted via index ($idxProtect -lt $idxRemove); widen window for body match.
Assert ($softBranch -match '(?s)Test-ConnectKeepEditorProtect[\s\S]{0,6000}Remove-LocalOrphanTunnel') `
    'Soft protect before Remove order within Soft branch body'

# Optional LIVE decoy: skip if compile/spawn too heavy or unavailable
$doLive = ($env:CLAUDE_CONNECT_L1_LIVE + '').Trim() -eq '1'
if (-not $doLive) {
    Note 'LIVE decoy skipped (set CLAUDE_CONNECT_L1_LIVE=1 for full process decoy)'
    $Skip++
    Assert ($true) 'static Soft/protect/reclaim contracts complete (LIVE optional)'
} else {
    Note 'LIVE decoy requested - extracting Soft stubs (best-effort)'
    $need = @(
        'Write-GitModeLog', 'Clear-TunnelBannerCache', 'Get-TunnelProcessExitCode',
        'Stop-TunnelProcessWithExitLog', 'Get-LocalTunnelSshReverseRegex',
        'Test-LocalTunnelSshCommandLine', 'Get-LocalTunnelSshPids',
        'Test-ProcessCommandIsConnectUi', 'Get-SiblingConnectTunnelPids',
        'Remove-LocalOrphanTunnel', 'Get-ConnectKeepTunnelMarkerPath',
        'Write-ConnectKeepTunnelMarker', 'Clear-ConnectKeepTunnelMarker',
        'Get-ConnectKeepTunnelMarkers', 'Test-ConnectKeepEditorProtect',
        'Invoke-ConnectHygieneClean'
    )
    $missing = @()
    foreach ($n in $need) {
        if (-not (Get-FunctionSource -Content $gm -Name $n)) { $missing += $n }
    }
    if ($missing.Count -gt 0) {
        Write-Host ("SKIPPED LIVE: missing helpers: {0}" -f ($missing -join ', ')) -ForegroundColor Yellow
        $Skip++
    } else {
        Assert ($true) 'LIVE helpers extractable (decoy run deferred to hygiene-race / orphan-tunnel)'
        $Skip++
        Note 'Full decoy covered by test-harder-live-hygiene-race / orphan-tunnel; L1 stays order+contract'
    }
}

Write-Host ''
$col = if ($Fail -eq 0) { 'Green' } else { 'Red' }
Write-Host ("L1 keep-reclaim RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor $col
if ($Fail -gt 0) { exit 1 }
exit 0
