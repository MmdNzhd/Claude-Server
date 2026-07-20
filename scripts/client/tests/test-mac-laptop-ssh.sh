#!/bin/bash
# test-mac-laptop-ssh.sh - static checks for Mac self-healing reverse-SSH helpers
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GIT="$ROOT/scripts/client/git-mode.sh"
MAC="$ROOT/scripts/client/mac/connect.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "$GIT" ] || fail "git-mode.sh missing"
[ -f "$MAC" ] || fail "mac/connect.sh missing"

grep -q 'install_laptop_server_pubkey' "$GIT" || fail 'missing install_laptop_server_pubkey'
grep -q 'verify_laptop_reverse_ssh' "$GIT" || fail 'missing verify_laptop_reverse_ssh'
grep -q 'verify_laptop_local_pubkey' "$GIT" || fail 'missing verify_laptop_local_pubkey'
grep -q 'ensure_laptop_ssh_key' "$GIT" || fail 'missing ensure_laptop_ssh_key'
grep -q 'ensure_laptop_reverse_ssh' "$GIT" || fail 'missing ensure_laptop_reverse_ssh'
grep -q 'invoke_laptop_admin_ops' "$GIT" || fail 'missing invoke_laptop_admin_ops'
grep -q 'run_mac_admin_cmd' "$GIT" || fail 'missing run_mac_admin_cmd'
grep -q 'laptop_ssh_bootstrap_local' "$GIT" || fail 'missing laptop_ssh_bootstrap_local'
grep -q 'cycle_remote_login' "$GIT" || fail 'missing cycle_remote_login'
grep -q 'grant_laptop_ssh_access' "$GIT" || fail 'missing grant_laptop_ssh_access'
grep -q 'localhost,::ffff:127.0.0.1' "$GIT" || fail 'Darwin from= prefix missing'
grep -q 'Verifying laptop SSH key' "$MAC" || fail 'connect.sh must verify before mount'
GIT_PS="$ROOT/scripts/client/git-mode.ps1"
grep -q 'ensure_laptop_reverse_ssh_cached' "$MAC" || fail 'connect.sh must use ensure_laptop_reverse_ssh_cached'
grep -q 'Ensure-LaptopReverseSshCached' "$GIT_PS" || fail 'missing Ensure-LaptopReverseSshCached in git-mode.ps1'
grep -q 'ensure_session_tunnel' "$GIT" || fail 'missing ensure_session_tunnel'
grep -q 'invoke_mount_project' "$GIT" || fail 'missing invoke_mount_project'
grep -q 'server mount script outdated' "$GIT" || fail 'invoke_mount_project must auto-push stale mount script'
UI="$ROOT/scripts/client/connect-ui.sh"
grep -q 'O = reopen editor' "$UI" || fail 'connect-ui.sh must advertise O reopen hotkey'
grep -q '_stop_cursor_server_profile' "$GIT" || fail 'git-mode.sh must kill ClaudeServerCursorProfile on disconnect'
grep -q '_stop_code_server_profile' "$GIT" || fail 'git-mode.sh must kill ClaudeServerCodeProfile on disconnect'
grep -q 'fix_laptop_ssh_firewall' "$GIT" || fail 'git-mode.sh must fix Mac SSH firewall'
grep -q 'ensure_mac_cursor_prerequisites' "$GIT" || fail 'git-mode.sh must ensure Mac Cursor prerequisites'
grep -q 'ensure_mac_cursor_tmpdir' "$GIT" || fail 'git-mode.sh must fix Mac TMPDIR for Remote SSH'
grep -q 'check_mac_cursor_remote_ssh_extension' "$GIT" || fail 'git-mode.sh must check anysphere.remote-ssh'
grep -q 'patch_cursor_server_profile_settings' "$GIT" || fail 'git-mode.sh must patch existing profile settings'
grep -q 'launch_remote_editor' "$MAC" || fail 'connect.sh must use launch_remote_editor'
grep -q 'cursor_auth_needs_refresh' "$GIT" || fail 'git-mode.sh must have cursor_auth_needs_refresh'
grep -q 'golden-synced-at.txt' "$GIT" || fail 'git-mode.sh must stamp golden-synced-at'
grep -q 'remote.SSH.useLocalServer' "$GIT" || fail 'git-mode.sh profile must set useLocalServer false'
grep -q 'remote_editor_on_correct_folder' "$ROOT/scripts/client/editor-launch.sh" || fail 'editor-launch.sh must detect on-folder state'
grep -q 'remote_editor_in_agent_home' "$ROOT/scripts/client/editor-launch.sh" || fail 'editor-launch.sh must detect agent home'
grep -q '_did_launch' "$MAC" || fail 'connect.sh must relaunch when not on folder'
grep -q 'remote_editor_running' "$ROOT/scripts/client/editor-launch.sh" || fail 'editor-launch.sh must track live editor process'
grep -q 'ClaudeServerCodeProfile' "$ROOT/scripts/client/editor-launch.sh" || fail 'editor-launch.sh must use isolated VS Code profile'
grep -q 'release_stale_tunnel_port' "$GIT" || fail 'missing release_stale_tunnel_port'
grep -q 'acquire_tunnel_port' "$GIT" || fail 'missing acquire_tunnel_port'
grep -q 'tunnel_banner_is_this_laptop' "$GIT" || fail 'missing tunnel_banner_is_this_laptop'
grep -q 'sanitize_ssh_alias_config' "$GIT" || fail 'missing sanitize_ssh_alias_config'
grep -q 'ExitOnForwardFailure=yes' "$GIT" || fail 'tunnel must use ExitOnForwardFailure'
! grep -q 'ClearAllForwardings=yes.*-R' "$MAC" || fail 'tunnel must not use ClearAllForwardings with -R'
! grep -q 'RemoteForward \$PORT' "$GIT" || fail 'RemoteForward must not be in ssh config'

# P0 recovery/tunnel safety contract (connect-fix-100 #96).
grep -q 'RECOVERY_SKIP_CLEAR_MOUNT' "$MAC" || fail 'auto recovery must preserve mount while editor is open'
grep -q 'FINALLY_KEEP_TUNNEL' "$MAC" || fail 'finally cleanup must preserve tunnel while editor is open'
grep -Eq 'TUNNEL_SYNC_FAIL_COUNT|TunnelSyncFailCount' "$GIT" "$MAC" || fail 'tunnel sync failures must be debounced'
grep -Eq 'TUNNEL_SYNC soft_fail.*(no_ssh_proc|tcp_open_no_process|no_process_tcp_open)' "$GIT" || fail 'tcp-open tunnel without process must soft-fail'
grep -q '_LAST_TUNNEL_TRACE' "$GIT" || fail 'TUNNEL_SYNC TRACE throttle state missing'
grep -q '\-ge 30' "$GIT" || fail 'TUNNEL_SYNC TRACE throttle must be at least 30 seconds'
_mac_push_body="$(awk '/^push_server_connect_conf\(\)[[:space:]]*\{/{in_fn=1} in_fn{print} in_fn && /^\}/{exit}' "$GIT")"
! grep -q 'claude-self-heal' <<<"$_mac_push_body" || fail 'push_server_connect_conf must not invoke claude-self-heal'
bash -n "$GIT" || fail "bash -n git-mode.sh"
bash -n "$MAC" || fail "bash -n mac/connect.sh"

echo 'OK test-mac-laptop-ssh.sh'
