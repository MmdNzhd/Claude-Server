#Requires -Version 5.1
# test-orphan-reclaim-hard-batch.ps1
# Static asserts: keep markers, Soft HYGIENE_SOFT_PORT / down-by-port, orphan reclaim
# killswitch, ACQUIRE_ORPHAN_RECLAIMABLE, HYGIENE_DEEP, Mac parity helpers.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Orphan reclaim / keep marker / Soft hygiene hard batch ===' -ForegroundColor White

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$gmSh = Get-Content (Get-ClientFile 'git-mode.sh') -Raw
$mac = Get-Content (Get-ClientFile 'mac\connect.sh') -Raw

# --- Win keep marker API ---
Assert ($gm -match 'function Write-ConnectKeepTunnelMarker') 'Write-ConnectKeepTunnelMarker defined'
Assert ($gm -match 'function Clear-ConnectKeepTunnelMarker') 'Clear-ConnectKeepTunnelMarker defined'
Assert ($gm -match 'function Get-ConnectKeepTunnelMarkers') 'Get-ConnectKeepTunnelMarkers defined'
Assert ($gm -match 'function Test-ConnectKeepEditorProtect') 'Test-ConnectKeepEditorProtect defined'
Assert ($gm -match 'KEEP_MARKER_WRITE') 'KEEP_MARKER_WRITE log present'

# --- Orphan reclaim killswitch + once-per-Ensure ---
Assert ($gm -match 'function Invoke-ConnectOrphanReclaim') 'Invoke-ConnectOrphanReclaim defined'
Assert ($gm -match 'CLAUDE_CONNECT_AUTO_RECLAIM') 'AUTO_RECLAIM env honored'
Assert ($gm -match "CLAUDE_CONNECT_AUTO_RECLAIM.*=\s*'0'|AUTO_RECLAIM=0") 'AUTO_RECLAIM=0 killswitch branch'
Assert ($gm -match 'RECLAIM_SKIP reason=AUTO_RECLAIM=0') 'RECLAIM_SKIP log on killswitch'
Assert ($connect -match 'OrphanReclaimDoneThisEnsure\s*=\s*\$false') 'sessionLoop resets OrphanReclaimDoneThisEnsure'
Assert ($gm -match 'OrphanReclaimDoneThisEnsure') 'Ensure-SessionTunnel uses OrphanReclaimDoneThisEnsure'

# --- Soft per-port + down-by-port ---
Assert ($gm -match 'HYGIENE_SOFT_PORT') 'HYGIENE_SOFT_PORT log present'
Assert ($gm -match 'function Invoke-ConnectMountDownByPort') 'Invoke-ConnectMountDownByPort defined'
Assert ($gm -match 'down-by-port') 'down-by-port remote command wired'
Assert ($gm -match 'mount_only_down') 'Soft mount_only_down when no local -R but keep marker'
Assert ($gm -match 'Invoke-ConnectMountDownDeadBoundPorts|HYGIENE_SOFT_DEAD_BOUND') 'Soft dead-bound mount heal'

# --- Acquire orphan reclaimable / keep_editor ---
Assert ($gm -match 'ACQUIRE_ORPHAN_RECLAIMABLE') 'ACQUIRE_ORPHAN_RECLAIMABLE class'
Assert ($gm -match 'keep_editor') 'keep_editor classification present'

# --- Deep hygiene ---
Assert ($gm -match 'function Invoke-ConnectHygieneDeepClean') 'Invoke-ConnectHygieneDeepClean defined'
Assert ($gm -match 'HYGIENE_DEEP') 'HYGIENE_DEEP log present'

# --- KEEP path writes marker ---
Assert ($connect -match 'Write-ConnectKeepTunnelMarker') 'connect KEEP writes marker'
Assert ($connect -match 'Clear-ConnectKeepTunnelMarker') 'connect clears marker on quit/clear'

# --- Mac git-mode.sh parity ---
Assert ($gmSh -match 'write_connect_keep_tunnel_marker') 'Mac write_connect_keep_tunnel_marker'
Assert ($gmSh -match 'clear_connect_keep_tunnel_marker') 'Mac clear_connect_keep_tunnel_marker'
Assert ($gmSh -match 'invoke_connect_orphan_reclaim') 'Mac invoke_connect_orphan_reclaim'
Assert ($gmSh -match 'CLAUDE_CONNECT_AUTO_RECLAIM') 'Mac AUTO_RECLAIM killswitch'
Assert ($gmSh -match 'down-by-port') 'Mac Soft down-by-port'
Assert ($gmSh -match 'mount_only_down|HYGIENE_SOFT_DEAD_BOUND|invoke_connect_mount_down_dead_bound') 'Mac Soft mount-only / dead-bound heal'
Assert ($gmSh -match 'get_sibling_connect_tunnel_pids') 'Mac get_sibling_connect_tunnel_pids'
Assert ($mac -match 'write_connect_keep_tunnel_marker') 'Mac connect KEEP calls write marker'

Write-Host ''
if ($failed -eq 0) { Write-Host "All $passed assertions passed." -ForegroundColor Green; exit 0 }
Write-Host "$failed failed / $passed passed." -ForegroundColor Red; exit 1
