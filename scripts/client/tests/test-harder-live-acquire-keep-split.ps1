#Requires -Version 5.1
# test-harder-live-acquire-keep-split.ps1 (L4)
# Acquire classifies ACQUIRE_ORPHAN_RECLAIMABLE vs keep_editor vs sibling_live;
# Remove-LocalOrphanTunnel used for reclaimable sticky/busy paths.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== HARDER LIVE L4: Acquire keep/orphan/sibling split ===' -ForegroundColor Cyan

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw

# Find Acquire function by reclaimable token proximity
$acqName = $null
foreach ($cand in @(
    'Acquire-ConnectTunnelSlot', 'Acquire-SessionTunnelSlot', 'Get-AcquireConnectTunnelSlot',
    'Invoke-AcquireConnectTunnel', 'Acquire-TunnelPort'
)) {
    if (Get-FunctionSource -Content $gm -Name $cand) { $acqName = $cand; break }
}
if (-not $acqName) {
    # Brace-extract around first ACQUIRE_ORPHAN_RECLAIMABLE by walking back to function
    $tok = $gm.IndexOf('ACQUIRE_ORPHAN_RECLAIMABLE')
    Assert ($tok -ge 0) 'ACQUIRE_ORPHAN_RECLAIMABLE present in git-mode.ps1'
    if ($tok -ge 0) {
        $before = $gm.Substring(0, $tok)
        $fm = [regex]::Matches($before, 'function\s+(\w+)')
        if ($fm.Count -gt 0) { $acqName = $fm[$fm.Count - 1].Groups[1].Value }
    }
}
Assert ([bool]$acqName) ("Acquire function name resolved: {0}" -f $acqName)
$acqSrc = if ($acqName) { Get-FunctionSource -Content $gm -Name $acqName } else { $null }
Assert ([bool]$acqSrc) 'extracted Acquire function body'

if ($acqSrc) {
    Assert ($acqSrc -match 'ACQUIRE_ORPHAN_RECLAIMABLE') 'Acquire logs ACQUIRE_ORPHAN_RECLAIMABLE'
    Assert ($acqSrc -match 'keep_editor') 'Acquire classifies keep_editor'
    Assert ($acqSrc -match 'sibling_live') 'Acquire classifies sibling_live'
    Assert ($acqSrc -match 'Get-SiblingConnectTunnelPids') 'Acquire uses Get-SiblingConnectTunnelPids'
    Assert ($acqSrc -match 'Get-ConnectKeepTunnelMarkers|keepMarkersAcq') 'Acquire reads keep markers'
    # Classification order comment
    Assert ($acqSrc -match 'sibling_live\s*/\s*keep_editor\s*/\s*ACQUIRE_ORPHAN_RECLAIMABLE|Classify: sibling_live') `
        'Acquire documents sibling_live / keep_editor / ORPHAN_RECLAIMABLE split'
    # Reclaimable path uses Remove-LocalOrphanTunnel (sticky or busy reclaim)
    Assert ($acqSrc -match 'Remove-LocalOrphanTunnel') `
        'Acquire calls Remove-LocalOrphanTunnel for reclaimable/sticky paths'
}

$orphanSrc = Get-FunctionSource -Content $gm -Name 'Remove-LocalOrphanTunnel'
Assert ([bool]$orphanSrc) 'Remove-LocalOrphanTunnel extractable'
Assert ($orphanSrc -match 'unprotected_live|skip_sibling') 'Orphan remove distinguishes sibling vs unprotected'

Write-Host ''
$col = if ($Fail -eq 0) { 'Green' } else { 'Red' }
Write-Host ("L4 acquire-keep-split RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor $col
if ($Fail -gt 0) { exit 1 }
exit 0
