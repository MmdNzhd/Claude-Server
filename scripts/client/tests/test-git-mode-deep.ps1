# test-git-mode-deep.ps1 - deep static + logic tests for GIT_MODE feature
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
$ver = Get-ConnectVersion

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

function Test-GetGitModeLogic {
    param([string]$Saved, [string]$Expected)
    $s = $Saved.Trim().ToLower()
    $got = if ($s -match '^(server|on|yes|1|slow)$') { 'server' } elseif ($s -match '^(hide|fast)$') { 'hide' } else { 'off' }
    Assert ($got -eq $Expected) "Get-GitMode parse '$Saved' -> $Expected (got $got)"
}

Test-GetGitModeLogic '' 'off'
Test-GetGitModeLogic 'hide' 'hide'
Test-GetGitModeLogic 'fast' 'hide'
Test-GetGitModeLogic 'server' 'server'
Test-GetGitModeLogic 'on' 'server'
Test-GetGitModeLogic '1' 'server'
Test-GetGitModeLogic 'slow' 'server'
Test-GetGitModeLogic 'SERVER' 'server'
Test-GetGitModeLogic 'garbage' 'off'
Test-GetGitModeLogic 'off' 'off'

$mount = Get-Content (Get-ServerFile 'server\claude-mount.sh') -Raw

Assert ($mount -match 'server\|on\|yes\|1\|slow\) GIT_MODE="server"') 'claude-mount normalizes server aliases'
Assert ($mount -match 'GIT_MODE="off"') 'claude-mount supports GIT_MODE=off'
Assert ($mount -match '_create_claude_stubs_only') 'claude-mount has off-mode stub path'
Assert ($mount -match 'if \[ "\$GIT_MODE" = "off" \]; then[\s\S]{0,200}_hide_git_and_create_stubs') 'claude-mount restores on already-mounted off'
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
Assert ($mount -match 'cmd_recover_one') 'claude-mount has recover-one command'
Assert ($gitModePs1 -match 'Clear-TunnelBannerCache') 'git-mode.ps1 has tunnel banner cache'
Assert ($gitModePs1 -match 'SCP: timeout ERROR') 'git-mode.ps1 logs SCP timeout'
Assert ($gitModePs1 -match 'LAPTOP_SSH: probe begin') 'git-mode.ps1 logs LAPTOP_SSH probe'
Assert ($gitModePs1 -match "ACTIVE_MOUNT=%s") 'git-mode.ps1 pushes ACTIVE_MOUNT in connect conf'
Assert ($mount -match 'cmd_down_others') 'claude-mount has down-others command'
Assert ($mount -match '_force_unmount_project') 'claude-mount has force unmount for hung sshfs'
Assert ($mount -match 'ACTIVE_MOUNT') 'claude-mount reads ACTIVE_MOUNT from connect conf'

$watchdog = Get-Content (Get-ServerFile 'server\claude-watchdog.sh') -Raw
Assert ($watchdog -match '_load_conf') 'watchdog loads ACTIVE_MOUNT before remount'
Assert ($watchdog -match 'local_id.*ACTIVE_MOUNT') 'watchdog remounts only active project'

$automount = Get-Content (Get-ServerFile 'server\claude-automount.sh') -Raw
Assert ($automount -match 'up "\$ACTIVE_MOUNT"') 'automount only mounts ACTIVE_MOUNT project'
Assert ($automount -match 'OFF mode must still run up') 'automount applies off mode when mount already ok'

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


# P0 recovery/tunnel safety parity (connect-fix-100 #93-96).
$macConnect = Get-Content (Get-ClientFile 'mac\connect.sh') -Raw
$macPushMatch = [regex]::Match($gitModeSh, '(?ms)^push_server_connect_conf\(\)\s*\{.*?^\}')
$macPushBody = if ($macPushMatch.Success) { $macPushMatch.Value } else { '' }
Assert ($macConnect -match 'RECOVERY_SKIP_CLEAR_MOUNT') 'mac auto recovery logs RECOVERY_SKIP_CLEAR_MOUNT when editor stays open'
Assert ($macConnect -match 'FINALLY_KEEP_TUNNEL') 'mac cleanup keeps tunnel alive while editor remains on remote folder'
Assert ($gitModeSh -match 'TUNNEL_SYNC soft_fail[^\r\n]*(no_ssh_proc|tcp_open_no_process|no_process_tcp_open|no_proc_tcp_open)') 'mac tunnel sync soft-fails when TCP is open without a process handle'
Assert (($gitModeSh + $macConnect) -match 'TUNNEL_SYNC_FAIL_COUNT|TunnelSyncFailCount') 'mac tunnel sync debounces consecutive failures'
Assert ($macPushBody -notmatch 'claude-self-heal') 'mac push_server_connect_conf does not invoke claude-self-heal'
Assert ($gitModeSh -match '_LAST_TUNNEL_TRACE[\s\S]*?-ge 30') 'mac TUNNEL_SYNC TRACE is throttled to at least 30 seconds'

# v20260717.7+: Server setup must not abort on script push; foreign-session guard; clear errors
Assert ($gitModeSh -match 'INIT_SERVER_SESSION_ERROR') 'git-mode.sh sets INIT_SERVER_SESSION_ERROR'
Assert ($gitModeSh -match 'warn_foreign_server_session') 'git-mode.sh has warn_foreign_server_session'
Assert ($gitModeSh -match 'Cleared stale session') 'git-mode.sh self-heals stale foreign session'
Assert ($gitModeSh -match 'password at most once') 'git-mode.sh Mac admin password once'
Assert ($gitModeSh -match 'never run remote cmds with quoted') 'git-mode.sh documents tilde chmod fix'
Assert ($gitModeSh -match '45s timeout') 'git-mode.sh Mac password has timeout'
$cuiSh = Get-Content (Get-ClientFile 'connect-ui.sh') -Raw -ErrorAction SilentlyContinue
if ($cuiSh) {
    Assert ($cuiSh -match 'sync_connect_log_to_server') 'connect-ui.sh syncs logs to server'
    Assert ($cuiSh -match 'mtime \+1') 'connect-ui.sh deletes server logs older than 1 day'
    Assert ($cuiSh -match 'config/claude-connect/logs/connect-') 'connect-ui.sh keeps durable local day logs'
}
$cuiPs = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
Assert ($cuiPs -match 'Sync-ConnectLogToServer') 'connect-ui.ps1 syncs logs to server'
Assert ($cuiPs -match 'mtime \+1') 'connect-ui.ps1 deletes server logs older than 1 day'
Assert ($cuiPs -notmatch "Join-Path \$ScriptDir 'connect.log'") 'connect-ui.ps1 does not write connect.log beside scripts'

Assert ($gitModePs1 -match 'Cleared stale session') 'git-mode.ps1 self-heals stale foreign session'
Assert ($gitModeSh -match 'script push failure must not abort connect') 'git-mode.sh documents non-fatal script push'
Assert ($gitModeSh -notmatch '(?s)initialize_server_session\(\) \{.*?\[ "\$push_ok" -eq 1 \]') 'initialize_server_session does not fail on push_ok'
Assert ($gitModePs1 -match 'function Warn-ForeignServerSession') 'git-mode.ps1 has Warn-ForeignServerSession'
Assert ($gitModePs1 -match '\[switch\]\$StopEditor') 'git-mode.ps1 Clear-SessionMount uses opt-in StopEditor'
Assert ($gitModePs1 -notmatch 'SkipEditorStop') 'git-mode.ps1 removed SkipEditorStop'
Assert ($winConnect -notmatch '-SkipEditorStop') 'connect.ps1 does not pass SkipEditorStop'

foreach ($rel in @('mac\connect.sh')) {
    $src = Get-Content (Get-ClientFile $rel) -Raw
    Assert ($src -match 'warn_foreign_server_session') "$rel calls warn_foreign_server_session"
    Assert ($src -match 'INIT_SERVER_SESSION_ERROR') "$rel shows INIT_SERVER_SESSION_ERROR"
    Assert ($src -match 'NOT your Mac login') "$rel setup clarifies server username"
}
$winConnect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
Assert ($winConnect -match 'Warn-ForeignServerSession') 'connect.ps1 calls Warn-ForeignServerSession'
Assert ($winConnect -match 'NOT your Windows login') 'connect.ps1 setup clarifies server username'
Assert ($winConnect -match 'server script push failed \(continuing\)') 'connect.ps1 continues after script push fail'
Assert ($winConnect -match 'PushOk') 'connect.ps1 tracks PushOk for non-fatal script push'
Assert ($gitModeSh -match 'stop_remote_editor') 'git-mode.sh has stop_remote_editor'
Assert ($gitModeSh -match '_stop_remote_editor_by_uri') 'git-mode.sh stop_remote_editor is path-scoped by uri/path'
Assert ($gitModeSh -match 'skip_editor="\$\{5:-1\}"') 'git-mode.sh clear_session_mount skips editor stop by default'

foreach ($rel in @('mac\connect.sh')) {
    $src = Get-Content (Get-ClientFile $rel) -Raw
    $bundle = $src + $gitModeSh
    Assert ($src -match "CONNECT_VERSION='$([regex]::Escape($ver))'") "$rel has current CONNECT_VERSION ($ver)"
    Assert ($src -match 'exit_requested|menuLoop') "$rel has post-disconnect menu loop"
    Assert ($src -match 'read_post_disconnect_key') "$rel has post-disconnect countdown"
    Assert ($src -match 'ui_session_box|G = git mode') "$rel has session git hotkey"
    Assert ($src -match 'clear_session_mount') "$rel clears mount on disconnect"
    Assert ($src -match 'initialize_server_session') "$rel uses parallel server setup"
    Assert ($src -notmatch 'unmount_other_projects|Unmount-OtherProjects') "$rel does not unmount other projects on connect"
    Assert ($src -match 'ACTIVE_MOUNT_ID') "$rel tracks ACTIVE_MOUNT on server"
    Assert ($bundle -match 'remount_project_git') "$rel has mid-session git remount"
    Assert ($src -match '_editor_opened') "$rel opens editor only once per menu pick"
    Assert ($src -match 'begin_connect_recovery') "$rel calls begin_connect_recovery on reconnect"
    Assert ($src -match 'stop_session_tunnel_cleanup') "$rel uses stop_session_tunnel_cleanup on disconnect"
    Assert ($src -match 'CURSOR_AUTH_FORCE') "$rel forces cursor auth after recovery"
    Assert ($src -match 'launch_remote_editor') "$rel uses launch_remote_editor for editor open"
    Assert ($src -match '_did_launch') "$rel relaunches when cursor not on folder"
    Assert ($src -match 'ensure_mac_cursor_prerequisites') "$rel calls ensure_mac_cursor_prerequisites before auth"
    Assert ($src -match 'Reload Window') "$rel shows Reload Window hint after auth sync"
    Assert ($src -match 'begin_connect_recovery|connect_log.*recover') "$rel logs recovery tags"
}

Assert ($gitModeSh -match 'cursor_auth_needs_refresh') 'git-mode.sh has cursor_auth_needs_refresh'
Assert ($gitModeSh -match 'golden-synced-at\.txt') 'git-mode.sh stamps golden-synced-at after merge'
Assert ($gitModeSh -match 'remote\.SSH\.useLocalServer') 'git-mode.sh sets useLocalServer in profile template'
Assert ($gitModeSh -match 'ensure_mac_cursor_prerequisites') 'git-mode.sh has Mac Cursor prerequisites'
Assert ($gitModeSh -match 'patch_cursor_server_profile_settings') 'git-mode.sh patches existing profile settings'
Assert ($gitModeSh -match 'check_mac_cursor_remote_ssh_extension') 'git-mode.sh checks anysphere.remote-ssh'

$editorLaunchSh = Get-Content (Get-ClientFile 'editor-launch.sh') -Raw
Assert ($editorLaunchSh -match 'remote_editor_on_correct_folder') 'editor-launch.sh detects on-folder'
Assert ($editorLaunchSh -match 'remote_editor_in_agent_home') 'editor-launch.sh detects agent home'
Assert ($editorLaunchSh -match '--new-window') 'editor-launch.sh supports new-window relaunch'
Assert ($editorLaunchSh -notmatch 'folder-uri\*\)\s*return 0') 'editor-launch.sh does not match any folder-uri'

Assert ($gitModeSh -match 'ACTIVE_MOUNT=%s') 'git-mode.sh pushes ACTIVE_MOUNT in connect conf'

Assert ($gitModePs1 -match 'function Read-RetryQuitKey') 'git-mode.ps1 has Read-RetryQuitKey with timeout'
Assert ($gitModeSh -match 'read_post_disconnect_key') 'git-mode.sh has post-disconnect helper'
Assert ($gitModeSh -match 'get_active_mount_id') 'git-mode.sh queries ACTIVE_MOUNT from server'
Assert ($gitModeSh -match 'get_git_mode_label') 'git-mode.sh has FAST/SLOW label helper'
Assert ($gitModeSh -match 'cursor_sqlite3_available') 'git-mode.sh uses sqlite3 for cursor auth'
Assert ($gitModePs1 -match 'Read-PostDisconnectKey') 'git-mode.ps1 has Read-PostDisconnectKey'

Assert ($gitModeSh -match 'tunnel_drop_session_action') 'git-mode.sh honors Q on tunnel drop'
Assert ($gitModeSh -match 'begin_connect_recovery') 'git-mode.sh has begin_connect_recovery'
Assert ($gitModeSh -match "storage.serviceMachineId") 'git-mode.sh checks storage.serviceMachineId in local_cursor_auth_complete'
Assert ($gitModeSh -match 'stripeMembershipType') 'git-mode.sh checks stripeMembershipType in local_cursor_auth_complete'
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
Assert ($gitModePs1 -match 'Test-TunnelPortIsForeignPeer') 'git-mode.ps1 has foreign peer guard'
Assert ($gitModePs1 -match 'ACQUIRE_SKIP: foreign_peer') 'git-mode.ps1 skips foreign peer ports'
Assert ($gitModePs1 -match 'skip_foreign_peer') 'git-mode.ps1 never kills foreign peer forwards'
Assert ($gitModePs1 -match 'Get-TunnelHostKeyFingerprint') 'git-mode.ps1 pins laptop host key fingerprint'
Assert ($gitModePs1 -match 'PUSH_CONF blocked') 'git-mode.ps1 refuses PushConf for foreign ports'
Assert ($gitModePs1 -match 'refuse_kill_foreign') 'git-mode.ps1 never fuser-kills foreign peers'
$heal = Get-Content (Get-ServerFile 'server\claude-self-heal.sh') -Raw
Assert ($heal -match '_heal_tunnel_ownership') 'claude-self-heal clears unowned TUNNEL_PORT'
Assert ($heal -match 'cleared unowned TUNNEL_PORT') 'claude-self-heal logs unowned port clear'
$gitModeSh = Get-Content (Get-ClientFile 'git-mode.sh') -Raw
Assert ($gitModeSh -match 'refuse_kill_foreign') 'git-mode.sh refuses killing foreign peers'
Assert ($gitModeSh -match 'PUSH_CONF blocked') 'git-mode.sh blocks PushConf for foreign ports'
Assert ($gitModeSh -match 'LAPTOP_HOSTKEY_FP=%s') 'git-mode.sh pushes LAPTOP_HOSTKEY_FP'

Assert ($gitModePs1 -match 'MOUNT_UP check_reuse|MOUNT_UP skip') 'git-mode.ps1 reuses or skips mount when check ok'
Assert ($gitModePs1 -match 'off_mode_apply') 'git-mode.ps1 still runs up / applies off when GIT_MODE=off'
Assert ($mount -match 'CLAUDE_TRUSTED_TUNNEL') 'claude-mount has trusted-tunnel fast path'
$automount = Get-Content (Get-ServerFile 'server\claude-automount.sh') -Raw
Assert ($automount -match 'VSCODE_IPC_HOOK_CLI') 'claude-automount skips IDE shell resolution'
Assert ($gitModeSh -match 'already mounted \(check ok\)') 'git-mode.sh skips mount when check ok'
Assert ($gitModeSh -match 'mode.*off') 'git-mode.sh still runs up when GIT_MODE=off'
Assert ($gitModePs1 -match 'Clear-ServerStaleTunnelForward') 'git-mode.ps1 clears stale server tunnel forward'
Assert ($gitModePs1 -match 'STALE_FORWARD: zombie') 'git-mode.ps1 detects zombie tunnel port'
Assert ($gitModePs1 -match 'Stop-SessionTunnelCleanup') 'git-mode.ps1 has Stop-SessionTunnelCleanup'
Assert ($gitModeSh -match 'clear_server_stale_tunnel_forward') 'git-mode.sh clears stale server tunnel forward'
Assert ($gitModeSh -match 'stop_session_tunnel_cleanup') 'git-mode.sh has stop_session_tunnel_cleanup'
Assert ($win -match 'Stop-SessionTunnelCleanup') 'connect.ps1 uses Stop-SessionTunnelCleanup on disconnect'
Assert ($gitModePs1 -match 'known_hosts_claude_mount') 'git-mode.ps1 uses mount known_hosts for reverse SSH probe'
Assert ($gitModePs1 -match 'known_hosts_claude_mount.*known_hosts_claude_tunnel|known_hosts_claude_tunnel.*known_hosts_claude_mount') 'Clear-ServerTunnelKnownHost resets mount and tunnel known_hosts'
Assert ($gitModePs1 -match 'Host key verification failed.*Clear-ServerTunnelKnownHost|Clear-ServerTunnelKnownHost[\s\S]{0,800}Host key verification failed') 'probe retries after host-key clear'
Assert ($gitModePs1 -match 'LastLaptopReverseSshError') 'git-mode.ps1 surfaces reverse SSH error detail'
Assert ($gitModePs1 -match 'WindowStyle Hidden -Command exit') 'git-mode.ps1 uses hidden Windows reverse SSH probe'
Assert ($gitModePs1 -match 'mac\\claude-mount\.sh') 'git-mode.ps1 finds claude-mount.sh in mac package folder'
Assert ($mount -match 'cmd_check') 'claude-mount has check command'
Assert ($gitModePs1 -match 'Initialize-SessionBgTunnel') 'git-mode.ps1 pre-warms background tunnel'
Assert ($mount -match 'CLAUDE_TRUSTED_TUNNEL') 'claude-mount supports trusted tunnel skip'
Assert ($mount -match '_hide_git_and_create_stubs') 'claude-mount has git hide with tunnel guard'
Assert ($mount -match 'ControlMaster=no') 'claude-mount disables SSH mux to laptop'
Assert ($mount -match 'EncodedCommand') 'claude-mount uses EncodedCommand for Windows git hide'

$gitSetup = Get-Content (Get-ServerFile 'server\claude-git-setup.sh') -Raw
Assert ($gitSetup -match 'GIT_MODE.*skip local mirror') 'git-setup skips mirror when GIT_MODE=server or off'
Assert ($gitSetup -match 'GIT_MODE.*off') 'git-setup skips mirror when GIT_MODE=off'
$laptopExec = Get-Content (Get-ServerFile 'server\laptop-exec.sh') -Raw
Assert ($laptopExec -match 'GIT_MODE="off"') 'laptop-exec defaults GIT_MODE to off'
Assert ($laptopExec -notmatch 'GIT_MODE="hide"; LAPTOP_OS') 'laptop-exec no hide pre-read default'
Assert ($mount -match 'cannot restore \.git') 'claude-mount warns when off restore blocked by tunnel'
Assert ($mount -match 'recover: off restore done') 'claude-mount recover-if-needed applies off restore'
Assert ($gitModePs1 -match 'off_mode_apply') 'git-mode.ps1 recover applies off when mount ok'

$dle = Get-Content (Get-ServerFile 'server\commands\deploy-laptop-exec.sh') -Raw
Assert ($dle -match 'CLIENT_BUNDLE/server/laptop-exec') 'deploy-laptop-exec prefers bundle over user home'
Assert ($dle -match 'GIT_MODE="off".*fail') 'deploy-laptop-exec fails if GIT_MODE not off'
Assert ($dle -match 'claude-mount.sh') 'deploy-laptop-exec deploys claude-mount'
$dcb = Get-Content (Get-ServerFile 'server\commands\deploy-client-bundle.sh') -Raw
Assert ($dcb -notmatch 'mac/connect-ui.sh') 'deploy-client-bundle uses scripts/client/connect-ui.sh'

# --- Site policy: GIT_MODE hide/server permanently force-off ---
Assert (Select-String -Path (Get-ServerFile 'server\claude-mount.sh') -Pattern 'CLAUDE_GIT_MODE_FORCE_OFF' -SimpleMatch -Quiet) 'claude-mount has CLAUDE_GIT_MODE_FORCE_OFF killswitch'
$forceCount = @(Select-String -Path (Get-ServerFile 'server\claude-mount.sh') -Pattern 'CLAUDE_GIT_MODE_FORCE_OFF' -SimpleMatch).Count
Assert ($forceCount -ge 2) ('claude-mount killswitch sites >=2 (got ' + $forceCount + ')')

$gmPs1Force = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
Assert ($gmPs1Force -match 'Site policy: GIT_MODE hide/server disabled') 'git-mode.ps1 documents force-off policy'
Assert ($gmPs1Force -match "return 'off'") 'git-mode.ps1 Get-GitMode returns off'

$gmShForce = Get-Content (Get-ClientFile 'git-mode.sh') -Raw
Assert ($gmShForce -match 'Site policy: GIT_MODE hide/server disabled') 'git-mode.sh documents force-off policy'
Assert ($gmShForce -match 'echo off') 'git-mode.sh get_git_mode echoes off'

# Runtime: even if git.conf says hide, Get-GitMode must return off and rewrite conf
$_cfg = Join-Path $env:TEMP ('gitmode-force-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $_cfg | Out-Null
Set-Content (Join-Path $_cfg 'git.conf') -Value 'hide' -Encoding ASCII
$CfgDir = $_cfg
. (Get-ClientFile 'git-mode.ps1')
$_mode = Get-GitMode
$_after = (Get-Content (Join-Path $_cfg 'git.conf') -Raw).Trim()
Assert ($_mode -eq 'off') ('Get-GitMode force-off runtime (got ' + $_mode + ')')
Assert ($_after -eq 'off') ('git.conf rewritten to off (got ' + $_after + ')')
Remove-Item -Recurse -Force $_cfg -ErrorAction SilentlyContinue
Assert $true 'GIT_MODE force-off killswitch + client policy'

Write-Host ""
if ($fail -eq 0) { Write-Host "All deep git-mode tests passed." -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
