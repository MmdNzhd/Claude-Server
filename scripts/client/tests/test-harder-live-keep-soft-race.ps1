#Requires -Version 5.1
# test-harder-live-keep-soft-race.ps1 (L2)
# Static HARDER: Soft uses Get-SiblingConnectTunnelPids / skip_sibling;
# Sibling mode kills Connect UI via Stop-Process; Soft does NOT Stop-Process Connect UI.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== HARDER LIVE L2: Soft sibling race / Soft vs Sibling UI kill ===' -ForegroundColor Cyan

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$softSrc = Get-FunctionSource -Content $gm -Name 'Invoke-ConnectHygieneClean'
$orphanSrc = Get-FunctionSource -Content $gm -Name 'Remove-LocalOrphanTunnel'
$sibPidSrc = Get-FunctionSource -Content $gm -Name 'Get-SiblingConnectTunnelPids'

Assert ([bool]$softSrc) 'extracted Invoke-ConnectHygieneClean'
Assert ([bool]$orphanSrc) 'extracted Remove-LocalOrphanTunnel'
Assert ([bool]$sibPidSrc) 'extracted Get-SiblingConnectTunnelPids'
if (-not ($softSrc -and $orphanSrc -and $sibPidSrc)) {
    Write-Host ("L2 RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor Red
    exit 1
}

# Split Soft vs Sibling branches
$sibIdx = $softSrc.IndexOf("# Sibling mode")
if ($sibIdx -lt 0) { $sibIdx = $softSrc.IndexOf("HYGIENE_SIBLING begin") }
Assert ($sibIdx -gt 0) 'HygieneClean has Soft then Sibling branches'
$softBranch = if ($sibIdx -gt 0) { $softSrc.Substring(0, $sibIdx) } else { $softSrc }
$sibBranch = if ($sibIdx -gt 0) { $softSrc.Substring($sibIdx) } else { '' }

# Soft path reaches Remove-LocalOrphanTunnel which uses sibling skip
Assert ($softBranch -match 'Remove-LocalOrphanTunnel') 'Soft calls Remove-LocalOrphanTunnel'
Assert ($orphanSrc -match 'Get-SiblingConnectTunnelPids') 'Remove-LocalOrphanTunnel uses Get-SiblingConnectTunnelPids'
Assert ($orphanSrc -match 'skip_sibling') 'Remove-LocalOrphanTunnel logs skip_sibling'
Assert ($softBranch -match 'Mode -eq ''Soft''|\$Mode -eq "Soft"|HYGIENE_SOFT begin') 'Soft mode branch present'

# Soft must NOT Stop-Process Connect UI (Sibling does)
Assert ($softBranch -notmatch 'Stop-Process\s+-Id\s+\$uiPid') `
    'Soft does not Stop-Process Connect UI ($uiPid)'
Assert ($softBranch -notmatch 'HYGIENE_SIBLING_STOP connect_ui') `
    'Soft branch does not log Sibling connect_ui stop'

# Sibling mode kills UI
Assert ($sibBranch -match 'Stop-Process\s+-Id\s+\$uiPid') `
    'Sibling mode kills Connect UI via Stop-Process -Id $uiPid'
Assert ($sibBranch -match 'HYGIENE_SIBLING_STOP connect_ui') `
    'Sibling logs HYGIENE_SIBLING_STOP connect_ui'
Assert ($sibBranch -match 'Stop-TunnelProcessWithExitLog') `
    'Sibling stops sibling tunnels'

# Soft still uses sibling classification indirectly (via Remove)
Assert ($gm -match '(?s)function Invoke-ConnectHygieneClean[\s\S]{0,8000}Remove-LocalOrphanTunnel') `
    'Soft hygiene path reaches Remove-LocalOrphanTunnel (sibling-safe)'

Write-Host ''
$col = if ($Fail -eq 0) { 'Green' } else { 'Red' }
Write-Host ("L2 keep-soft-race RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor $col
if ($Fail -gt 0) { exit 1 }
exit 0
