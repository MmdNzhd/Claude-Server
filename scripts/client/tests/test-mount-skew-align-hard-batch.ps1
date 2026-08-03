#Requires -Version 5.1
# test-mount-skew-align-hard-batch.ps1
# HARD gate: three-way skew (OK / DEFERRED / ALIGN conf-only / SKEW remount),
# down-by-port, self-heal ALIGN-before-stale, keep Soft down-by-port wiring.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Mount skew / ALIGN / Soft down-by-port hard batch ===' -ForegroundColor White

$mount = Get-Content (Get-ServerFile 'server\claude-mount.sh') -Raw
$healPath = Get-ServerFile 'server\claude-self-heal.sh'
$heal = if (Test-Path $healPath) { Get-Content -LiteralPath $healPath -Raw } else { '' }
$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$gmSh = Get-Content (Get-ClientFile 'git-mode.sh') -Raw
$mac = Get-Content (Get-ClientFile 'mac\connect.sh') -Raw
$ui = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw

Assert ($mount -match '_mount_skew_keep_fuse') 'claude-mount has _mount_skew_keep_fuse'
Assert ($mount -match 'MOUNT_PORT_SKEW_DEFERRED') 'DEFERRED log present'
Assert ($mount -match 'MOUNT_PORT_SKEW_ALIGN') 'ALIGN log present'
Assert ($mount -match '_align_conf_tunnel_to_live') 'ALIGN conf rewrite helper present'
Assert ($mount -match 'down-by-port') 'down-by-port command present'
Assert ($mount -match 'MOUNT_SHARED_P') 'MOUNT_SHARED_P warn present'

$skewFn = ''
if ($mount -match '(?s)_mount_skew_keep_fuse\(\)\s*\{(.{200,8000}?)(?:\n[a-z_]+\(|\n# ===)') {
    $skewFn = $Matches[1]
}
Assert ([bool]$skewFn) 'extracted _mount_skew_keep_fuse body'
Assert ($skewFn -match '_align_conf_tunnel_to_live') 'ALIGN calls conf rewrite'
# Remount is return 1 from this function (caller unmounts); ALIGN path itself must not call fusermount.
Assert ($skewFn -match 'never fusermount|MOUNT_PORT_SKEW_ALIGN') 'ALIGN branch present'
Assert ($skewFn -notmatch '(?m)^\s*fusermount') 'ALIGN keep fn does not invoke fusermount'

Assert ($mount -match '(?s)cmd_down\(\)[\s\S]{0,800}_in_proc_mounts') 'cmd_down uses _in_proc_mounts'

if ($heal) {
    Assert ($heal -match 'align|ALIGN|live_sshfs') 'self-heal mentions ALIGN/live sshfs'
    $callAlign = [regex]::Match($heal, '_heal_align[^\n]*')
    $callStale = [regex]::Match($heal, '_heal_stale_mounts')
    if ($callAlign.Success -and $callStale.Success) {
        Assert ($callAlign.Index -lt $callStale.Index) 'self-heal ALIGN before _heal_stale_mounts'
    }
}

Assert ($gm -match 'Write-ConnectKeepTunnelMarker') 'Win keep marker API'
Assert ($gm -match 'Invoke-ConnectMountDownByPort') 'Win Soft down-by-port'
Assert ($gm -match 'HYGIENE_SOFT_PORT') 'Win Soft per-port log'
Assert ($gm -match 'Invoke-ConnectOrphanReclaim') 'Win orphan reclaim'
Assert ($gm -match 'Invoke-ConnectMountVerify') 'Win MOUNT_VERIFY'
Assert ($gm -notmatch '\*"\\\$LP"\*') 'MOUNT_VERIFY does not use broken "\$LP" escape'
Assert ($gm -match '(?m)case "`\$cmd" in') 'MOUNT_VERIFY uses escaped case cmd'
Assert ($gmSh -match 'invoke_connect_mount_verify') 'Mac git-mode has invoke_connect_mount_verify'
Assert ($mac -match 'invoke_connect_mount_verify') 'Mac connect calls MOUNT_VERIFY'
Assert ($mac -match 'LITTER_SNAPSHOT') 'Mac SESSION_BEGIN emits LITTER_SNAPSHOT'
Assert ($mac -match 'PHASE_MS mount=') 'Mac finally emits PHASE_MS'
$envRepair = Get-Content (Get-ClientFile 'windows\connect-env-repair.ps1') -Raw
Assert ($envRepair -match 'function Get-ConnectVersionSortKey') 'Get-ConnectVersionSortKey present'
Assert ($envRepair -match 'Anti-downgrade') 'Set-ConnectInstallCurrent anti-downgrade'
$boot = Get-Content (Get-ClientFile 'windows\connect-boot.ps1') -Raw
Assert ($boot -match 'never re-stamp install-current') 'boot prefers newest VerDir'
Assert ($gm -match 'ACQUIRE_ORPHAN_RECLAIMABLE') 'Acquire orphan reclaimable class'

$verExpect = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
Assert ($connect -match [regex]::Escape("ConnectVersion = '$verExpect'")) "Win ConnectVersion $verExpect"
Assert ($connect -match 'Write-ConnectKeepTunnelMarker') 'KEEP writes marker'
Assert ($connect -match 'OrphanReclaimDoneThisEnsure = \$false') 'sessionLoop resets reclaim flag'
Assert ($connect -match 'Invoke-ConnectMountVerify') 'connect calls MOUNT_VERIFY'
Assert ($connect -match 'deferred_setup_refuse_empty_slot') 'C7 deferred refuses empty UI_SLOT'
Assert ($ui -match 'boot_inherit_refuse_empty_slot') 'C7 boot inherit refuses empty UI_SLOT'

Assert ($gmSh -match 'port_takeover') 'Mac PushConf port_takeover'
Assert ($gmSh -match 'AM_ONLY|am_only') 'Mac PushConf AM_ONLY'
Assert ($gmSh -match 'get_sibling_connect_tunnel_pids') 'Mac Soft sibling-safe'
Assert ($gmSh -match 'down-by-port') 'Mac Soft down-by-port'
Assert ($mac -match [regex]::Escape("CONNECT_VERSION='$verExpect'")) "Mac CONNECT_VERSION $verExpect"
Assert ($mac -match 'write_connect_keep_tunnel_marker') 'Mac KEEP marker before disown'

$cleanup = Get-ServerFile 'server\commands\cleanup-user.sh'
Assert (Test-Path $cleanup) 'cleanup-user.sh exists'
$cs = Get-Content -LiteralPath $cleanup -Raw
Assert ($cs -match '--force') 'cleanup-user supports --force'
$disp = Get-ServerFile 'server\claude-server'
$dispTxt = Get-Content -LiteralPath $disp -Raw
Assert ($dispTxt -match 'cleanup-user') 'claude-server wires cleanup-user'

Write-Host ''
if ($failed -eq 0) { Write-Host "All $passed assertions passed." -ForegroundColor Green; exit 0 }
Write-Host "$failed failed / $passed passed." -ForegroundColor Red; exit 1
