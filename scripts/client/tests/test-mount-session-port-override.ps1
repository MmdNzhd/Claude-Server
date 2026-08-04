#Requires -Version 5.1
# Static contract: session reverse-tunnel port overrides fleet conf for claude-mount up.
# Evidence: Precise×6 20260804.16 W5 MOUNT_BG_FAIL on published 20020 while session was 20024.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== mount session-port override (static) ===' -ForegroundColor Cyan

$mount = Get-Content -LiteralPath (Get-ServerFile 'claude-mount.sh') -Raw -ErrorAction SilentlyContinue
if (-not $mount) {
    $mountPath = Join-Path $script:RepoRoot 'scripts\server\claude-mount.sh'
    $mount = Get-Content -LiteralPath $mountPath -Raw
}
$connect = Get-Content -LiteralPath (Get-ClientFile 'windows\connect.ps1') -Raw
$gitMode = Get-Content -LiteralPath (Get-ClientFile 'git-mode.ps1') -Raw
$launch = Get-Content -LiteralPath (Get-ClientFile 'editor-launch.ps1') -Raw
$mcp = Get-Content -LiteralPath (Get-ClientFile 'windows\windows-mcp-laptop.ps1') -Raw

Assert ($mount -match 'CLAUDE_MOUNT_TUNNEL_PORT') 'claude-mount.sh reads CLAUDE_MOUNT_TUNNEL_PORT'
Assert ($mount -match 'MOUNT_PORT_OVERRIDE') 'claude-mount.sh logs MOUNT_PORT_OVERRIDE'
Assert ($connect -match 'CLAUDE_MOUNT_TUNNEL_PORT=\$SessionPort') 'BG mount runner sets CLAUDE_MOUNT_TUNNEL_PORT'
Assert ($connect -match '-SessionPort') 'Start-MountProjectBackground accepts -SessionPort'
Assert ($connect -match '-SessionPort\s+\$mountSessionPort') 'call site passes session port'
Assert ($gitMode -match 'CLAUDE_MOUNT_TUNNEL_PORT=') 'Invoke-MountProject / remount pass session port env'
Assert ($launch -match 'LAUNCH_POLL_WALL' -or $launch -match 'warmWallMs') 'warm launch has wall-clock cap'
Assert ($launch -match 'LAUNCH_SKIP:.*remote-classic' -or $launch -match 'LaunchSkipWarmClassic') 'skip remote-classic when promising'
Assert ($launch -match 'LAUNCH_PROMISING_EARLY_GRACE') 'promising early grace exit'
Assert ($mcp -match 'abandoned mutex') 'WMCP mutex unwrap matches abandoned text'
Assert ($mcp -match 'fleet_spawn_mutex' -or $mcp -match 'wmcp-fleet-bg.stamp') 'WMCP fleet single-bg Ensure guard'
Assert ($mcp -match 'MaxOuter') 'peer probe accepts MaxOuter for late workers'

Write-Host ''
Write-Host ("RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($Fail -eq 0) { 0 } else { 1 })
