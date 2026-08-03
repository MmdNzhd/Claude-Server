#Requires -Version 5.1
# test-harder-live-slot-storm-keep.ps1 (L5)
# Static 10-slot anti-amir wall-at-2 contract:
# Soft loops 0..9; protect skips; reclaim ProtectSet; AUTO_RECLAIM=0 killswitch.
# Documents: Soft/reclaim must never kill siblings/KEEP across the UID 10-port block.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '=== HARDER LIVE L5: 10-slot Soft/reclaim KEEP storm (anti-amir wall-at-2) ===' -ForegroundColor Cyan
Note 'Contract: N=1..10 concurrent Connect/KEEP must not wall at ~2 (amir-class peer_live stranding)'

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$softSrc = Get-FunctionSource -Content $gm -Name 'Invoke-ConnectHygieneClean'
$reclaimSrc = Get-FunctionSource -Content $gm -Name 'Invoke-ConnectOrphanReclaim'

Assert ([bool]$softSrc) 'extracted Invoke-ConnectHygieneClean'
Assert ([bool]$reclaimSrc) 'extracted Invoke-ConnectOrphanReclaim'

$sibIdx = $softSrc.IndexOf("# Sibling mode")
if ($sibIdx -lt 0) { $sibIdx = $softSrc.IndexOf("HYGIENE_SIBLING begin") }
$softBranch = if ($sibIdx -gt 0) { $softSrc.Substring(0, $sibIdx) } else { $softSrc }

# Soft loops slots 0..9
Assert ($softBranch -match 'for\s*\(\s*\$slot\s*=\s*0\s*;\s*\$slot\s*-lt\s*10') `
    'Soft loops slot 0..9 (10-port UID block)'
Assert ($softBranch -match '\$base\s*\+\s*\$slot|\$port\s*=\s*\$base') `
    'Soft computes port = base + slot'

# Protect skips (keep_editor / protect_root) continue without Remove
Assert ($softBranch -match 'skipProtect|action=skip reason=keep_editor') `
    'Soft protect skips keep_editor ports'
Assert ($softBranch -match 'if\s*\(\s*\$skipProtect\s*\)\s*\{\s*continue') `
    'Soft continue on skipProtect (siblings/KEEP survive)'

# Reclaim ProtectSet + preferred pin + sibling merge
Assert ($reclaimSrc -match 'ProtectSet') 'Reclaim accepts ProtectSet'
Assert ($reclaimSrc -match 'for\s*\(\s*\$slot\s*=\s*0\s*;\s*\$slot\s*-lt\s*10') `
    'Reclaim loops slot 0..9'
Assert ($reclaimSrc -match 'Get-SiblingConnectTunnelPids') 'Reclaim merges sibling PIDs into protect'
Assert ($reclaimSrc -match 'RECLAIM_SKIP_KEEP|preferred_pin|keep_editor') `
    'Reclaim skips KEEP / preferred pin'

# AUTO_RECLAIM=0 killswitch (operator escape / anti-footgun)
Assert ($reclaimSrc -match "CLAUDE_CONNECT_AUTO_RECLAIM.*=\s*'0'|AUTO_RECLAIM=0") `
    'AUTO_RECLAIM=0 killswitch branch'
Assert ($reclaimSrc -match 'RECLAIM_SKIP reason=AUTO_RECLAIM=0') `
    'RECLAIM_SKIP log on AUTO_RECLAIM=0'

# Anti-amir: Acquire must not permanently peer_live strand reclaimable orphans
Assert ($gm -match 'ACQUIRE_ORPHAN_RECLAIMABLE') 'Acquire marks reclaimable (not permanent peer_live)'
Assert ($gm -match 'not permanent peer_live|not permanent peer_live') `
    'Acquire comment: orphan reclaimable is not permanent peer_live'

Write-Host ''
$col = if ($Fail -eq 0) { 'Green' } else { 'Red' }
Write-Host ("L5 slot-storm-keep RESULT: {0} pass / {1} fail (anti-amir wall-at-2 static)" -f $Pass, $Fail) -ForegroundColor $col
if ($Fail -gt 0) { exit 1 }
exit 0
