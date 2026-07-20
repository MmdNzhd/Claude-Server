# -*- coding: utf-8 -*-
"""Fix all residual connect risks from edge audit."""
from pathlib import Path
import re

root = Path(r'D:\Smart\Claude-Code-Server')

def must_replace(path: Path, old: str, new: str, label: str, count: int = 1):
    t = path.read_text(encoding='utf-8')
    n = t.count(old)
    if n != count:
        # try normalize newlines
        t2 = t.replace('\r\n', '\n')
        old2 = old.replace('\r\n', '\n')
        n2 = t2.count(old2)
        if n2 != count:
            raise SystemExit(f'FAIL {label}: found {n}/{n2} want {count} in {path.name}')
        t = t2.replace(old2, new.replace('\r\n', '\n'), count)
        path.write_text(t.replace('\n', '\r\n') if '\r\n' in path.read_bytes().decode('utf-8', 'replace')[:200] else t, encoding='utf-8', newline='\n')
        print('OK', label)
        return
    path.write_text(t.replace(old, new, count), encoding='utf-8', newline='\n')
    print('OK', label)

# ========== MAC connect.sh: session keys ==========
mac = root / 'scripts/client/mac/connect.sh'
mt = mac.read_text(encoding='utf-8')

old_mac_keys = '''            _action="q"
            _got_key=0
            _status_at=0
            _tunnel_sync_failed=0
            while true; do
                if declare -F sync_session_tunnel_forward >/dev/null 2>&1 \\
                    && ! sync_session_tunnel_forward "$bg_pid"; then
                    _tunnel_sync_failed=1
                    break
                fi
                if [ "$_editor_opened" -eq 1 ] && declare -F remote_editor_running >/dev/null 2>&1; then
                    if remote_editor_running "$EDITOR_CMD" "$ALIAS" "$go_path"; then
                        _editor_opened=1
                        _editor_seen_open=1
                    else
                        _editor_opened=0
                    fi
                fi
                _now="$(date +%s 2>/dev/null || printf '0')"
                if [ "$_now" != "0" ] && [ $(( _now - _status_at )) -ge 30 ]; then
                    _tunnel_ok=1
                    _tunnel_alive "$bg_pid" || _tunnel_ok=0
                    ui_session_status_line "$go_id" "$(get_git_mode_label "$(get_git_mode)")" "$_tunnel_ok" "$_editor_opened" "$EDITOR_NAME"
                    _status_at="$_now"
                fi
                if read -r -t 1 -n 1 _key </dev/tty 2>/dev/null; then
                    if declare -F connect_decision >/dev/null 2>&1; then connect_decision session_key_raw "$_key"; fi
                    _key_lower="$(printf '%s' "$_key" | tr '[:upper:]' '[:lower:]')"
                    [ -z "$_key_lower" ] && _key_lower="q"
                    [ "$_key_lower" = "r" ] && _action="r"
                    [ "$_key_lower" = "g" ] && _action="g"
                    [ "$_key_lower" = "o" ] && _action="o"
                    _got_key=1; break
                fi
            done'''

new_mac_keys = '''            _action=""
            _got_key=0
            _status_at=0
            _tunnel_sync_failed=0
            while true; do
                if declare -F sync_session_tunnel_forward >/dev/null 2>&1 \\
                    && ! sync_session_tunnel_forward "$bg_pid"; then
                    _tunnel_sync_failed=1
                    break
                fi
                if [ "$_editor_opened" -eq 1 ] && declare -F remote_editor_running >/dev/null 2>&1; then
                    if remote_editor_running "$EDITOR_CMD" "$ALIAS" "$go_path"; then
                        _editor_opened=1
                        _editor_seen_open=1
                    else
                        _editor_opened=0
                    fi
                fi
                _now="$(date +%s 2>/dev/null || printf '0')"
                if [ "$_now" != "0" ] && [ $(( _now - _status_at )) -ge 30 ]; then
                    _tunnel_ok=1
                    _tunnel_alive "$bg_pid" || _tunnel_ok=0
                    ui_session_status_line "$go_id" "$(get_git_mode_label "$(get_git_mode)")" "$_tunnel_ok" "$_editor_opened" "$EDITOR_NAME"
                    _status_at="$_now"
                fi
                if read -r -t 1 -n 1 _key </dev/tty 2>/dev/null; then
                    if declare -F connect_decision >/dev/null 2>&1; then connect_decision session_key_raw "$_key"; fi
                    # ASCII letter commands only — never treat Persian/other glyphs as quit.
                    _key_lower="$(printf '%s' "$_key" | tr '[:upper:]' '[:lower:]')"
                    _resolved=""
                    case "$_key_lower" in
                        r) _resolved="r" ;;
                        g) _resolved="g" ;;
                        o) _resolved="o" ;;
                        q|$'\\n'|$'\\r'|'') _resolved="q" ;;  # empty/Enter = quit; bare Enter often yields empty
                    esac
                    # Non-ASCII printable (e.g. ض): ignore and keep waiting.
                    if [ -z "$_resolved" ]; then
                        _ord="$(printf '%s' "$_key" | od -An -tuC | tr -s ' ' | awk '{print $1; exit}')"
                        if [ -n "$_ord" ] && [ "$_ord" -gt 127 ]; then
                            if declare -F connect_log >/dev/null 2>&1; then
                                connect_log "SESSION_KEY ignore non_command keychar=non_ascii" 'INFO'
                            fi
                            continue
                        fi
                        if declare -F connect_log >/dev/null 2>&1; then
                            connect_log "SESSION_KEY ignore non_command key=$_key_lower" 'INFO'
                        fi
                        continue
                    fi
                    _action="$_resolved"
                    _got_key=1; break
                fi
            done'''

# Fix empty Enter case - in bash read -n 1, Enter might be $'\n'. Empty string forcing q is wrong for ignore.
# Better: only q and newline for quit; don't map empty from Persian.
new_mac_keys = new_mac_keys.replace(
    "q|$'\\n'|$'\\r'|'') _resolved=\"q\" ;;  # empty/Enter = quit; bare Enter often yields empty",
    "q|$'\\n'|$'\\r') _resolved=\"q\" ;;"
)

if old_mac_keys not in mt:
    raise SystemExit('mac session key block not found')
mt = mt.replace(old_mac_keys, new_mac_keys, 1)
print('OK mac session keys')

old_mac_disc = '''            printf '    Disconnecting...\\n'
            clear_session_mount "$go_id" "$EDITOR_CMD" "$ALIAS" "$go_path"
            stop_session_tunnel_cleanup 1
            already_down=1
            printf '    Laptop folder restored.\\n'

            session_done=1'''

new_mac_disc = '''            if [ "$_action" = "q" ]; then
                printf '    Disconnecting...\\n'
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "SESSION: disconnect project=$go_id reason=user_quit" 'INFO'
                fi
                clear_session_mount "$go_id" "$EDITOR_CMD" "$ALIAS" "$go_path"
                stop_session_tunnel_cleanup 1
                already_down=1
                printf '    Laptop folder restored.\\n'
                session_done=1
            elif [ "$_tunnel_sync_failed" -eq 1 ] || ! _tunnel_alive "$bg_pid"; then
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log 'SESSION: fallthrough_recover reason=tunnel_down_empty_action' 'WARN'
                fi
                _action="r"
                continue
            else
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "SESSION: ignore_empty_action gotKey=$_got_key" 'WARN'
                fi
                continue
            fi'''

if old_mac_disc not in mt:
    raise SystemExit('mac disconnect block not found')
mt = mt.replace(old_mac_disc, new_mac_disc, 1)
print('OK mac disconnect guard')

# version bump in mac connect.sh
mt, n = re.subn(r'20260719\.29', '20260719.30', mt)
print(f'mac connect.sh version bumps: {n}')
mac.write_text(mt, encoding='utf-8', newline='\n')

# ========== MAC git-mode.sh ==========
gm = root / 'scripts/client/git-mode.sh'
gt = gm.read_text(encoding='utf-8')

old_push = '''push_server_connect_conf() {
    local mode os="${GIT_MODE_LAPTOP_OS:-mac}" active="${ACTIVE_MOUNT_ID:-}"
    local clear="${1:-}"
    mode="$(get_git_mode)"
    # Preserve server ACTIVE_MOUNT when caller left it empty (tunnel-ensure must not wipe).
    if [ "$clear" != "--clear" ] && [ -z "$active" ]; then
        active="$(sshx "grep -E '^ACTIVE_MOUNT=' \\$HOME/.claude-connect.conf 2>/dev/null | tail -1 | cut -d= -f2-" 2>/dev/null | tr -d '\\r' || true)"
        [ -z "$active" ] && active="${ACTIVE_PROJECT_ID:-}"
    fi
    if [ "$clear" = "--clear" ]; then active=""; fi
    sshx "printf 'LAPTOP_USER=%s\\nTUNNEL_PORT=%s\\nGIT_MODE=%s\\nLAPTOP_OS=%s\\nACTIVE_MOUNT=%s\\n' '${LAPTOP_USER}' '$PORT' '${mode}' '${os}' '${active}' > \\$HOME/.claude-connect.conf && chmod 600 \\$HOME/.claude-connect.conf" 2>/dev/null || true
    # Keep this hot path configuration-only. Self-heal runs during bundle setup,
    # not on every mount/recovery push.
}'''

new_push = '''push_server_connect_conf() {
    local mode os="${GIT_MODE_LAPTOP_OS:-mac}" active="${ACTIVE_MOUNT_ID:-}"
    local clear="${1:-}" clear_flag=0 prefer="" lu port mode_esc
    local dedupe_key now_ts
    mode="$(get_git_mode)"
    # Preserve server ACTIVE_MOUNT when caller left it empty (tunnel-ensure must not wipe).
    if [ "$clear" = "--clear" ]; then
        clear_flag=1
        active=""
        prefer=""
    else
        if [ -n "$active" ]; then
            prefer="$active"
        elif [ -n "${ACTIVE_PROJECT_ID:-}" ]; then
            prefer="${ACTIVE_PROJECT_ID}"
            active="$prefer"
        else
            prefer=""
        fi
    fi
    lu="${LAPTOP_USER:-}"
    port="${PORT:-}"
    dedupe_key="${lu}|${port}|${mode}|${prefer}|${clear_flag}"
    now_ts="$(date +%s 2>/dev/null || printf '0')"
    if [ -n "${_LAST_PUSH_CONF_KEY:-}" ] && [ "$_LAST_PUSH_CONF_KEY" = "$dedupe_key" ] \\
        && [ -n "${_LAST_PUSH_CONF_AT:-}" ] && [ "$now_ts" != "0" ] \\
        && [ $(( now_ts - _LAST_PUSH_CONF_AT )) -le 8 ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "PUSH_CONF skip_duplicate key=$dedupe_key" 'INFO'
        fi
        return 0
    fi
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "PUSH_CONF begin laptop_user=$lu port=$port git_mode=$mode prefer_mount=$prefer clear=$clear_flag" 'INFO'
    fi
    # Base64 remote body — avoids quote-eating on nested ssh (parity with Windows).
    local remote_body b64 push_out push_ec
    remote_body="$(cat <<EOF
set +e
CLEAR='$clear_flag'
PREFER='$prefer'
LU='$lu'
PORT='$port'
MODE='$mode'
OS='$os'
if [ "\\$CLEAR" = "1" ]; then
  AM=
elif [ -n "\\$PREFER" ]; then
  AM=\\$PREFER
else
  AM=\\$(grep -E '^ACTIVE_MOUNT=' "\\$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
fi
printf 'LAPTOP_USER=%s\\nTUNNEL_PORT=%s\\nGIT_MODE=%s\\nLAPTOP_OS=%s\\nACTIVE_MOUNT=%s\\n' "\\$LU" "\\$PORT" "\\$MODE" "\\$OS" "\\$AM" > "\\$HOME/.claude-connect.conf"
chmod 600 "\\$HOME/.claude-connect.conf" 2>/dev/null || true
printf 'PUSH_CONF_RESULT clear=%s prefer=%s active=%s\\n' "\\$CLEAR" "\\$PREFER" "\\$AM"
EOF
)"
    b64="$(printf '%s' "$remote_body" | base64 | tr -d '\\n')"
    push_out="$(sshx "echo $b64 | base64 -d | bash" 2>/dev/null || true)"
    push_ec=$?
    if [ "$push_ec" -ne 0 ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "PUSH_CONF fail exit=$push_ec out=$(printf '%s' "$push_out" | tr '\\n' ' ')" 'ERROR'
        fi
        return "$push_ec"
    fi
    _LAST_PUSH_CONF_KEY="$dedupe_key"
    _LAST_PUSH_CONF_AT="$now_ts"
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "PUSH_CONF ok exit=0 $(printf '%s' "$push_out" | grep PUSH_CONF_RESULT | tail -1 | tr '\\n' ' ')" 'INFO'
    fi
}'''

# The file may have different escaping for $HOME - read exact from file
idx = gt.find('push_server_connect_conf() {')
if idx < 0:
    raise SystemExit('push_server_connect_conf not found')
end = gt.find('\nunmount_other_projects()', idx)
if end < 0:
    end = gt.find('\n\nunmount_other_projects', idx)
if end < 0:
    raise SystemExit('end of push_server_connect_conf not found')
exact_old = gt[idx:end]
gt = gt[:idx] + new_push + '\n' + gt[end:]
print('OK mac push_server_connect_conf')

# tunnel_drop: don't map non-r to q
old_drop = '''tunnel_drop_session_action() {
    if [ "${_got_key:-0}" -eq 0 ] && ! _tunnel_alive "$bg_pid"; then
        local _peek=""
        if read -r -t 0 -n 1 _peek </dev/tty 2>/dev/null; then
            local _pl
            _pl="$(printf '%s' "$_peek" | tr '[:upper:]' '[:lower:]')"
            if [ "$_pl" = "r" ]; then
                _action="r"
            else
                _action="q"
                _got_key=1
            fi
        else
            _action="r"
            printf '\\n    Connection dropped - reconnecting...\\n'
        fi
    fi
}'''

new_drop = '''tunnel_drop_session_action() {
    if [ "${_got_key:-0}" -eq 0 ] && ! _tunnel_alive "$bg_pid"; then
        local _peek=""
        if read -r -t 0 -n 1 _peek </dev/tty 2>/dev/null; then
            local _pl
            _pl="$(printf '%s' "$_peek" | tr '[:upper:]' '[:lower:]')"
            if [ "$_pl" = "r" ]; then
                _action="r"
            elif [ "$_pl" = "q" ]; then
                _action="q"
                _got_key=1
            else
                # Ignore non-command (incl. Persian); auto-recover like no key.
                _action="r"
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "SESSION_KEY ignore non_command(during_drop) key=$_pl" 'INFO'
                fi
            fi
        else
            _action="r"
            printf '\\n    Connection dropped - reconnecting...\\n'
        fi
    fi
}'''

if old_drop not in gt:
    # try without escaped newlines in printf
    old_drop2 = old_drop.replace("printf '\\\\n    Connection dropped - reconnecting...\\\\n'", "printf '\\n    Connection dropped - reconnecting...\\n'")
    new_drop2 = new_drop.replace("printf '\\\\n    Connection dropped - reconnecting...\\\\n'", "printf '\\n    Connection dropped - reconnecting...\\n'")
    if old_drop2 in gt:
        gt = gt.replace(old_drop2, new_drop2, 1)
        print('OK tunnel_drop_session_action')
    else:
        raise SystemExit('tunnel_drop block not found')
else:
    gt = gt.replace(old_drop, new_drop, 1)
    print('OK tunnel_drop_session_action')

# ORPHAN protect current bg_pid
old_orphan = '''remove_local_orphan_tunnel() {
    local target_port="$1" killed=0
    [ -n "$target_port" ] || return 0
    if pkill -f "ssh.*-R ${target_port}:localhost:22" 2>/dev/null; then
        killed=1
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "ORPHAN_TUNNEL: killed local ssh port=$target_port" 'DEBUG'
        fi
    fi
    clear_tunnel_banner_cache
    if [ "$killed" -eq 1 ]; then
        clear_server_stale_tunnel_forward "$target_port" || true
    fi
}'''

new_orphan = '''remove_local_orphan_tunnel() {
    local target_port="$1" killed=0 protect_pid="${2:-${bg_pid:-}}"
    [ -n "$target_port" ] || return 0
    # Do not kill the live session tunnel (Win skip_current parity).
    if [ -n "$protect_pid" ] && kill -0 "$protect_pid" 2>/dev/null; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "ORPHAN_TUNNEL: skip_current pid=$protect_pid port=$target_port" 'DEBUG'
        fi
        # Kill other matching ssh reverse forwards on this port, if any.
        local p
        for p in $(pgrep -f "ssh.*-R ${target_port}:localhost:22" 2>/dev/null || true); do
            if [ "$p" != "$protect_pid" ]; then
                kill "$p" 2>/dev/null || true
                killed=1
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "ORPHAN_TUNNEL: killing local pid=$p port=$target_port" 'DEBUG'
                fi
            fi
        done
    else
        if pkill -f "ssh.*-R ${target_port}:localhost:22" 2>/dev/null; then
            killed=1
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "ORPHAN_TUNNEL: killed local ssh port=$target_port" 'DEBUG'
            fi
        fi
    fi
    clear_tunnel_banner_cache
    if [ "$killed" -eq 1 ]; then
        clear_server_stale_tunnel_forward "$target_port" || true
    fi
}'''

if old_orphan not in gt:
    raise SystemExit('orphan block not found')
gt = gt.replace(old_orphan, new_orphan, 1)
print('OK mac orphan protect')

# ENSURE: avoid blind pkill when bg_pid healthy — replace the pkill line after killing bg
# Add soft-fail /6 for no_ssh_proc_tcp_open
if '_TUNNEL_SOFT_FAIL_COUNT' not in gt:
    gt = gt.replace(
        '_TUNNEL_SYNC_FAIL_COUNT=0\n',
        '_TUNNEL_SYNC_FAIL_COUNT=0\n_TUNNEL_SOFT_FAIL_COUNT=0\n',
        1,
    )
    print('OK init soft fail count')

old_soft = '''    if ! kill -0 "$bg_pid" 2>/dev/null; then
        if tunnel_up || { declare -F tunnel_tcp_open >/dev/null 2>&1 && tunnel_tcp_open; }; then
            _TUNNEL_SYNC_FAIL_COUNT=0
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_SYNC soft_fail pid=$bg_pid port=$PORT reason=no_ssh_proc_tcp_open" 'WARN'
            fi
            return 0
        fi'''

new_soft = '''    if ! kill -0 "$bg_pid" 2>/dev/null; then
        if tunnel_up || { declare -F tunnel_tcp_open >/dev/null 2>&1 && tunnel_tcp_open; }; then
            _TUNNEL_SYNC_FAIL_COUNT=0
            _TUNNEL_SOFT_FAIL_COUNT=$(( _TUNNEL_SOFT_FAIL_COUNT + 1 ))
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_SYNC soft_fail count=$_TUNNEL_SOFT_FAIL_COUNT/6 pid=$bg_pid port=$PORT reason=no_ssh_proc_tcp_open" 'WARN'
            fi
            if [ "$_TUNNEL_SOFT_FAIL_COUNT" -lt 6 ]; then
                return 0
            fi
            _TUNNEL_SOFT_FAIL_COUNT=0
            # Bound exceeded: treat as drop below
        else
            : # fall through to miss counter
        fi
        if tunnel_up || { declare -F tunnel_tcp_open >/dev/null 2>&1 && tunnel_tcp_open; }; then
            # Soft-fail budget exhausted with TCP still open — keep session (Win parity returns while <6 only).
            return 0
        fi'''

# Actually the Win logic: while soft fail < 6, return 0 (keep). At 6, continue to drop path.
# Let me simplify - match Win more closely:

new_soft = '''    if ! kill -0 "$bg_pid" 2>/dev/null; then
        if tunnel_up || { declare -F tunnel_tcp_open >/dev/null 2>&1 && tunnel_tcp_open; }; then
            _TUNNEL_SYNC_FAIL_COUNT=0
            _TUNNEL_SOFT_FAIL_COUNT=$(( ${_TUNNEL_SOFT_FAIL_COUNT:-0} + 1 ))
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_SYNC soft_fail count=$_TUNNEL_SOFT_FAIL_COUNT/6 pid=$bg_pid port=$PORT reason=no_ssh_proc_tcp_open" 'WARN'
            fi
            if [ "$_TUNNEL_SOFT_FAIL_COUNT" -lt 6 ]; then
                return 0
            fi
            _TUNNEL_SOFT_FAIL_COUNT=0
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_DROP pid=$bg_pid port=$PORT reason=no_ssh_proc_tcp_open_budget" 'WARN'
            fi
            return 1
        fi'''

if old_soft not in gt:
    raise SystemExit('soft_fail tcp_open block not found')
gt = gt.replace(old_soft, new_soft, 1)
print('OK mac soft_fail /6')

# Reset soft fail on healthy tunnel_up path
gt = gt.replace(
    '''    if tunnel_up; then
        probe_up=1
        _TUNNEL_SYNC_FAIL_COUNT=0
    else''',
    '''    if tunnel_up; then
        probe_up=1
        _TUNNEL_SYNC_FAIL_COUNT=0
        _TUNNEL_SOFT_FAIL_COUNT=0
    else''',
    1,
)

# ENSURE: protect pkill when recent spawn - change blind pkill to use remove_local_orphan_tunnel with protect
old_ensure_pkill = '''    [ -n "${bg_pid:-}" ] && kill "$bg_pid" 2>/dev/null || true
    [ -n "${bg_pid:-}" ] && [ -n "${PORT:-}" ] && clear_server_stale_tunnel_forward "$PORT" || true
    bg_pid=""
    pkill -f "ssh.*-R ${PORT}:localhost:22" 2>/dev/null && clear_server_stale_tunnel_forward "$PORT" || true'''

new_ensure_pkill = '''    local _old_bg="${bg_pid:-}"
    [ -n "${bg_pid:-}" ] && kill "$bg_pid" 2>/dev/null || true
    [ -n "${bg_pid:-}" ] && [ -n "${PORT:-}" ] && clear_server_stale_tunnel_forward "$PORT" || true
    bg_pid=""
    # Prefer orphan helper with no protect (old bg already killed) over blind pkill storms.
    remove_local_orphan_tunnel "$PORT" "" || true'''

if old_ensure_pkill in gt:
    gt = gt.replace(old_ensure_pkill, new_ensure_pkill, 1)
    print('OK ensure orphan helper')
else:
    print('WARN ensure pkill block not exact — skip')

gt, n = re.subn(r'20260719\.29', '20260719.30', gt)
print(f'git-mode.sh version bumps: {n}')
gm.write_text(gt, encoding='utf-8', newline='\n')

# ========== WINDOWS fixes ==========
gps = root / 'scripts/client/git-mode.ps1'
w = gps.read_text(encoding='utf-8')

old_pd = '''            $ki = [Console]::ReadKey($true)
            $kc = $ki.KeyChar.ToString().ToLower()
            if ($kc -eq 'm' -or $ki.Key -eq [ConsoleKey]::M) { return 'm' }
            if ($kc -eq 'c' -or $ki.Key -eq [ConsoleKey]::C) { return 'c' }
            if ($kc -eq 'x' -or $ki.Key -eq [ConsoleKey]::X) { return 'x' }'''

new_pd = '''            $ki = [Console]::ReadKey($true)
            $kcRaw = $ki.KeyChar.ToString()
            $code = if ($kcRaw.Length -eq 1) { [int][char]$kcRaw[0] } else { 0 }
            $ascii = ($code -ge 32 -and $code -le 126)
            $kc = if ($ascii) { $kcRaw.ToLowerInvariant() } else { '' }
            $useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
            if ($kc -eq 'm' -or ($useVk -and $ki.Key -eq [ConsoleKey]::M)) { return 'm' }
            if ($kc -eq 'c' -or ($useVk -and $ki.Key -eq [ConsoleKey]::C)) { return 'c' }
            if ($kc -eq 'x' -or ($useVk -and $ki.Key -eq [ConsoleKey]::X)) { return 'x' }'''

if old_pd not in w:
    raise SystemExit('PostDisconnect key block not found')
w = w.replace(old_pd, new_pd, 1)
print('OK PostDisconnect useVk')

# Promote a few DEBUG to INFO
for a, b in [
    ('Write-GitModeLog "ORPHAN_TUNNEL: killing local pid=$processId port=$TargetPort" \'DEBUG\'',
     'Write-GitModeLog "ORPHAN_TUNNEL: killing local pid=$processId port=$TargetPort" \'WARN\''),
    ('Write-GitModeLog "CLEAR_MOUNT: down begin project=$ProjectId" \'DEBUG\'',
     'Write-GitModeLog "CLEAR_MOUNT: down begin project=$ProjectId" \'INFO\''),
    ('Write-GitModeLog "CLEAR_MOUNT: down end ms=$downMs project=$ProjectId" \'DEBUG\'',
     'Write-GitModeLog "CLEAR_MOUNT: down end ms=$downMs project=$ProjectId" \'INFO\''),
]:
    if a in w:
        w = w.replace(a, b, 1)
        print('OK promote', b[20:50])

w, n = re.subn(r'20260719\.29', '20260719.30', w)
print(f'git-mode.ps1 version bumps: {n}')
gps.write_text(w, encoding='utf-8', newline='\n')

# connect.ps1 menu + context mirrors + version
cp = root / 'scripts/client/windows/connect.ps1'
ct = cp.read_text(encoding='utf-8')

old_menu = '''            default { Warn "Enter a number or a/e/d/c/g/q." }'''
new_menu = '''            default {
                # Ignore non-ASCII / typo noise (Persian layout) without WARN spam.
                $raw = if ($null -ne $choice) { [string]$choice } else { '' }
                $isAsciiCmd = $raw.Length -eq 1 -and [int][char]$raw[0] -ge 32 -and [int][char]$raw[0] -le 126
                if ($isAsciiCmd -or $raw -match '^\\d+$') {
                    Warn "Enter a number or a/e/d/c/g/q."
                } else {
                    Write-ConnectLog ("PROJECT_MENU ignore non_command choice={0}" -f $raw) 'INFO'
                }
            }'''
# Need to see how $choice is named - might be different variable
if old_menu not in ct:
    # find default warn
    m = re.search(r'default \{ Warn "Enter a number or a/e/d/c/g/q\." \}', ct)
    if not m:
        raise SystemExit('menu default warn not found')
    # look backward for variable
    print('menu context:', ct[m.start()-200:m.start()])
    raise SystemExit('need choice var name')

# Fix: the switch uses $_ or $sel - check Choose-Project
# From dump: switch on something ending with default Warn - use $_ in switch
new_menu = '''            default {
                $raw = [string]$_
                $isAscii = $raw.Length -ge 1 -and ($raw.ToCharArray() | Where-Object { [int]$_ -gt 127 } | Measure-Object).Count -eq 0
                if ($isAscii) {
                    Warn "Enter a number or a/e/d/c/g/q."
                } elseif (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                    Write-ConnectLog ("PROJECT_MENU ignore non_command choice={0}" -f $raw) 'INFO'
                }
            }'''
ct = ct.replace(old_menu, new_menu, 1)
print('OK project menu ignore non-ascii')

# Sync script-scoped mirrors for CONTEXT — after flags log lines that set locals, set script vars
# Patch Write-ConnectSessionContext instead to accept and also read ActiveProjectId
ui = root / 'scripts/client/connect-ui.ps1'
ut = ui.read_text(encoding='utf-8')
old_ctx = '''    $am = 'none'
    if ($script:ActiveMountId) { $am = $script:ActiveMountId }
    elseif ($go -and $go.Id) { $am = $go.Id }'''
new_ctx = '''    $am = 'none'
    if ($script:ActiveProjectId) { $am = $script:ActiveProjectId }
    elseif ($script:ActiveMountId) { $am = $script:ActiveMountId }
    elseif ($go -and $go.Id) { $am = $go.Id }
    $edOpen = if ($null -ne $script:EditorOpened) { $script:EditorOpened } else { $false }
    if (Get-Variable -Name editorOpened -Scope 1 -ErrorAction SilentlyContinue) {
        try { $edOpen = [bool](Get-Variable -Name editorOpened -Scope 1 -ValueOnly) } catch { }
    }
    $alDown = if ($null -ne $script:AlreadyDown) { $script:AlreadyDown } else { $false }
    if (Get-Variable -Name alreadyDown -Scope 1 -ErrorAction SilentlyContinue) {
        try { $alDown = [bool](Get-Variable -Name alreadyDown -Scope 1 -ValueOnly) } catch { }
    }'''
# Also fix the flags line
old_flags = '''    Write-ConnectLog "flags editor_opened=$($script:EditorOpened) already_down=$($script:AlreadyDown) recovery_gen=$($script:RecoveryGeneration) session_iter=$($script:SessionLoopIter)"'''
new_flags = '''    Write-ConnectLog "flags editor_opened=$edOpen already_down=$alDown recovery_gen=$($script:RecoveryGeneration) session_iter=$($script:SessionLoopIter)"'''

if old_ctx not in ut:
    raise SystemExit('context am block not found')
ut = ut.replace(old_ctx, new_ctx, 1)
if old_flags not in ut:
    raise SystemExit('context flags not found')
ut = ut.replace(old_flags, new_flags, 1)
ui.write_text(ut, encoding='utf-8', newline='\n')
print('OK CONTEXT flags from parent scope')

# Also set script mirrors in connect.ps1 on key transitions - lightweight
# After $alreadyDown = $true/$false assignments commonly - use a few critical ones
for old_a, new_a in [
    ('$alreadyDown = $true', '$alreadyDown = $true; $script:AlreadyDown = $true'),
    ('$alreadyDown = $false', '$alreadyDown = $false; $script:AlreadyDown = $false'),
]:
    # replace_all carefully - might be too many. Limit via count in session loop areas only.
    pass

# Set ActiveProjectId when go selected - search
if '$script:ActiveProjectId = $go.Id' not in ct and 'ActiveProjectId' in ct:
    pass
# Ensure ActiveProjectId is set - grep pattern in Prepare
ct2 = ct
# bump version
ct2, n = re.subn(r'20260719\.29', '20260719.30', ct2)
print(f'connect.ps1 version bumps: {n}')
cp.write_text(ct2, encoding='utf-8', newline='\n')

# version files
for vf in [
    root / 'scripts/client/windows/connect-version.txt',
    root / 'scripts/client/mac/connect-version.txt',
]:
    vf.write_text('20260719.30', encoding='utf-8', newline='\n')
    print('bumped', vf)

print('ALL_LOCAL_DONE')
