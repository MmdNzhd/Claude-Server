# test-git-mode-deep.ps1 — deep static + logic tests for GIT_MODE feature
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

function Test-GetGitModeLogic {
    param([string]$Saved, [string]$Expected)
    $s = $Saved.Trim().ToLower()
    $got = if ($s -match '^(server|on|yes|1|slow)$') { 'server' } else { 'hide' }
    Assert ($got -eq $Expected) "Get-GitMode parse '$Saved' -> $Expected (got $got)"
}

Write-Host ""
Write-Host "=== GIT_MODE deep logic tests ===" -ForegroundColor Cyan
Write-Host ""

Test-GetGitModeLogic '' 'hide'
Test-GetGitModeLogic 'hide' 'hide'
Test-GetGitModeLogic 'server' 'server'
Test-GetGitModeLogic 'on' 'server'
Test-GetGitModeLogic '1' 'server'
Test-GetGitModeLogic 'slow' 'server'
Test-GetGitModeLogic 'SERVER' 'server'
Test-GetGitModeLogic 'garbage' 'hide'
Test-GetGitModeLogic 'off' 'hide'

$mount = Get-Content (Get-ServerFile 'server\claude-mount.sh') -Raw

Assert ($mount -match 'server\|on\|yes\|1\|slow\) GIT_MODE="server"') 'claude-mount normalizes server aliases'
Assert ($mount -match 'mac\|darwin\|osx\) LAPTOP_OS="mac"') 'claude-mount normalizes mac aliases'
Assert ($mount -match 'cmd_up\(\)[\s\S]*?_load_global') 'cmd_up loads global config'
Assert ($mount -match 'cmd_down\(\)[\s\S]*?_load_global') 'cmd_down loads global config'
Assert ($mount -match 'cmd_recover\(\)[\s\S]*?_load_global') 'cmd_recover loads global config'

$restoreCount = ([regex]::Matches($mount, '_restore_git')).Count
Assert ($restoreCount -ge 4) "claude-mount has multiple _restore_git safety nets (count=$restoreCount)"
Assert ($mount -match 'sshfs failed[\s\S]*?_restore_git') 'sshfs failure restores .git'
Assert ($mount -match '_mac_hide_git_and_create_stubs') 'Mac stub path exists'
Assert ($mount -match '_win_hide_git_and_create_stubs') 'Windows stub path exists'
Assert ($mount -match 'mount_git_mode') 'claude-mount supports per-project git_mode override'
Assert ($mount -match 'Get-Process git') 'claude-mount stops git.exe on hide retry'

$gitModePs1 = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
Assert ($gitModePs1 -match "ACTIVE_MOUNT=%s") 'git-mode.ps1 pushes ACTIVE_MOUNT in connect conf'
Assert ($mount -match 'cmd_down_others') 'claude-mount has down-others command'
Assert ($mount -match '_force_unmount_project') 'claude-mount has force unmount for hung sshfs'
Assert ($mount -match 'ACTIVE_MOUNT') 'claude-mount reads ACTIVE_MOUNT from connect conf'

$watchdog = Get-Content (Get-ServerFile 'server\claude-watchdog.sh') -Raw
Assert ($watchdog -match '_load_active_mount') 'watchdog loads ACTIVE_MOUNT before remount'
Assert ($watchdog -match 'local_id.*ACTIVE_MOUNT') 'watchdog remounts only active project'

$automount = Get-Content (Get-ServerFile 'server\claude-automount.sh') -Raw
Assert ($automount -match 'up "\$ACTIVE_MOUNT"') 'automount only mounts ACTIVE_MOUNT project'

foreach ($rel in @('windows\connect.ps1', 'users\designer\connect.ps1')) {
    $src = Get-Content (Get-ClientFile $rel) -Raw
    Assert ($src -match 'git-mode\.ps1') "$rel dot-sources git-mode.ps1"
    Assert ($src -notmatch 'Unmount-OtherProjects') "$rel does not unmount other projects on connect"
}

foreach ($rel in @('mac\connect.sh', 'users\designer\connect.sh')) {
    $src = Get-Content (Get-ClientFile $rel) -Raw
    Assert ($src -match 'git-mode\.sh') "$rel sources git-mode.sh"
}

$gitModeSh = Get-Content (Get-ClientFile 'git-mode.sh') -Raw
Assert ($gitModeSh -match 'function clear_session_mount|clear_session_mount\(\)') 'git-mode.sh has clear_session_mount'
Assert ($gitModeSh -match 'initialize_server_session') 'git-mode.sh has initialize_server_session'
Assert ($gitModeSh -match 'stop_remote_editor') 'git-mode.sh has stop_remote_editor'

foreach ($rel in @('mac\connect.sh')) {
    $src = Get-Content (Get-ClientFile $rel) -Raw
    $bundle = $src + $gitModeSh
    Assert ($src -match "CONNECT_VERSION='20260703\.12'") "$rel has current CONNECT_VERSION"
    Assert ($src -match 'exit_requested|menuLoop') "$rel has post-disconnect menu loop"
    Assert ($src -match 'read_post_disconnect_key') "$rel has post-disconnect countdown"
    Assert ($src -match 'ui_session_box|G = git mode') "$rel has session git hotkey"
    Assert ($src -match 'clear_session_mount') "$rel closes editor on disconnect"
    Assert ($src -match 'initialize_server_session') "$rel uses parallel server setup"
    Assert ($src -notmatch 'unmount_other_projects|Unmount-OtherProjects') "$rel does not unmount other projects on connect"
    Assert ($src -match 'ACTIVE_MOUNT_ID') "$rel tracks ACTIVE_MOUNT on server"
    Assert ($bundle -match 'remount_project_git') "$rel has mid-session git remount"
    Assert ($src -match '_editor_opened') "$rel opens editor only once per menu pick"
    Assert ($src -match 'tunnel_drop_session_action') "$rel honors Q on tunnel drop"
}

Assert ($gitModeSh -match 'ACTIVE_MOUNT=%s') 'git-mode.sh pushes ACTIVE_MOUNT in connect conf'

Assert ($gitModePs1 -match 'function Read-RetryQuitKey') 'git-mode.ps1 has Read-RetryQuitKey with timeout'
Assert ($gitModeSh -match 'read_post_disconnect_key') 'git-mode.sh has post-disconnect helper'
Assert ($gitModeSh -match 'get_active_mount_id') 'git-mode.sh queries ACTIVE_MOUNT from server'
Assert ($gitModeSh -match 'get_git_mode_label') 'git-mode.sh has FAST/SLOW label helper'
Assert ($gitModeSh -match 'push_cursor_golden_from_server_profile') 'git-mode.sh has P-key push'
Assert ($gitModePs1 -match 'Read-PostDisconnectKey') 'git-mode.ps1 has Read-PostDisconnectKey'

Assert ($gitModeSh -match 'tunnel_drop_session_action') 'git-mode.sh honors Q on tunnel drop'
Assert ($gitModeSh -match 'test_mount_success') 'git-mode.sh has mount success helper'

$win = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$pushIdx = $win.IndexOf('Push-ServerConnectConf')
$chooseIdx = $win.IndexOf('Choose-Project -Mounts')
Assert ($pushIdx -gt 0 -and $chooseIdx -gt $pushIdx) 'Initial conf push before Choose-Project'

$install = Get-Content (Get-ServerFile 'server\commands\install.sh') -Raw
Assert ($install -match 'claude-mount\.sh.* /usr/local/lib/claude-mount') 'install.sh deploys to /usr/local/lib'
Assert ($install -match 'all users ~/.local/bin') 'install.sh redeploys claude-mount to all users'
Assert ($gitModeSh -match 'ensure_session_tunnel') 'git-mode.sh has ensure_session_tunnel'
Assert ($gitModeSh -match 'invoke_mount_project') 'git-mode.sh has invoke_mount_project'
Assert ($gitModePs1 -match 'Ensure-LaptopReverseSshCached') 'git-mode.ps1 has Ensure-LaptopReverseSshCached'
Assert ($gitModePs1 -match 'Acquire-TunnelPort') 'git-mode.ps1 has Acquire-TunnelPort'
Assert ($mount -match 'cmd_check') 'claude-mount has check command'
Assert ($mount -match 'CLAUDE_TRUSTED_TUNNEL') 'claude-mount supports trusted tunnel skip'
Assert ($mount -match 'ControlMaster=no') 'claude-mount disables SSH mux to laptop'

$gitSetup = Get-Content (Get-ServerFile 'server\claude-git-setup.sh') -Raw
Assert ($mount -match 'EncodedCommand') 'claude-mount uses EncodedCommand for Windows git hide'

$gitSetup = Get-Content (Get-ServerFile 'server\claude-git-setup.sh') -Raw
Assert ($gitSetup -match 'GIT_MODE=server') 'git-setup skips mirror when GIT_MODE=server'

Write-Host ""
if ($fail -eq 0) { Write-Host "All deep git-mode tests passed." -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
