# git-mode.sh - shared GIT_MODE helpers (sourced by connect.sh forks)
# Requires: CFG_DIR, CM, PORT, LAPTOP_USER; functions sshx, warn; optional bg_pid + _tunnel_alive

if ! declare -f warn >/dev/null 2>&1; then
    warn() { printf '  [!] %s\n' "$*" >&2; }
fi

GIT_CONF="$CFG_DIR/git.conf"

get_git_mode() {
    # Site policy: GIT_MODE hide/server disabled. Always OFF.
    if [ -n "${GIT_CONF:-}" ]; then
        mkdir -p "$(dirname "$GIT_CONF")" 2>/dev/null || true
        printf 'off\n' > "$GIT_CONF" 2>/dev/null || true
    fi
    echo off
}

get_active_mount_id() {
    local line
    line="$(sshx "grep ^ACTIVE_MOUNT= \$HOME/.claude-connect.conf 2>/dev/null" 2>/dev/null | tail -1 || true)"
    line="${line#ACTIVE_MOUNT=}"
    line="${line//$'\r'/}"
    line="${line//$'\n'/}"
    printf '%s' "$line"
}

get_git_mode_label() {
    case "${1:-off}" in
        server|slow) printf 'SLOW' ;;
        hide|fast) printf 'HIDE' ;;
        *) printf 'OFF' ;;
    esac
}

_TUNNEL_BANNER_CACHE_AT=0
_TUNNEL_BANNER_CACHE_BANNER=''
_TUNNEL_BANNER_CACHE_UP=0
_TUNNEL_BANNER_CACHE_NEGATIVE=0
_TUNNEL_BANNER_CACHE_INVALID=0
_LAST_FORWARD_PROBE_AT=0
_TUNNEL_FORWARD_PROBE_INTERVAL_SEC=45
_TUNNEL_SYNC_FAIL_COUNT=0
_TUNNEL_SOFT_FAIL_COUNT=0
_TUNNEL_BANNER_DEFER_COUNT=0
_LAST_TUNNEL_SPAWN_SUCCESS_AT=0
_LAST_TUNNEL_SPAWN_SUCCESS_PORT=
_LAST_TUNNEL_SPAWN_PID=
# Still-busy spawn abort window (clear -> ensure race). Locked by test-stale-forward-wait-init.
STILL_BUSY_WINDOW_SEC=15
_LAST_STALE_FORWARD_STILL_BUSY_PORT=
_LAST_STALE_FORWARD_STILL_BUSY_AT=0
# Still-busy refuse_spawn streak cap. Locked by test-stale-forward-rebind-streak.
REFUSE_SPAWN_STREAK_CAP=5
_REFUSE_SPAWN_STREAK=0
# Wait/poll iteration cap (was 12). Locked by test-tunnel-wait-backoff-fanout.
TUNNEL_WAIT_MAX_ATTEMPTS=6
# Owner/service coupling: release empty lease after backends-down + xray-expected.
# Locked by test-proxy-owner-service-coupling (S3 SERVICE_DEAD_SEC=60).
SERVICE_DEAD_SEC=60
_PROXY_OWNER_SERVICE_DEAD_SINCE=0
SESSION_EVER_HAD_PROXY_LEGS=0
# Injectable epoch seconds for tests (empty => date +%s).
_CURSOR_PROXY_HEALTH_NOW=
# Sync no_proc keep-alive time-box (Task 5). Locked by test-tunnel-no-proc-keepalive (S3=120).
NO_PROC_ZOMBIE_SEC=120
_NO_PROC_KEEPALIVE_SINCE=0
# Injectable epoch seconds for no_proc age-gate tests (empty => date +%s).
_NO_PROC_ZOMBIE_NOW=

clear_tunnel_banner_cache() {
    _TUNNEL_BANNER_CACHE_AT=0
    _TUNNEL_BANNER_CACHE_BANNER=''
    _TUNNEL_BANNER_CACHE_UP=0
    _TUNNEL_BANNER_CACHE_NEGATIVE=0
    _TUNNEL_BANNER_CACHE_INVALID=1
}

# Transport/timeout strings are NOT SSH banners (real banners start with SSH-2.0-).
tunnel_banner_is_transport_noise() {
    local banner="${1:-}"
    [ -n "$banner" ] || return 1
    printf '%s' "$banner" | grep -q '^SSH-2\.0-' && return 1
    printf '%s' "$banner" | grep -Eqi 'Unknown error|Connection timed out|Connection refused|Could not resolve|No route to host|Network is unreachable|Connection reset|Operation timed out|banner exchange|Connection closed|^ssh:|timed out|Name or service not known'
}

wait_pid_timeout() {
    local pid="$1" label="${2:-job}" timeout_sec="${3:-30}" waited=0 rc=0
    [ -n "$pid" ] || return 0
    while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$timeout_sec" ]; do
        sleep 1
        waited=$((waited + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "SCP: timeout ERROR label=$label sec=$timeout_sec" 'ERROR'
        fi
        return 1
    fi
    wait "$pid" 2>/dev/null || rc=$?
    return "$rc"
}

test_is_primary_tunnel_publisher() {
    # Slot preference only: UI slot 0 (or legacy unset) is the preferred publisher.
    # Remote AM_ONLY body may still let a non-primary publish via port_takeover.
    local slot="${CLAUDE_CONNECT_UI_SLOT:-}"
    slot="$(printf '%s' "$slot" | tr -d '[:space:]')"
    [ -z "$slot" ] && return 0
    [ "$slot" = "0" ]
}

_push_conf_sq_escape() {
    # Escape for embedding inside a single-quoted bash assignment.
    local s="${1:-}"
    s="${s//\'/\'\\\'\'}"
    printf '%s' "$s"
}

push_server_connect_conf() {
    if [ -z "${LAPTOP_HOSTKEY_FP:-}" ]; then
        LAPTOP_HOSTKEY_FP="$(get_stored_laptop_hostkey_fp || true)"
    fi

    # Never publish another peer's reverse port into ~/.claude-connect.conf.
    if [ -n "${PORT:-}" ] && tunnel_port_is_foreign_peer "$PORT"; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "PUSH_CONF blocked: foreign_peer port=$PORT" 'ERROR'
        fi
        return 0
    fi
    if [ -n "${PORT:-}" ] && tunnel_hostkey_mismatch "$PORT"; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "PUSH_CONF blocked: hostkey_mismatch port=$PORT" 'ERROR'
        fi
        return 0
    fi
    local mode os="${GIT_MODE_LAPTOP_OS:-mac}" active="${ACTIVE_MOUNT_ID:-}"
    local clear="${1:-}" clear_flag=0 prefer="" lu port
    local dedupe_key now_ts am_only=0 am_only_flag=0 publish_port_log
    local prefer_esc lu_esc mode_esc slot_esc hk_esc port_esc
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
    # Never push empty TUNNEL_PORT (hamed Mac NO_PORT). Prefer session PORT, else local CFG,
    # else formula 20000+(UID-1000)*10+slot when SERVER_UID_STR is known.
    if [ -z "$port" ] || [ "$port" = "0" ]; then
        if [ -f "${CFG:-}" ]; then
            port="$(grep -E '^TUNNEL_PORT=' "$CFG" 2>/dev/null | tail -1 | cut -d= -f2- | tr -dc '0-9')"
        fi
    fi
    if [ -z "$port" ] || [ "$port" = "0" ]; then
        if [ -z "${SERVER_UID_STR:-}" ]; then
            SERVER_UID_STR="$(sshx 'id -u' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+$' | head -1 | tr -dc '0-9')"
        fi
        _uid_fb="${SERVER_UID_STR:-}"
        _slot_fb="${TUNNEL_SLOT:-0}"
        case "$_slot_fb" in ''|*[!0-9]*) _slot_fb=0 ;; esac
        if [ -n "$_uid_fb" ] && declare -F tunnel_port_user_base >/dev/null 2>&1; then
            _base_fb="$(tunnel_port_user_base "$_uid_fb")"
            port=$(( _base_fb + _slot_fb ))
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "PUSH_CONF port_from_formula uid=$_uid_fb slot=$_slot_fb port=$port" 'INFO'
            fi
        fi
        unset _uid_fb _slot_fb _base_fb
    fi
    # Non-primary still pushes ACTIVE_MOUNT(+GIT_MODE); prefer not to overwrite primary TUNNEL_PORT.
    if ! test_is_primary_tunnel_publisher; then
        am_only=1
        am_only_flag=1
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "PUSH_CONF am_only slot=${CLAUDE_CONNECT_UI_SLOT:-} port=$port publish_port=0" 'INFO'
        fi
    fi
    dedupe_key="${lu}|${port}|${mode}|${prefer}|${clear_flag}|${am_only_flag}"
    now_ts="$(date +%s 2>/dev/null || printf '0')"
    if [ -n "${_LAST_PUSH_CONF_KEY:-}" ] && [ "$_LAST_PUSH_CONF_KEY" = "$dedupe_key" ] \
        && [ -n "${_LAST_PUSH_CONF_AT:-}" ] && [ "$now_ts" != "0" ] \
        && [ $(( now_ts - _LAST_PUSH_CONF_AT )) -le 8 ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "PUSH_CONF skip_duplicate key=$dedupe_key" 'INFO'
        fi
        return 0
    fi
    prefer_esc="$(_push_conf_sq_escape "$prefer")"
    lu_esc="$(_push_conf_sq_escape "$lu")"
    mode_esc="$(_push_conf_sq_escape "$mode")"
    slot_esc="$(_push_conf_sq_escape "${TUNNEL_SLOT:-}")"
    hk_esc="$(_push_conf_sq_escape "${LAPTOP_HOSTKEY_FP:-}")"
    port_esc="$(_push_conf_sq_escape "$port")"
    publish_port_log="$port"
    [ "$am_only_flag" = "1" ] && publish_port_log=0
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "PUSH_CONF begin laptop_user=$lu port=$port slot=${TUNNEL_SLOT:-} git_mode=$mode prefer_mount=$prefer clear=$clear_flag am_only=$am_only_flag publish_port=$publish_port_log" 'INFO'
    fi
    # Base64 remote body - avoids quote-eating on nested ssh (parity with Windows).
    # ACTIVE_MOUNT_GUARD / AM_ONLY / port_takeover / port_mismatch_keep / primary_soft_keep match Win.
    local remote_body b64 push_out push_ec
    remote_body="$(cat <<EOF
set +e
CLEAR='$clear_flag'
PREFER='$prefer_esc'
LU='$lu_esc'
PORT='$port_esc'
SLOT='$slot_esc'
MODE='$mode_esc'
HK='$hk_esc'
AM_ONLY='$am_only_flag'
CUR_AM=\$(grep -E '^ACTIVE_MOUNT=' "\$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
CUR_PORT=\$(grep -E '^TUNNEL_PORT=' "\$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
CUR_SLOT=\$(grep -E '^TUNNEL_SLOT=' "\$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
if [ "\$CLEAR" = "1" ]; then
  AM=
elif [ -n "\$PREFER" ]; then
  if [ -n "\$CUR_AM" ] && [ "\$CUR_AM" != "\$PREFER" ] && mountpoint -q "\$HOME/mounts/\$CUR_AM" 2>/dev/null; then
    AM=\$CUR_AM
    printf 'ACTIVE_MOUNT_GUARD keep=%s prefer=%s reason=other_still_mounted\n' "\$CUR_AM" "\$PREFER"
  else
    AM=\$PREFER
    if [ -n "\$CUR_AM" ] && [ "\$CUR_AM" != "\$PREFER" ]; then
      printf 'ACTIVE_MOUNT_STEAL from=%s to=%s\n' "\$CUR_AM" "\$PREFER"
    fi
  fi
else
  AM=\$CUR_AM
fi
if [ "\$AM_ONLY" = "1" ]; then
  if [ -n "\$CUR_PORT" ]; then
    # P1.3 liveness override: slot-index am_only must not permanently keep a dead
    # published port. Take over ONLY when CUR_PORT has no listener AND this
    # session's PORT is listening.
    CUR_LIVE=0
    if timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/'\$CUR_PORT 2>/dev/null; then
      CUR_LIVE=1
    fi
    OUR_LIVE=0
    if [ -n "\$PORT" ] && [ "\$PORT" != "0" ]; then
      if timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/'\$PORT 2>/dev/null; then
        OUR_LIVE=1
      fi
    fi
    if [ "\$CUR_LIVE" = "0" ] && [ "\$OUR_LIVE" = "1" ]; then
      PORT_OUT=\$PORT
      SLOT_OUT=\$SLOT
      PUBLISH_PORT=\$PORT
      printf 'PUSH_CONF port_takeover published_dead=%s session=%s slot=%s\n' "\$CUR_PORT" "\$PORT" "\$SLOT"
    else
      PORT_OUT=\$CUR_PORT
      SLOT_OUT=\$CUR_SLOT
      if [ -n "\$PORT" ] && [ "\$PORT" != "\$CUR_PORT" ]; then
        printf 'PUSH_CONF port_mismatch_keep session=%s server=%s cur_live=%s our_live=%s\n' "\$PORT" "\$CUR_PORT" "\$CUR_LIVE" "\$OUR_LIVE"
      fi
      PUBLISH_PORT=0
    fi
  else
    PORT_OUT=\$PORT
    SLOT_OUT=\$SLOT
    PUBLISH_PORT=0
  fi
else
  # Primary soft-liveness: when published CUR_PORT differs from this session PORT,
  # keep CUR only if both listeners are up AND a live sshfs under ~/mounts uses -p CUR.
  # Otherwise primary may overwrite (fleet reclaim) or take over a dead published port.
  if [ -n "\$CUR_PORT" ] && [ "\$CUR_PORT" != "0" ] && [ -n "\$PORT" ] && [ "\$PORT" != "\$CUR_PORT" ]; then
    CUR_LIVE=0
    if timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/'\$CUR_PORT 2>/dev/null; then
      CUR_LIVE=1
    fi
    OUR_LIVE=0
    if [ -n "\$PORT" ] && [ "\$PORT" != "0" ]; then
      if timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/'\$PORT 2>/dev/null; then
        OUR_LIVE=1
      fi
    fi
    MOUNT_ON_CUR=0
    for _m_pid in \$(pgrep -u "\$(id -un)" -f '[s]shfs' 2>/dev/null); do
      [ -r /proc/\$_m_pid/cmdline ] || continue
      _m_cmd=\$(tr '\0' ' ' < /proc/\$_m_pid/cmdline 2>/dev/null)
      case "\$_m_cmd" in
        *"\$HOME/mounts/"*) ;;
        *) continue ;;
      esac
      _m_p=\$(printf '%s' "\$_m_cmd" | sed -n 's/.* -p \([0-9][0-9]*\).*/\1/p; t; s/.* -p\([0-9][0-9]*\).*/\1/p')
      if [ "\$_m_p" = "\$CUR_PORT" ]; then
        MOUNT_ON_CUR=1
        break
      fi
    done
    unset _m_pid _m_cmd _m_p
    if [ "\$CUR_LIVE" = "1" ] && [ "\$OUR_LIVE" = "1" ] && [ "\$MOUNT_ON_CUR" = "1" ]; then
      PORT_OUT=\$CUR_PORT
      SLOT_OUT=\$CUR_SLOT
      PUBLISH_PORT=0
      printf 'PUSH_CONF primary_soft_keep session=%s server=%s reason=mount_on_cur\n' "\$PORT" "\$CUR_PORT"
    elif [ "\$CUR_LIVE" = "0" ] && [ "\$OUR_LIVE" = "1" ]; then
      PORT_OUT=\$PORT
      SLOT_OUT=\$SLOT
      PUBLISH_PORT=\$PORT
    else
      PORT_OUT=\$PORT
      SLOT_OUT=\$SLOT
      PUBLISH_PORT=\$PORT
      if [ "\$CUR_LIVE" = "1" ] && [ "\$MOUNT_ON_CUR" = "0" ]; then
        printf 'PUSH_CONF primary_overwrite cur_live=1 mount_on_cur=0\n'
      fi
    fi
  else
    PORT_OUT=\$PORT
    SLOT_OUT=\$SLOT
    PUBLISH_PORT=\$PORT
  fi
fi
# Never wipe TUNNEL_PORT (empty/0 PORT_OUT -> laptop-exec NO_PORT / legacy 20000+UID).
if { [ -z "\$PORT_OUT" ] || [ "\$PORT_OUT" = "0" ]; } && [ -n "\$CUR_PORT" ] && [ "\$CUR_PORT" != "0" ]; then
  PORT_OUT=\$CUR_PORT
  SLOT_OUT=\$CUR_SLOT
  printf 'PUSH_CONF port_empty_recovered server=%s\n' "\$CUR_PORT"
fi
if [ -z "\$PORT_OUT" ] || [ "\$PORT_OUT" = "0" ]; then
  printf 'PUSH_CONF_RESULT clear=%s prefer=%s active=%s am_only=%s publish_port=ABORT_EMPTY\n' "\$CLEAR" "\$PREFER" "\$AM" "\$AM_ONLY"
  exit 0
fi
mkdir -p "\$HOME/.local/bin"
printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nPORT=%s\nTUNNEL_SLOT=%s\nGIT_MODE=%s\nLAPTOP_OS=mac\nACTIVE_MOUNT=%s\nLAPTOP_HOSTKEY_FP=%s\n' "\$LU" "\$PORT_OUT" "\$PORT_OUT" "\$SLOT_OUT" "\$MODE" "\$AM" "\$HK" > "\$HOME/.claude-connect.conf"
chmod 600 "\$HOME/.claude-connect.conf" 2>/dev/null || true
printf 'PUSH_CONF_RESULT clear=%s prefer=%s active=%s am_only=%s publish_port=%s\n' "\$CLEAR" "\$PREFER" "\$AM" "\$AM_ONLY" "\$PUBLISH_PORT"
EOF
)"
    b64="$(printf '%s' "$remote_body" | base64 | tr -d '\n')"
    # Do not swallow sshx failures with || true - need real exit for RESULT/dedupe gate.
    push_out="$(sshx "echo $b64 | base64 -d | bash" 2>/dev/null)"
    push_ec=$?
    result_line="$(printf '%s' "$push_out" | grep PUSH_CONF_RESULT | tail -1 | tr '\n' ' ')"
    if [ "$push_ec" -ne 0 ] || [ -z "$result_line" ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "PUSH_CONF fail exit=$push_ec out=${result_line:-no_result} $(printf '%s' "$push_out" | tr '\n' ' ')" 'ERROR'
            # Win signal list (includes ACTIVE_MOUNT_GUARD + primary soft-liveness).
            for _push_sig in ABORT_EMPTY port_empty_recovered port_mismatch_keep port_takeover ACTIVE_MOUNT_GUARD ACTIVE_MOUNT_STEAL primary_soft_keep primary_overwrite; do
                case "${result_line:-} ${push_out:-}" in
                    *"$_push_sig"*)
                        _sig_lvl=INFO
                        [ "$_push_sig" = "ABORT_EMPTY" ] && _sig_lvl=WARN
                        connect_log "PUSH_CONF signal=$_push_sig out=${result_line:-no_result}" "$_sig_lvl"
                        if [ "$_push_sig" = "ACTIVE_MOUNT_STEAL" ]; then
                            _steal_from="$(printf '%s' "$push_out" | sed -n 's/.*ACTIVE_MOUNT_STEAL from=\([^ ]*\) to=\([^ ]*\).*/\1/p' | head -1)"
                            _steal_to="$(printf '%s' "$push_out" | sed -n 's/.*ACTIVE_MOUNT_STEAL from=\([^ ]*\) to=\([^ ]*\).*/\2/p' | head -1)"
                            [ -n "$_steal_from" ] && connect_log "ACTIVE_MOUNT_STEAL from=$_steal_from to=$_steal_to" 'INFO'
                            unset _steal_from _steal_to
                        fi
                        unset _sig_lvl
                        ;;
                esac
            done
            unset _push_sig
        fi
        # Do not record dedupe on failure - allow immediate retry.
        if [ "$push_ec" -ne 0 ]; then
            return "$push_ec"
        fi
        return 1
    fi
    _LAST_PUSH_CONF_KEY="$dedupe_key"
    _LAST_PUSH_CONF_AT="$now_ts"
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "PUSH_CONF ok exit=0 $result_line" 'INFO'
        for _push_sig in ABORT_EMPTY port_empty_recovered port_mismatch_keep port_takeover ACTIVE_MOUNT_GUARD ACTIVE_MOUNT_STEAL primary_soft_keep primary_overwrite; do
            case "${result_line:-} ${push_out:-}" in
                *"$_push_sig"*)
                    _sig_lvl=INFO
                    [ "$_push_sig" = "ABORT_EMPTY" ] && _sig_lvl=WARN
                    connect_log "PUSH_CONF signal=$_push_sig out=${result_line:-no_result}" "$_sig_lvl"
                    if [ "$_push_sig" = "ACTIVE_MOUNT_STEAL" ]; then
                        _steal_from="$(printf '%s' "$push_out" | sed -n 's/.*ACTIVE_MOUNT_STEAL from=\([^ ]*\) to=\([^ ]*\).*/\1/p' | head -1)"
                        _steal_to="$(printf '%s' "$push_out" | sed -n 's/.*ACTIVE_MOUNT_STEAL from=\([^ ]*\) to=\([^ ]*\).*/\2/p' | head -1)"
                        [ -n "$_steal_from" ] && connect_log "ACTIVE_MOUNT_STEAL from=$_steal_from to=$_steal_to" 'INFO'
                        unset _steal_from _steal_to
                    fi
                    unset _sig_lvl
                    ;;
            esac
        done
        unset _push_sig
    fi
}

unmount_other_projects() {
    local keep="${1:-}"
    [ -n "$keep" ] || return 0
    sshx "$CM down-others '$keep'" 2>/dev/null || true
}


push_remote_file_if_changed() {
    # remote may be ~/path - never run remote cmds with quoted "~" (no expand).
    # scp still gets the ~/ form (OpenSSH expands after host:).
    local src="$1" remote="$2" local_h="" remote_h="" rpath
    [ -f "$src" ] || return 0
    # Normalize: callers pass ~/path; never allow $HOME/~/path on the server.
    # IMPORTANT: do NOT use ${remote#~/} - bash tilde-expands the # pattern to $HOME/,
    # so the strip fails and rpath becomes $HOME/~/... (literal directory "~/").
    case "$remote" in
        '~/'*) remote="${remote:2}" ;;
        '~')   remote='' ;;
    esac
    case "$remote" in
        '')          rpath='\$HOME' ;;
        '$HOME/'*)   rpath="$remote" ;;
        /home/*)     rpath="$remote" ;;
        /*)          rpath="$remote" ;;
        *)           rpath="\$HOME/$remote" ;;
    esac
    local_h="$(local_file_sha256 "$src" 2>/dev/null || true)"
    remote_h="$(sshx "sha256sum $rpath 2>/dev/null | awk '{print \$1}'" 2>/dev/null | tr -d '\r\n')"
    [ -n "$local_h" ] && [ "$local_h" = "$remote_h" ] && return 0
    sshx "mkdir -p \"\$(dirname $rpath)\"" >/dev/null 2>&1 || true
    local scp_dest="$remote"
    case "$scp_dest" in
        ''|'$HOME') scp_dest='~' ;;
        '$HOME/'*)  scp_dest="~/${scp_dest:6}" ;;  # len('$HOME/')==6; avoid #~/ tilde pitfall
        /*)         ;;
        *)          scp_dest="~/$scp_dest" ;;
    esac
    # These targets can be live-executed concurrently (e.g. claude-watchdog polling
    # claude-mount, or claude-automount at login) - land in a .new sibling and mv
    # atomically into place so a running process never reads a torn file.
    scp -o BatchMode=yes -o ConnectTimeout=20 -q "$src" "$ALIAS:${scp_dest}.new" 2>/dev/null || return 1
    case "$scp_dest" in
        */laptop-exec|*/laptop-exec-setup|*/laptop-exec-guard.sh|*/laptop-exec-guard-wrap.sh|*/laptop-exec-shell-scan.py|*/laptop-exec-audit-log.sh|*/laptop-exec-session.sh|*/claude-self-heal|*/claude-automount)
            sshx "chmod +x ${rpath}.new && mv -f ${rpath}.new $rpath" >/dev/null 2>&1 || true ;;
        *)
            sshx "mv -f ${rpath}.new $rpath" >/dev/null 2>&1 || true ;;
    esac
    return 0
}

push_laptop_exec_bundle() {
    local server_dir="$1"
    [ -n "$server_dir" ] || return 0
    if [ ! -f "$server_dir/laptop-exec.sh" ]; then
        echo "  warn  LE push skipped: no laptop-exec.sh under $server_dir (mount-only; run: sudo claude-server deploy-laptop-exec)" >&2
        return 0
    fi
    push_remote_file_if_changed "$server_dir/laptop-exec.sh" '~/.local/bin/laptop-exec' || true
    push_remote_file_if_changed "$server_dir/laptop-exec-setup.sh" '~/.local/bin/laptop-exec-setup' || true
    push_remote_file_if_changed "$server_dir/claude-self-heal.sh" '~/.local/bin/claude-self-heal' || true
    push_remote_file_if_changed "$server_dir/claude-automount.sh" '~/.local/bin/claude-automount' || true
    push_remote_file_if_changed "$server_dir/cursor-rules/laptop-exec.mdc" '~/.cursor/rules/laptop-exec.mdc' || true
    push_remote_file_if_changed "$server_dir/skills/laptop-exec/SKILL.md" '~/.cursor/skills/laptop-exec/SKILL.md' || true
    push_remote_file_if_changed "$server_dir/cursor-hooks/laptop-exec-guard.sh" '~/.cursor/hooks/laptop-exec-guard.sh' || true
    push_remote_file_if_changed "$server_dir/cursor-hooks/laptop-exec-guard-wrap.sh" '~/.cursor/hooks/laptop-exec-guard-wrap.sh' || true
    push_remote_file_if_changed "$server_dir/cursor-hooks/laptop-exec-shell-scan.py" '~/.cursor/hooks/laptop-exec-shell-scan.py' || true
    push_remote_file_if_changed "$server_dir/cursor-hooks/laptop-exec-audit-log.sh" '~/.cursor/hooks/laptop-exec-audit-log.sh' || true
    push_remote_file_if_changed "$server_dir/cursor-hooks/laptop-exec-session.sh" '~/.cursor/hooks/laptop-exec-session.sh' || true
    # chmod + CRLF strip (safe for Mac and Windows-origin bundles)
    sshx "chmod +x \$HOME/.local/bin/laptop-exec \$HOME/.local/bin/laptop-exec-setup \$HOME/.local/bin/claude-self-heal \$HOME/.local/bin/claude-automount \$HOME/.cursor/hooks/laptop-exec-*.sh 2>/dev/null; sed -i 's/\r\$//' \$HOME/.local/bin/laptop-exec \$HOME/.local/bin/laptop-exec-setup \$HOME/.local/bin/claude-self-heal \$HOME/.local/bin/claude-automount \$HOME/.local/bin/claude-mount \$HOME/.cursor/hooks/laptop-exec-*.sh \$HOME/.cursor/hooks/laptop-exec-shell-scan.py 2>/dev/null; true" >/dev/null 2>&1 || true
    sshx '$HOME/.local/bin/laptop-exec-setup --user 2>/dev/null; /usr/local/bin/laptop-exec-setup --user 2>/dev/null; true' >/dev/null 2>&1 || true
    # Self-heal for Mac and Windows laptop sessions (server-side)
    sshx '$HOME/.local/bin/claude-self-heal --quiet 2>/dev/null; /usr/local/bin/claude-self-heal --quiet 2>/dev/null; true' >/dev/null 2>&1 || true
}

resolve_server_script_dir() {
    # Prefer full server tree (mount + laptop-exec) so LE hook push is not a no-op.
    local script_dir="$1" _rel _candidate d i
    d="$script_dir"
    i=0
    while [ "$i" -lt 8 ] && [ -n "$d" ] && [ "$d" != "/" ]; do
        _candidate="$d/scripts/server"
        if [ -f "$_candidate/claude-mount.sh" ] && [ -f "$_candidate/laptop-exec.sh" ]; then
            printf '%s' "$_candidate"
            return 0
        fi
        d="$(dirname "$d")"
        i=$((i + 1))
    done
    _candidate="$script_dir/server"
    if [ -f "$_candidate/claude-mount.sh" ] && [ -f "$_candidate/laptop-exec.sh" ]; then
        printf '%s' "$_candidate"
        return 0
    fi
    for _rel in "../server" "../../server" "../../../server"; do
        _candidate="$(cd "$script_dir/$_rel" 2>/dev/null && pwd)" || continue
        if [ -f "$_candidate/claude-mount.sh" ] && [ -f "$_candidate/laptop-exec.sh" ]; then
            printf '%s' "$_candidate"
            return 0
        fi
    done
    # Mount-only fallback
    d="$script_dir"
    i=0
    while [ "$i" -lt 8 ] && [ -n "$d" ] && [ "$d" != "/" ]; do
        _candidate="$d/scripts/server"
        if [ -f "$_candidate/claude-mount.sh" ]; then
            printf '%s' "$_candidate"
            return 0
        fi
        _candidate="$d/server"
        if [ -f "$_candidate/claude-mount.sh" ]; then
            printf '%s' "$_candidate"
            return 0
        fi
        d="$(dirname "$d")"
        i=$((i + 1))
    done
    return 1
}

stop_remote_editor() {
    local editor_cmd="$1" alias_name="$2" remote_path="$3"

    # Path/alias scoped only - never kill the whole ClaudeServerCursorProfile tree from mount clear.
    _stop_remote_editor_by_uri "$alias_name" "$remote_path"
}

_stop_remote_editor_by_uri() {
    local alias_name="$1" remote_path="$2"
    local uri_needle="ssh-remote+${alias_name}" path_needle="${remote_path%/}"
    local line pid cmd found=0

    _stop_remote_editor_pass() {
        local force="${1:-0}"
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            pid="${line%% *}"
            cmd="${line#* }"
            case "$cmd" in *"$uri_needle"*) ;; *) continue ;; esac
            case "$cmd" in *"$path_needle"*) ;; *) continue ;; esac
            found=1
            if [ "$force" -eq 1 ]; then
                kill -9 "$pid" 2>/dev/null || true
            else
                kill "$pid" 2>/dev/null || true
            fi
        done < <(ps ax -o pid=,command= 2>/dev/null || true)
    }

    _stop_remote_editor_pass 0
    if [ "$found" -eq 1 ]; then
        sleep 12
    fi
    _stop_remote_editor_pass 1
}

# Cursor Remote-SSH spawns a profile tree: only the main binary carries folder-uri;
# GPU/renderer/network helpers only show --user-data-dir=...ClaudeServerCursorProfile.
_stop_editor_server_profile() {
    local profile_tag="$1"
    local line pid cmd found=0

    _stop_editor_profile_pass() {
        local force="${1:-0}"
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            pid="${line%% *}"
            cmd="${line#* }"
            case "$cmd" in *"$profile_tag"*) ;; *) continue ;; esac
            found=1
            if [ "$force" -eq 1 ]; then
                kill -9 "$pid" 2>/dev/null || true
            else
                kill "$pid" 2>/dev/null || true
            fi
        done < <(ps ax -o pid=,command= 2>/dev/null || true)
    }

    _stop_editor_profile_pass 0
    if [ "$found" -eq 1 ]; then
        sleep 12
    fi
    _stop_editor_profile_pass 1
}

_stop_cursor_server_profile() {
    _stop_editor_server_profile "ClaudeServerCursorProfile"
}

_stop_code_server_profile() {
    _stop_editor_server_profile "ClaudeServerCodeProfile"
}

clear_session_mount() {
    local project_id="$1" editor_cmd="${2:-}" alias_name="${3:-}" remote_path="${4:-}" skip_editor="${5:-1}" reason="${6:-}"
    local reason_part="" down_begin down_ms
    [ -n "$reason" ] && reason_part=" reason=$reason"
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "CLEAR_MOUNT project=$project_id skip_editor=$skip_editor editor=$editor_cmd path=$remote_path$reason_part" 'INFO'
    fi
    if [ "$skip_editor" = "0" ] && [ -n "$editor_cmd" ] && [ -n "$alias_name" ] && [ -n "$remote_path" ]; then
        stop_remote_editor "$editor_cmd" "$alias_name" "$remote_path"
    fi
    clear_tunnel_banner_cache
    if [ -n "$project_id" ]; then
        down_begin=$SECONDS
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "CLEAR_MOUNT: down begin project=$project_id" 'INFO'
        fi
        sshx "timeout 8 $CM down '$project_id' 2>/dev/null" 2>/dev/null || true
        down_ms=$(( (SECONDS - down_begin) * 1000 ))
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "CLEAR_MOUNT: down end ms=$down_ms project=$project_id" 'INFO'
        fi
    fi
    # Win Clear-SessionMount calls Release-CursorProxyOwner before clearing ACTIVE_MOUNT.
    if declare -F release_cursor_proxy_owner >/dev/null 2>&1; then
        release_cursor_proxy_owner || true
    fi
    ACTIVE_MOUNT_ID=""
    push_server_connect_conf --clear
}

laptop_ssh_prepare_dir() {
    mkdir -p "$HOME/.ssh"
    chmod 755 "$HOME" 2>/dev/null || true
    chmod 700 "$HOME/.ssh" 2>/dev/null || true
}

mac_login_realname() {
    # Sharing UI shows Full Name; SSH uses short name (whoami).
    local rn=""
    rn="$(id -F 2>/dev/null | tr -d '\r\n' || true)"
    [ -n "$rn" ] || rn="$(dscl . -read "/Users/$(whoami)" RealName 2>/dev/null | tail -1 | sed 's/^RealName: *//;s/^ //' | tr -d '\r\n' || true)"
    printf '%s' "$rn"
}

remote_login_on() {
    nc -zw1 127.0.0.1 22 2>/dev/null && return 0
    launchctl print system/com.openssh.sshd 2>/dev/null | grep -q 'state = running' && return 0
    launchctl list com.openssh.sshd >/dev/null 2>&1 && return 0
    local out
    out="$(systemsetup -getremotelogin 2>&1)" || true
    printf '%s\n' "$out" | grep -qi 'Remote Login: On\|already On'
}

laptop_ssh_ready() {
    remote_login_on && return 0
    pgrep -x sshd >/dev/null 2>&1
}

read_laptop_admin_password() {
    [ -n "${LAPTOP_ADMIN_PW:-}" ] && return 0
    # Only one interactive prompt per connect (avoid double-ask on retry pass).
    if [ "${_MAC_ADMIN_PW_ASKED:-0}" -eq 1 ]; then
        return 1
    fi
    _MAC_ADMIN_PW_ASKED=1
    printf '    \033[0;33mMac password (one time, 45s timeout, fixes Remote Login):\033[0m\n' >/dev/tty 2>/dev/null || true
    if ! read -rs -t 45 LAPTOP_ADMIN_PW </dev/tty 2>/dev/null; then
        read -rs -t 45 LAPTOP_ADMIN_PW 2>/dev/null || LAPTOP_ADMIN_PW=""
    fi
    echo '' >/dev/tty 2>/dev/null || echo ''
    [ -n "${LAPTOP_ADMIN_PW:-}" ]
}

run_mac_admin_cmd() {
    # Run one privileged Mac command. Password at most once per connect
    # (cached in LAPTOP_ADMIN_PW). Avoids 3x GUI prompts + silent hangs.
    local cmd="$1" osa_pid i rc=1
    [ "$(uname -s)" = "Darwin" ] || return 1
    [ -n "$cmd" ] || return 1

    if [ -n "${LAPTOP_ADMIN_PW:-}" ]; then
        printf '%s\n' "$LAPTOP_ADMIN_PW" | sudo -S -p '' sh -c "$cmd" >/dev/null 2>&1 && return 0
    fi

    # Terminal password first (connect.sh always has /dev/tty).
    if [ -z "${LAPTOP_ADMIN_PW:-}" ]; then
        read_laptop_admin_password || true
    fi
    if [ -n "${LAPTOP_ADMIN_PW:-}" ]; then
        printf '%s\n' "$LAPTOP_ADMIN_PW" | sudo -S -p '' sh -c "$cmd" >/dev/null 2>&1 && return 0
    fi

    # One GUI prompt with hard timeout (cancelled dialogs used to hang forever).
    if [ "${_MAC_ADMIN_GUI_TRIED:-0}" -eq 0 ]; then
        _MAC_ADMIN_GUI_TRIED=1
        osascript -e "do shell script \"${cmd//\"/\\\"}\" with administrator privileges" >/dev/null 2>&1 &
        osa_pid=$!
        i=0
        while kill -0 "$osa_pid" 2>/dev/null; do
            i=$((i + 1))
            if [ "$i" -ge 90 ]; then
                kill "$osa_pid" 2>/dev/null || true
                break
            fi
            sleep 1
        done
        wait "$osa_pid" 2>/dev/null && return 0
    fi
    return 1
}


mac_ssh_access_blocked() {
    local user="${1:-${LAPTOP_USER:-$(whoami)}}"
    id -Gn "$user" 2>/dev/null | tr ' ' '\n' | grep -qx 'com.apple.access_ssh-disabled'
}

mac_ssh_clear_disabled_cmd() {
    local user="${1:-${LAPTOP_USER:-$(whoami)}}"
    # Prefer dseditgroup; dscl fallback for stubborn DirectoryService state.
    printf '%s' "dseditgroup -o edit -d '$user' -t user com.apple.access_ssh-disabled 2>/dev/null || dscl . -delete /Groups/com.apple.access_ssh-disabled GroupMembership '$user' 2>/dev/null || true; dseditgroup -o edit -a '$user' -t user com.apple.access_ssh 2>/dev/null || true"
}

grant_laptop_ssh_access() {
    local user="${LAPTOP_USER:-$(whoami)}"
    # Must REMOVE from com.apple.access_ssh-disabled; adding to access_ssh alone is not enough.
    run_mac_admin_cmd "$(mac_ssh_clear_disabled_cmd "$user")"
}

fix_laptop_ssh_firewall() {
    local sshd="/usr/sbin/sshd"
    [ "$(uname -s)" = "Darwin" ] || return 0
    [ -x "$sshd" ] || sshd="$(command -v sshd 2>/dev/null || true)"
    [ -n "$sshd" ] || return 1
    run_mac_admin_cmd "/usr/libexec/ApplicationFirewall/socketfilterfw --add '$sshd' 2>/dev/null; /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp '$sshd' 2>/dev/null; true"
}

cycle_remote_login() {
    run_mac_admin_cmd "systemsetup -setremotelogin off; sleep 2; systemsetup -setremotelogin on"
    wait_laptop_sshd
}

enable_remote_login() {
    remote_login_on && return 0
    run_mac_admin_cmd "systemsetup -setremotelogin on" || return 1
    wait_laptop_sshd
}

laptop_key_from_prefix() {
    if [ "$(uname -s)" = "Darwin" ]; then
        printf '%s' 'from="127.0.0.1,::1,localhost,::ffff:127.0.0.1"'
    else
        printf '%s' 'from="127.0.0.1,::1"'
    fi
}

install_laptop_server_pubkey() {
    local pub="$1" prefix
    pub="${pub//$'\r'/}"
    [ -n "$pub" ] || return 1
    laptop_ssh_prepare_dir || return 1
    mkdir -p "$HOME/.ssh" || return 1
    touch "$HOME/.ssh/authorized_keys" || return 1
    chmod 700 "$HOME/.ssh" 2>/dev/null || true
    chmod 600 "$HOME/.ssh/authorized_keys" || true
    awk -v pub="$pub" 'index($0, pub) == 0 && NF > 0' "$HOME/.ssh/authorized_keys" > "$HOME/.ssh/authorized_keys.tmp" 2>/dev/null \
        && mv "$HOME/.ssh/authorized_keys.tmp" "$HOME/.ssh/authorized_keys"
    rm -f "$HOME/.ssh/authorized_keys.tmp"
    prefix="$(laptop_key_from_prefix 2>/dev/null || echo from-claude-server)"
    echo "$prefix $pub" >> "$HOME/.ssh/authorized_keys" || return 1
    chmod 600 "$HOME/.ssh/authorized_keys" || true
    xattr -c "$HOME/.ssh/authorized_keys" 2>/dev/null || true
    return 0
}

fetch_laptop_server_pubkey() {
    local pub="${1:-}"
    if [ -n "$pub" ]; then
        printf '%s' "$pub"
        return 0
    fi
    if [ -n "${PUB_B:-}" ]; then
        printf '%s' "$PUB_B"
        return 0
    fi
    pub="$(sshx "cat \$HOME/.ssh/claude_laptop.pub" 2>/dev/null | tr -d '\r' | grep '^ssh-' | head -1)"
    [ -n "$pub" ] || return 1
    printf '%s' "$pub"
}

diagnose_laptop_ssh_failure() {
    # Full diagnostics -> server ~/.claude/logs/ only (laptop temp buffer wiped after sync).
    # so admins can read from the Linux server without asking the user to paste.
    local pub="${1:-}" user frag="" key_tmp="" ak="$HOME/.ssh/authorized_keys"
    local port22=0 rl=0 in_group="?" key_in_ak=0 from_line="?"
    local diag_local diag_remote_dir diag_remote_latest diag_remote_stamp
    local _ssh_rc=1 ssh_out="" _ssh_err _rn _sys _launch _ak_lines _uname_a
    user="${LAPTOP_USER:-$(whoami)}"
    pub="${pub//$'\r'/}"
    frag="$(printf '%s' "$pub" | awk '{print $2}')"
    _rn="$(mac_login_realname 2>/dev/null || true)"
    diag_local="$(mktemp "${TMPDIR:-/tmp}/claude-laptop-ssh-diag.XXXXXX")"
    diag_remote_dir='$HOME/.claude/logs'
    diag_remote_latest='$HOME/.claude/logs/laptop-ssh-diag-latest.txt'

    _dlog() {
        local m="$1"
        printf '%s\n' "$m" >> "$diag_local"
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "LAPTOP_SSH_DIAG: $m" 'WARN'
        fi
        printf '      diag: %s\n' "$m"
    }

    {
        echo "==== Claude laptop SSH diagnose ===="
        echo "ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "connect_version=${CONNECT_VERSION:-${script:ConnectVersion:-unknown}}"
        echo "host=$(hostname 2>/dev/null || true)"
        echo "short_user=$user"
        echo "realname=${_rn}"
        echo "server_user=${REMOTE_USER:-?}"
        echo "server_alias=${ALIAS:-?}"
        echo "server_ip=${SERVER_IP:-?}"
        echo "tunnel_port=${PORT:-?}"
        echo "uname=$(uname -a 2>/dev/null || true)"
        echo "sw_vers=$(sw_vers 2>/dev/null | tr '\n' '|' || true)"
        echo "id=$(id 2>/dev/null || true)"
    } > "$diag_local"

    nc -zw1 127.0.0.1 22 2>/dev/null && port22=1 || port22=0
    remote_login_on && rl=1 || rl=0
    _dlog "port22_open=$port22 remote_login_on=$rl"

    _sys="$(systemsetup -getremotelogin 2>&1 | tr '\n' ' ' | tr -d '\r')"
    _dlog "systemsetup_getremotelogin=${_sys}"

    _launch="$(launchctl print system/com.openssh.sshd 2>&1 | grep -E 'state =|path =|pid =' | head -5 | tr '\n' ';')"
    _dlog "sshd_launchctl=${_launch}"

    if id -Gn "$user" 2>/dev/null | tr ' ' '\n' | grep -qx 'com.apple.access_ssh-disabled'; then
        in_group=DISABLED
        _dlog "access_ssh_disabled=yes FIX=System Settings > Sharing > Remote Login > allow this Mac user (or All users)"
    elif dseditgroup -o check -n . -m "$user" com.apple.access_ssh >/dev/null 2>&1; then
        in_group=yes
    elif dseditgroup -o read com.apple.access_ssh >/dev/null 2>&1; then
        in_group=no
        _dlog "access_ssh_members=$(dseditgroup -o read com.apple.access_ssh 2>/dev/null | grep -i 'GroupMembership|users' | head -3 | tr '\n' ' ')"
    else
        in_group=absent_or_all_users
    fi
    _dlog "access_ssh_group=$in_group"
    _dlog "id_groups=$(id -Gn "$user" 2>/dev/null | tr ' ' ',' || true)"

    _dlog "perms home=$(stat -f '%Lp %Su:%Sg' "$HOME" 2>/dev/null || true) .ssh=$(stat -f '%Lp %Su:%Sg' "$HOME/.ssh" 2>/dev/null || true) ak=$(stat -f '%Lp %Su:%Sg' "$ak" 2>/dev/null || true)"
    _dlog "ls_ssh=$(ls -la "$HOME/.ssh" 2>/dev/null | tr '\n' '|' || true)"

    _ak_lines=0
    [ -f "$ak" ] && _ak_lines="$(grep -cve '^[[:space:]]*$' "$ak" 2>/dev/null || echo 0)"
    _dlog "authorized_keys_nonempty_lines=${_ak_lines}"

    if [ -n "$frag" ] && [ -f "$ak" ] && grep -Fq "$frag" "$ak" 2>/dev/null; then
        key_in_ak=1
        from_line="$(grep -F "$frag" "$ak" | head -1 | awk '{print $1}')"
        _dlog "matching_ak_key_present=yes (pubkey redacted)"
    fi
    _dlog "server_pubkey_in_authorized_keys=$key_in_ak from_prefix=$from_line frag_tail=$(printf '%s' "$frag" | tail -c 12)"

    # sshd config snippets (no secrets)
    if [ -f /etc/ssh/sshd_config ]; then
        _dlog "sshd_config=$(grep -Ei '^(PubkeyAuthentication|PasswordAuthentication|AuthorizedKeysFile|AllowUsers|AllowGroups|PermitRootLogin|#Pubkey|#Password)' /etc/ssh/sshd_config 2>/dev/null | tr '\n' ';' || true)"
    fi

    if [ -z "$frag" ]; then
        _dlog "FAIL reason=no_server_pubkey_fragment"
    elif [ "$key_in_ak" -eq 0 ]; then
        _dlog "FAIL reason=pubkey_not_in_authorized_keys"
    elif [ "$port22" -eq 0 ]; then
        _dlog "FAIL reason=sshd_not_listening_on_22"
    else
        # SECURITY: do not pull ~/.ssh/claude_laptop private key into diagnose logs/tmp.
        # Pubkey + sshd/port/allow-list checks above are enough for diagnosis.
        _dlog "local_ssh_vv=skipped reason=no_private_key_fetch_in_diagnose"
        _dlog "HINT: if auth fails, check Remote Login allow-list, authorized_keys from=, and sshd"
    fi

    _dlog "connect_log_buffer=${CONNECT_LOG_PATH:-unset} (durable local day log + server sync)"
    if declare -F sync_connect_log_to_server >/dev/null 2>&1; then sync_connect_log_to_server || true; fi

    # Push full report to server home (readable by admin / agent on Linux).
    if [ -n "${ALIAS:-}" ] && command -v scp >/dev/null 2>&1; then
        sshx "mkdir -p \$HOME/.claude/logs && chmod 700 \$HOME/.claude \$HOME/.claude/logs 2>/dev/null; true" >/dev/null 2>&1 || true
        if scp -o BatchMode=yes -o ConnectTimeout=15 -q "$diag_local" "${ALIAS}:.claude/logs/laptop-ssh-diag-latest.txt" 2>/dev/null; then
            sshx "cp -f \$HOME/.claude/logs/laptop-ssh-diag-latest.txt \"\$HOME/.claude/logs/laptop-ssh-diag-\$(date +%Y%m%d-%H%M%S).txt\" 2>/dev/null; chmod 600 \$HOME/.claude/logs/laptop-ssh-diag*.txt 2>/dev/null; true" >/dev/null 2>&1 || true
            warn "Diagnostics uploaded to server: ~/.claude/logs/laptop-ssh-diag-latest.txt (user ${REMOTE_USER:-?})"
            _dlog "uploaded_to_server=yes path=~/.claude/logs/laptop-ssh-diag-latest.txt"
        else
            # fallback: base64 via sshx
            if command -v base64 >/dev/null 2>&1; then
                _b64="$(base64 < "$diag_local" | tr -d '\n\r')"
                if sshx "mkdir -p \$HOME/.claude/logs && echo '$_b64' | base64 -d > \$HOME/.claude/logs/laptop-ssh-diag-latest.txt && chmod 600 \$HOME/.claude/logs/laptop-ssh-diag-latest.txt" >/dev/null 2>&1; then
                    warn "Diagnostics uploaded to server: ~/.claude/logs/laptop-ssh-diag-latest.txt"
                    _dlog "uploaded_to_server=yes via=base64"
                else
                    warn "Could not upload diagnostics to server (SSH/scp failed)"
                    _dlog "uploaded_to_server=no"
                fi
            else
                _dlog "uploaded_to_server=no"
            fi
        fi
    fi

    warn "Diagnostics on server only: ~/.claude/logs/laptop-ssh-diag-latest.txt (+ connect-YYYYMMDD.log)"
    rm -f "$diag_local"
    return 0
}

verify_laptop_local_pubkey() {
    local pub="$1" frag="" key_tmp="" rc=1
    pub="${pub//$'\r'/}"
    frag="$(printf '%s' "$pub" | awk '{print $2}')"
    [ -n "$frag" ] || return 1
    grep -Fq "$frag" "$HOME/.ssh/authorized_keys" 2>/dev/null || return 1
    key_tmp="$(mktemp "${TMPDIR:-/tmp}/claude-laptop-key.XXXXXX")"
    umask 077
    if sshx "base64 < \$HOME/.ssh/claude_laptop" 2>/dev/null | tr -d '\r\n' | (base64 -D 2>/dev/null || base64 -d 2>/dev/null) > "$key_tmp"; then
        chmod 600 "$key_tmp"
        ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
            -i "$key_tmp" "${LAPTOP_USER:-$(whoami)}@127.0.0.1" true >/dev/null 2>&1
        rc=$?
    fi
    rm -f "$key_tmp"
    [ "$rc" -eq 0 ]
}

fetch_tunnel_banner() {
    tunnel_fetch_banner
}

# One sshx RTT: TCP open + SSH banner (replaces separate port_open + banner calls).
tunnel_fetch_banner_raw() {
    [ -n "${PORT:-}" ] || return 1
    # Single TCP connection (nc only). Old /dev/tcp+nc used 2 MaxStartups slots.
    sshx "timeout 3 nc -w 2 127.0.0.1 ${PORT} 2>/dev/null | head -1" 2>/dev/null | tr -d '\r\n'
}

tunnel_tcp_open() {
    [ -n "${PORT:-}" ] || return 1
    local out
    out="$(sshx "timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/${PORT} 2>/dev/null' && echo open || echo closed" 2>/dev/null | tr -d '\r\n')"
    echo "$out" | grep -q 'open'
}

tunnel_fetch_banner() {
    local now age_ms banner
    [ -n "${PORT:-}" ] || return 1
    # Positive cache (3s) OR brief negative cache (2s) — never re-probe a dead link every tick.
    if [ "$_TUNNEL_BANNER_CACHE_INVALID" -eq 0 ] && [ "$_TUNNEL_BANNER_CACHE_AT" -gt 0 ]; then
        now="$(date +%s 2>/dev/null || printf '0')"
        age_ms=$(( (now - _TUNNEL_BANNER_CACHE_AT) * 1000 ))
        if [ "$_TUNNEL_BANNER_CACHE_UP" -eq 1 ] && [ "$age_ms" -lt 3000 ]; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_BANNER cache hit age_ms=$age_ms banner=$_TUNNEL_BANNER_CACHE_BANNER" 'TRACE'
            fi
            printf '%s' "$_TUNNEL_BANNER_CACHE_BANNER"
            return 0
        fi
        if [ "${_TUNNEL_BANNER_CACHE_NEGATIVE:-0}" -eq 1 ] && [ "$_TUNNEL_BANNER_CACHE_UP" -eq 0 ] && [ "$age_ms" -lt 2000 ]; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_BANNER negative_cache hit age_ms=$age_ms port=$PORT" 'TRACE'
            fi
            printf ''
            return 0
        fi
    fi
    _TUNNEL_BANNER_CACHE_INVALID=0
    banner="$(tunnel_fetch_banner_raw 2>/dev/null || true)"
    case "$banner" in
        *MaxStartups*)
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_BANNER soft_fail port=$PORT reason=maxstartups" 'WARN'
            fi
            banner=""
            ;;
    esac
    if [ -n "$banner" ] && tunnel_banner_is_transport_noise "$banner"; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "TUNNEL_BANNER transport_fail port=$PORT detail=$banner" 'DEBUG'
        fi
        banner=""
        _TUNNEL_BANNER_CACHE_AT="$(date +%s 2>/dev/null || printf '0')"
        _TUNNEL_BANNER_CACHE_BANNER=""
        _TUNNEL_BANNER_CACHE_UP=0
        _TUNNEL_BANNER_CACHE_NEGATIVE=1
        printf ''
        return 0
    fi
    if [ -n "$banner" ] && tunnel_banner_is_this_laptop "$banner"; then
        _TUNNEL_BANNER_CACHE_AT="$(date +%s 2>/dev/null || printf '0')"
        _TUNNEL_BANNER_CACHE_BANNER="$banner"
        _TUNNEL_BANNER_CACHE_UP=1
        _TUNNEL_BANNER_CACHE_NEGATIVE=0
    else
        # Do NOT negative-cache ordinary empty/miss (poisoned DROP1 recovery).
        # Transport failures already set _TUNNEL_BANNER_CACHE_NEGATIVE above.
        _TUNNEL_BANNER_CACHE_AT=0
        _TUNNEL_BANNER_CACHE_BANNER=""
        _TUNNEL_BANNER_CACHE_UP=0
        _TUNNEL_BANNER_CACHE_NEGATIVE=0
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "TUNNEL_BANNER miss port=$PORT banner=$banner" 'DEBUG'
        fi
    fi
    printf '%s' "$banner"
}

tunnel_banner_is_this_laptop() {
    local banner="${1:-}" os="${GIT_MODE_LAPTOP_OS:-mac}"
    [ -n "$banner" ] || banner="$(tunnel_fetch_banner)"
    [ -n "$banner" ] || return 1
    echo "$banner" | grep -q '^SSH-2.0-' || return 1
    case "$os" in
        mac|darwin)
            # macOS Remote Login advertises a normal OpenSSH banner. Reject
            # server/Linux and Windows banners so a foreign forward is not reused.
            echo "$banner" | grep -qi 'OpenSSH' || return 1
            echo "$banner" | grep -qiE 'OpenSSH_for_Windows|Ubuntu|Debian|el[0-9]+' && return 1
            ;;
        win|windows)
            echo "$banner" | grep -qi 'OpenSSH_for_Windows' || return 1
            ;;
    esac
    return 0
}

tunnel_port_open() {
    [ -n "$(tunnel_fetch_banner 2>/dev/null || true)" ]
}

tunnel_up() {
    local banner age_ms now attempt
    if [ "$_TUNNEL_BANNER_CACHE_INVALID" -eq 0 ] && [ "$_TUNNEL_BANNER_CACHE_AT" -gt 0 ] && [ "$_TUNNEL_BANNER_CACHE_UP" -eq 1 ]; then
        now="$(date +%s 2>/dev/null || printf '0')"
        age_ms=$(( (now - _TUNNEL_BANNER_CACHE_AT) * 1000 ))
        if [ "$age_ms" -lt 3000 ]; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_UP port=$PORT up=1 cache=1" 'TRACE'
            fi
            return 0
        fi
    fi
    for attempt in 1 2 3; do
        [ "$attempt" -gt 1 ] && sleep 0.25
        banner="$(tunnel_fetch_banner 2>/dev/null || true)"
        if [ -n "$banner" ] && tunnel_banner_is_this_laptop "$banner"; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_UP port=$PORT up=1 attempt=$attempt" 'TRACE'
            fi
            return 0
        fi
    done
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "TUNNEL_UP port=$PORT up=0" 'TRACE'
    fi
    return 1
}


_tunnel_session_diag_suffix() {
    local proj=""
    if [ -n "${ACTIVE_PROJECT_ID:-}" ]; then
        proj=" project=${ACTIVE_PROJECT_ID}"
    fi
    printf '%s soft_fail=%s sync_fail=%s' "$proj" "${_TUNNEL_SOFT_FAIL_COUNT:-0}" "${_TUNNEL_SYNC_FAIL_COUNT:-0}"
}

log_tunnel_drop() {
    local reason="${1:-auto_reconnect}"
    local project_id="${2:-${ACTIVE_PROJECT_ID:-?}}"
    local tunnel_sync_ok="${3:-false}"
    local editor_opened="${4:-${_editor_opened:-0}}"
    local editor_seen="${5:-${_editor_seen_open:-0}}"
    local gen="${6:-${RECOVERY_GENERATION:-0}}"
    local tcp_open=0 tunnel_up=0
    local drop_cause="${LAST_TUNNEL_SYNC_DROP_REASON:-}"
    local cause_part="" bg_part=""
    if declare -F tunnel_tcp_open >/dev/null 2>&1 && tunnel_tcp_open; then tcp_open=1; fi
    if declare -F tunnel_up >/dev/null 2>&1 && tunnel_up; then tunnel_up=1; fi
    [ -n "$drop_cause" ] && [ "$reason" = "auto_reconnect" ] && cause_part=" drop_cause=$drop_cause"
    [ -n "${bg_pid:-}" ] && bg_part=" bg_pid=$bg_pid"
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "TUNNEL_DROP reason=$reason soft_fail=${_TUNNEL_SOFT_FAIL_COUNT:-0} sync_fail=${_TUNNEL_SYNC_FAIL_COUNT:-0} tcp_open=$tcp_open tunnel_up=$tunnel_up tunnel_sync_ok=$tunnel_sync_ok project=$project_id editor_opened=$editor_opened editor_seen=$editor_seen gen=$gen$cause_part$bg_part port=${PORT:-?}" 'INFO'
    fi
}

# When bg tunnel process is alive, probe forward every _TUNNEL_FORWARD_PROBE_INTERVAL_SEC
# (45s; zombie forward detection). A healthy banner cache may defer one probe in a row.
sync_session_tunnel_forward() {
    local bg_pid="${1:-}" now probe_up
    local fail_threshold="${TUNNEL_FORWARD_FAIL_THRESHOLD:-3}"
    [ -n "$bg_pid" ] || return 1
    case "$fail_threshold" in ''|*[!0-9]*) fail_threshold=3 ;; esac
    [ "$fail_threshold" -ge 1 ] 2>/dev/null || fail_threshold=3

    # Owner/service coupling on every Sync tick (D5): zombie owners release without Ensure churn.
    if declare -F update_cursor_proxy_owner_service_health >/dev/null 2>&1; then
        update_cursor_proxy_owner_service_health || true
    fi

    # A missing local ssh PID is not definitive: the reverse forward can still
    # be healthy after process re-parenting. Trust TCP/banner evidence first.
    if ! kill -0 "$bg_pid" 2>/dev/null; then
        if tunnel_up || { declare -F tunnel_tcp_open >/dev/null 2>&1 && tunnel_tcp_open; }; then
            _TUNNEL_SYNC_FAIL_COUNT=0
            _TUNNEL_SOFT_FAIL_COUNT=$(( ${_TUNNEL_SOFT_FAIL_COUNT:-0} + 1 ))
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_SYNC soft_fail count=$_TUNNEL_SOFT_FAIL_COUNT/4 pid=$bg_pid port=$PORT reason=no_ssh_proc_tcp_open$(_tunnel_session_diag_suffix)" 'WARN'
            fi
            if [ "$_TUNNEL_SOFT_FAIL_COUNT" -lt 4 ]; then
                return 0
            fi
            # TCP/banner still healthy: lost local ssh PID only. Keep session up
            # (do not force "Connection dropped" recovery). First-exhaust arm has
            # no release_stale (S5). Age gate via _no_proc_should_keep (D7).
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_SYNC soft_fail_exhausted_keep_alive port=$PORT reason=no_ssh_proc_tcp_open pid=$bg_pid$(_tunnel_session_diag_suffix)" 'WARN'
            fi
            _TUNNEL_SOFT_FAIL_COUNT=0
            _no_proc_should_keep && return 0
            # Age gate drop: >=120s continuous no_proc + (NOT auth OR NOT banner).
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_SYNC soft_fail_exhausted_zombie_drop port=$PORT reason=no_ssh_proc_tcp_open pid=$bg_pid$(_tunnel_session_diag_suffix)" 'WARN'
                LAST_TUNNEL_SYNC_DROP_REASON=soft_fail_exhausted_zombie_drop
                log_tunnel_drop soft_fail_exhausted_zombie_drop "${ACTIVE_PROJECT_ID:-?}" false "${_editor_opened:-0}" "${_editor_seen_open:-0}" "${RECOVERY_GENERATION:-0}"
            fi
            release_stale_tunnel_port || true
            _NO_PROC_KEEPALIVE_SINCE=0
            if declare -F update_cursor_proxy_owner_service_health >/dev/null 2>&1; then
                update_cursor_proxy_owner_service_health || true
            fi
            return 1
        fi
        _TUNNEL_SYNC_FAIL_COUNT=$(( _TUNNEL_SYNC_FAIL_COUNT + 1 ))
        if [ "$_TUNNEL_SYNC_FAIL_COUNT" -lt "$fail_threshold" ]; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_SYNC soft_fail pid=$bg_pid port=$PORT reason=no_ssh_proc count=$_TUNNEL_SYNC_FAIL_COUNT threshold=$fail_threshold$(_tunnel_session_diag_suffix)" 'WARN'
            fi
            return 0
        fi
        if declare -F connect_log >/dev/null 2>&1; then
            LAST_TUNNEL_SYNC_DROP_REASON=no_ssh_proc_tunnel_down
            log_tunnel_drop no_ssh_proc_tunnel_down "${ACTIVE_PROJECT_ID:-?}" false "${_editor_opened:-0}" "${_editor_seen_open:-0}" "${RECOVERY_GENERATION:-0}"
        fi
        _TUNNEL_SYNC_FAIL_COUNT=0
        return 1
    fi

    # Healthy local ssh PID: clear no_proc keep-alive age tracking.
    _NO_PROC_KEEPALIVE_SINCE=0

    now="$(date +%s 2>/dev/null || printf '0')"
    if [ "$_LAST_FORWARD_PROBE_AT" -eq 0 ]; then
        _LAST_FORWARD_PROBE_AT="$now"
        return 0
    fi
    if [ $(( now - _LAST_FORWARD_PROBE_AT )) -lt "$_TUNNEL_FORWARD_PROBE_INTERVAL_SEC" ]; then
        return 0
    fi
    _LAST_FORWARD_PROBE_AT="$now"
    # Keepalive defer: when the tunnel is already healthy (no soft-fails, banner
    # cache still positive) and we have not deferred the previous probe, skip
    # this active check once to cut needless SSH round-trips. A soft-fail
    # streak or an already-used defer must fall through to a real probe.
    if [ "${_TUNNEL_SOFT_FAIL_COUNT:-0}" -eq 0 ] && [ "${_TUNNEL_BANNER_DEFER_COUNT:-0}" -eq 0 ] \
        && { [ "${_TUNNEL_BANNER_CACHE_UP:-0}" -eq 1 ] || [ -n "${_TUNNEL_BANNER_CACHE_BANNER:-}" ]; }; then
        _TUNNEL_BANNER_DEFER_COUNT=$(( ${_TUNNEL_BANNER_DEFER_COUNT:-0} + 1 ))
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "TUNNEL_SYNC probe_deferred pid=$bg_pid port=$PORT reason=keepalive_banner_fresh$(_tunnel_session_diag_suffix)" 'TRACE'
        fi
        return 0
    fi
    _TUNNEL_BANNER_DEFER_COUNT=0
    clear_tunnel_banner_cache
    if tunnel_up; then
        probe_up=1
        _TUNNEL_SYNC_FAIL_COUNT=0
        _TUNNEL_SOFT_FAIL_COUNT=0
        _NO_PROC_KEEPALIVE_SINCE=0
    else
        probe_up=0
    fi
    if [ "$probe_up" -eq 0 ]; then
        if declare -F tunnel_tcp_open >/dev/null 2>&1 && tunnel_tcp_open; then
            _TUNNEL_SOFT_FAIL_COUNT=$(( ${_TUNNEL_SOFT_FAIL_COUNT:-0} + 1 ))
            _TUNNEL_SYNC_FAIL_COUNT=0
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_SYNC soft_fail count=$_TUNNEL_SOFT_FAIL_COUNT/4 pid=$bg_pid port=$PORT reason=banner_miss_tcp_open$(_tunnel_session_diag_suffix)" 'WARN'
            fi
            if [ "$_TUNNEL_SOFT_FAIL_COUNT" -ge 4 ]; then
                if declare -F connect_log >/dev/null 2>&1; then
                    LAST_TUNNEL_SYNC_DROP_REASON=banner_miss_tcp_open_budget
                    log_tunnel_drop banner_miss_tcp_open_budget "${ACTIVE_PROJECT_ID:-?}" false "${_editor_opened:-0}" "${_editor_seen_open:-0}" "${RECOVERY_GENERATION:-0}"
                fi
                release_stale_tunnel_port || true
                _TUNNEL_SOFT_FAIL_COUNT=0
                return 1
            fi
            return 0
        else
            _TUNNEL_SYNC_FAIL_COUNT=$(( _TUNNEL_SYNC_FAIL_COUNT + 1 ))
            if [ "$_TUNNEL_SYNC_FAIL_COUNT" -lt "$fail_threshold" ]; then
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "TUNNEL_SYNC soft_fail pid=$bg_pid port=$PORT reason=forward_probe_failed count=$_TUNNEL_SYNC_FAIL_COUNT threshold=$fail_threshold$(_tunnel_session_diag_suffix)" 'WARN'
                fi
                return 0
            fi
            if declare -F connect_log >/dev/null 2>&1; then
                LAST_TUNNEL_SYNC_DROP_REASON=bg_alive_forward_dead
                log_tunnel_drop bg_alive_forward_dead "${ACTIVE_PROJECT_ID:-?}" false "${_editor_opened:-0}" "${_editor_seen_open:-0}" "${RECOVERY_GENERATION:-0}"
            fi
            _TUNNEL_SYNC_FAIL_COUNT=0
            release_stale_tunnel_port || true
            return 1
        fi
    fi
    if declare -F connect_log >/dev/null 2>&1; then
        _now=$(date +%s)
        if [ -z "${_LAST_TUNNEL_TRACE:-}" ] || [ $((_now - _LAST_TUNNEL_TRACE)) -ge 30 ]; then
            connect_log "TUNNEL_SYNC: bg_alive pid=$bg_pid port=$PORT" 'TRACE'
            _LAST_TUNNEL_TRACE=$_now
        fi
    fi
    return 0
}

wait_for_tunnel_up() {
    local pid="${1:-}" i sleep_s local_r_not_owned=0 local_pids="" p owned=0
    local max_attempts="${TUNNEL_WAIT_MAX_ATTEMPTS:-6}"
    for i in $(seq 1 "$max_attempts"); do
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_WAIT fail=1 attempt=$i reason=ssh_died pid=$pid" 'WARN'
            fi
            printf '    Tunnel check... SSH process died\n'
            release_stale_tunnel_port || true
            return 1
        fi
        if tunnel_up; then
            # Gate A: banner/TCP alone is not enough — spawn pid must own local -R.
            # Empty local PID list is failure (fail-closed), not success.
            owned=0
            local_pids=""
            if [ -n "$pid" ] && [ -n "${PORT:-}" ]; then
                local_pids="$(get_local_tunnel_ssh_pids "$PORT" 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
                for p in $(get_local_tunnel_ssh_pids "$PORT" 2>/dev/null || true); do
                    if [ "$p" = "$pid" ]; then owned=1; break; fi
                done
            fi
            if [ "$owned" -eq 1 ]; then
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "TUNNEL_WAIT ok=1 attempt=$i port=$PORT pid=$pid" 'DEBUG'
                fi
                return 0
            fi
            local_r_not_owned=1
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_WAIT ok=0 attempt=$i reason=local_r_not_owned port=$PORT pid=$pid local_pids=$local_pids" 'WARN'
            fi
        else
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_WAIT ok=0 attempt=$i port=$PORT" 'TRACE'
            fi
        fi
        if [ "$i" -ge "$max_attempts" ]; then
            break
        fi
        sleep_s="$(awk "BEGIN { s=0.25+($i-1)*0.2; print (s>1.5?1.5:s) }")"
        sleep "$sleep_s"
    done
    if declare -F connect_log >/dev/null 2>&1; then
        if [ "$local_r_not_owned" -eq 1 ]; then
            connect_log "TUNNEL_WAIT fail=1 reason=local_r_not_owned port=$PORT pid=$pid" 'WARN'
        else
            connect_log "TUNNEL_WAIT fail=1 reason=timeout port=$PORT" 'WARN'
        fi
    fi
    release_stale_tunnel_port || true
    return 1
}

poll_tunnel_with_progress() {
    local pid="${1:-}" i sleep_s up="" local_r_not_owned=0 local_pids="" p owned=0
    local max_attempts="${TUNNEL_WAIT_MAX_ATTEMPTS:-6}"
    for i in $(seq 1 "$max_attempts"); do
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_WAIT fail=1 attempt=$i reason=ssh_died pid=$pid" 'WARN'
            fi
            printf '    Tunnel check... SSH process died\n'
            release_stale_tunnel_port || true
            return 1
        fi
        if tunnel_up; then
            # Gate A: banner/TCP alone is not enough — spawn pid must own local -R.
            # Empty local PID list is failure (fail-closed), not success.
            owned=0
            local_pids=""
            if [ -n "$pid" ] && [ -n "${PORT:-}" ]; then
                local_pids="$(get_local_tunnel_ssh_pids "$PORT" 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
                for p in $(get_local_tunnel_ssh_pids "$PORT" 2>/dev/null || true); do
                    if [ "$p" = "$pid" ]; then owned=1; break; fi
                done
            fi
            if [ "$owned" -eq 1 ]; then
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "TUNNEL_WAIT ok=1 attempt=$i port=$PORT pid=$pid" 'DEBUG'
                fi
                if [ "$i" -eq 1 ]; then
                    printf '    Tunnel check... port %d is open\n' "$PORT"
                else
                    printf '    Tunnel check %d/%d... port %d is open\n' "$i" "$max_attempts" "$PORT"
                fi
                return 0
            fi
            local_r_not_owned=1
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_WAIT ok=0 attempt=$i reason=local_r_not_owned port=$PORT pid=$pid local_pids=$local_pids" 'WARN'
            fi
            printf '    Tunnel check %d/%d... port %d open but not owned by this tunnel\n' "$i" "$max_attempts" "$PORT"
        else
            printf '    Tunnel check %d/%d... port %d not open yet\n' "$i" "$max_attempts" "$PORT"
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_WAIT ok=0 attempt=$i port=$PORT" 'TRACE'
            fi
        fi
        if [ "$i" -ge "$max_attempts" ]; then
            break
        fi
        sleep_s="$(awk "BEGIN { s=0.25+($i-1)*0.2; print (s>1.5?1.5:s) }")"
        sleep "$sleep_s"
    done
    if declare -F connect_log >/dev/null 2>&1; then
        if [ "$local_r_not_owned" -eq 1 ]; then
            connect_log "TUNNEL_WAIT fail=1 reason=local_r_not_owned port=$PORT pid=$pid" 'WARN'
        else
            connect_log "TUNNEL_WAIT fail=1 reason=timeout port=$PORT" 'WARN'
        fi
    fi
    release_stale_tunnel_port || true
    return 1
}

find_claude_mount_src() {
    local script_dir="$1" _mount_src="" _mount_dir=""
    if [ -f "$script_dir/claude-mount.sh" ]; then
        printf '%s' "$script_dir/claude-mount.sh"
        return 0
    fi
    _mount_dir="$(resolve_server_script_dir "$script_dir" 2>/dev/null || true)"
    if [ -n "$_mount_dir" ] && [ -f "$_mount_dir/claude-mount.sh" ]; then
        printf '%s' "$_mount_dir/claude-mount.sh"
        return 0
    fi
    return 1
}

local_file_sha256() {
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
}

remote_claude_mount_sha256() {
    sshx "sha256sum \$HOME/.local/bin/claude-mount 2>/dev/null | awk '{print \$1}'" 2>/dev/null | tr -d '\r\n'
}

push_claude_mount_if_changed() {
    local src="$1" local_h="" remote_h=""
    [ -f "$src" ] || return 0
    local_h="$(local_file_sha256 "$src")"
    if [ -n "$local_h" ]; then
        remote_h="$(remote_claude_mount_sha256)"
        [ "$local_h" = "$remote_h" ] && return 0
    fi
    # claude-mount is live-executed (claude-watchdog polls it every 30s server-side) -
    # land in a .new sibling and mv atomically so a concurrent exec never tears it.
    scp -o BatchMode=yes -o ConnectTimeout=20 -q "$src" "$ALIAS:~/.local/bin/claude-mount.new" 2>/dev/null \
        && sshx "chmod +x \$HOME/.local/bin/claude-mount.new && mv -f \$HOME/.local/bin/claude-mount.new \$HOME/.local/bin/claude-mount" 2>/dev/null || true
}

prepare_server_session_parallel() {
    local go_id="$1" mount_src="${2:-}" pp="" sp=""
    ACTIVE_MOUNT_ID="$go_id"
    push_server_connect_conf &
    pp=$!
    if [ -n "$mount_src" ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "SCP: begin project=$go_id" 'DEBUG'
        fi
        push_claude_mount_if_changed "$mount_src" &
        sp=$!
    fi
    wait_pid_timeout "$pp" push_conf 30 || true
    if [ -n "$sp" ]; then
        wait_pid_timeout "$sp" claude_mount 30 || true
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "SCP: end project=$go_id" 'DEBUG'
        fi
    fi
}

project_mount_healthy() {
    local id="$1"
    [ -n "$id" ] || return 1
    sshx "$CM check '$id' 2>/dev/null" 2>/dev/null | grep -q '^ok$'
}

recover_mounts_if_needed() {
    local id="$1" fresh_tunnel="${2:-0}" recover_ec=0 recover_begin recover_ms
    if [ "$fresh_tunnel" = "0" ] && project_mount_healthy "$id"; then
        if [ "$(get_git_mode)" = "off" ]; then
            sshx "timeout 15 $CM recover-if-needed '$id' 2>/dev/null" 2>/dev/null || true
        fi
        return 0
    fi
    printf '    \033[0;90mRecovering stale mounts...\033[0m\n'
    recover_begin=$SECONDS
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "RECOVER: begin project=$id fresh_tunnel=$fresh_tunnel" 'INFO'
    fi
    clear_tunnel_banner_cache
    # Single remote command (Win parity) - no nested sshx on the server.
    if ! sshx "timeout 30 $CM recover-one '$id' 2>/dev/null || timeout 30 $CM recover-if-needed '$id' 2>/dev/null || timeout 30 $CM recover 2>/dev/null || true"; then
        recover_ec=$?
    fi
    recover_ms=$(( (SECONDS - recover_begin) * 1000 ))
    if declare -F connect_log >/dev/null 2>&1; then
        if [ "$recover_ec" -ne 0 ]; then
            connect_log "RECOVER: fail project=$id exit=$recover_ec ms=$recover_ms" 'WARN'
        else
            connect_log "RECOVER: end project=$id ms=$recover_ms" 'INFO'
        fi
    fi
    if [ "$recover_ec" -ne 0 ]; then
        printf '    \033[0;33mRecover finished with errors (exit %s)\033[0m\n' "$recover_ec"
    else
        printf '    \033[0;90mRecover done\033[0m\n'
    fi
}

# Reset session state after tunnel drop (manual R or auto recovery).
begin_connect_recovery() {
    local trigger="$1" project_id="$2" editor_was_open="${3:-0}"
    RECOVERY_GENERATION="${RECOVERY_GENERATION:-0}"
    RECOVERY_GENERATION=$(( RECOVERY_GENERATION + 1 ))
    POST_TUNNEL_RECOVERY=1
    export CURSOR_AUTH_FORCE=1
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "RECOVERY_BEGIN trigger=$trigger project=$project_id editor_opened=$editor_was_open gen=$RECOVERY_GENERATION"
    fi
    if [ "$trigger" = "auto" ] && declare -F invoke_connect_silent_update_check >/dev/null 2>&1; then
        invoke_connect_silent_update_check || true
    fi
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log 'RECOVERY_STATE_RESET editor_opened=0 force_auth=1 post_recovery=1'
    fi
}

complete_post_tunnel_recovery() {
    local mount_ok="${1:-0}" auth_detail="${2:-}"
    [ "${POST_TUNNEL_RECOVERY:-0}" = "1" ] || return 0
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "RECOVERY_END mount_ok=$mount_ok gen=${RECOVERY_GENERATION:-0} auth=$auth_detail"
    fi
    POST_TUNNEL_RECOVERY=0
}

cursor_auth_needs_refresh() {
    local db="${1:-}"
    [ -n "$db" ] || return 1
    [ -f "$db" ] || return 0
    cursor_sqlite3_available || return 0
    cursor_db_value_length "$db" 'storage.serviceMachineId' || return 0
    return 1
}

invoke_mount_project() {
    local id="$1" script_dir="${2:-${CONNECT_SCRIPT_DIR:-}}" mount_out="" ec=0 src="" mode=""
    mode="$(get_git_mode)"
    if project_mount_healthy "$id" && [ "$mode" != "off" ]; then
        printf 'already mounted (check ok)'
        return 0
    fi
    mount_out="$(sshx "CLAUDE_TRUSTED_TUNNEL=1 $CM up '$id' 2>&1")"
    ec=$?
    if test_mount_success "$mount_out" "$ec"; then
        printf '%s' "$mount_out"
        return 0
    fi
    if echo "$mount_out" | grep -qE 'unbound variable|syntax error near unexpected'; then
        printf '      -> server mount script outdated, pushing update...\n' >&2
        if [ -n "$script_dir" ]; then
            src="$(find_claude_mount_src "$script_dir" 2>/dev/null || true)"
            [ -n "$src" ] && push_claude_mount_if_changed "$src"
            mount_out="$(sshx "CLAUDE_TRUSTED_TUNNEL=1 $CM up '$id' 2>&1")"
            ec=$?
            if test_mount_success "$mount_out" "$ec"; then
                printf '%s' "$mount_out"
                return 0
            fi
        fi
    fi
    printf '%s' "$mount_out"
    return "$ec"
}

# C6 / E5: best-effort post-open health — timed ls + bound -p + shared-p.
# Never treat skip_remount_healthy / started_in_background alone as healthy.
invoke_connect_mount_verify() {
    local id="${1:-}" mount_out="${2:-}" out="" line="" shared_n=0 bound_p=""
    id="$(printf '%s' "$id" | tr "'" '-')"
    [ -n "$id" ] || return 0
    out="$(sshx "set +e
ID='$id'
LP=\"\$HOME/mounts/\$ID\"
ls_ok=0
bound=''
conf=''
shared=0
if [ -d \"\$LP\" ]; then
  if timeout 3 ls -la \"\$LP\" >/dev/null 2>&1; then ls_ok=1; fi
fi
for p in /proc/[0-9]*; do
  [ -r \"\$p/cmdline\" ] || continue
  cmd=\$(tr '\\0' ' ' < \"\$p/cmdline\" 2>/dev/null)
  case \"\$cmd\" in
    *sshfs*)
      case \"\$cmd\" in
        *\"\$LP\"*)
          bound=\$(printf '%s' \"\$cmd\" | sed -n 's/.* -p \\([0-9][0-9]*\\).*/\\1/p; t; s/.* -p\\([0-9][0-9]*\\).*/\\1/p')
          break
          ;;
      esac
      ;;
  esac
done
conf=\$(grep -E '^TUNNEL_PORT=' \"\$HOME/.claude-connect.conf\" 2>/dev/null | tail -1 | cut -d= -f2- | tr -dc '0-9')
if [ \"\$ls_ok\" = \"1\" ] && [ -z \"\$bound\" ]; then
  if grep -F \" \$LP \" /proc/mounts >/dev/null 2>&1 || grep -F \" \$LP\" /proc/mounts >/dev/null 2>&1; then
    :
  else
    ls_ok=0
    printf 'MOUNT_VERIFY pending_no_sshfs project=%s\\n' \"\$ID\"
  fi
fi
if [ -n \"\$bound\" ]; then
  shared=\$(ps -eo args 2>/dev/null | grep -F -- \"-p \$bound\" | grep -c '[s]shfs' || true)
fi
printf 'MOUNT_VERIFY ls_ok=%s bound_p=%s conf_p=%s shared_p=%s project=%s\\n' \"\$ls_ok\" \"\$bound\" \"\$conf\" \"\$shared\" \"\$ID\"
if [ \"\$shared\" -ge 2 ] 2>/dev/null; then
  printf 'MOUNT_SHARED_P projects_on_port=%s port=%s\\n' \"\$shared\" \"\$bound\"
fi
" 2>/dev/null || true)"
    if [ -z "$out" ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "MOUNT_VERIFY empty project=${id} mount_out=$(printf '%s' "$mount_out" | tr '\n' ' ')" 'WARN'
        fi
        return 0
    fi
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in
            *MOUNT_VERIFY*|*MOUNT_SHARED_P*|*DUAL_CONNECT*)
                if declare -F connect_log >/dev/null 2>&1; then
                    case "$line" in
                        *ls_ok=0*|*pending_no_sshfs*) connect_log "$line" 'WARN' ;;
                        *) connect_log "$line" 'INFO' ;;
                    esac
                fi
                ;;
        esac
    done <<EOF
$out
EOF
    shared_n="$(printf '%s' "$out" | sed -n 's/.*shared_p=\([0-9][0-9]*\).*/\1/p' | head -1)"
    bound_p="$(printf '%s' "$out" | sed -n 's/.*bound_p=\([0-9][0-9]*\).*/\1/p' | head -1)"
    if [ "${shared_n:-0}" -ge 2 ] 2>/dev/null; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "DUAL_CONNECT shared_p=${shared_n} port=${bound_p:-?} project=${id}" 'INFO'
        fi
    fi
    if echo "$mount_out" | grep -qE 'skip_remount_healthy|started_in_background' \
        && ! echo "$out" | grep -q 'ls_ok=1'; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "MOUNT_VERIFY not_healthy_from_skip_alone project=${id}" 'WARN'
        fi
    fi
    return 0
}

ensure_laptop_reverse_ssh_cached() {
    local pub="${1:-}" rc=0
    if [ "${LAPTOP_SSH_VERIFIED:-0}" = "1" ] && verify_laptop_reverse_ssh; then
        return 0
    fi
    ensure_laptop_reverse_ssh "$pub" || rc=$?
    [ "$rc" -eq 0 ] && LAPTOP_SSH_VERIFIED=1
    return "$rc"
}

tunnel_port_tcp_open() {
    local port="${1:-${PORT:-}}"
    local out=""
    [ -n "$port" ] || return 1
    out="$(sshx "timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/${port} 2>/dev/null' && echo open || echo closed" 2>/dev/null | tr -d '\r\n')"
    [ "$out" = open ]
}


XRAY_SERVER_SOCKS_PORT=10808
XRAY_SERVER_HTTP_PORT=10809
CURSOR_SOCKS_FRONT_PORT=18999
CURSOR_HTTP_FRONT_PORT=18998
export CURSOR_SOCKS_FRONT_PORT CURSOR_HTTP_FRONT_PORT
SOCKS_PROXY_PORT=""
HTTP_PROXY_PORT=""   # session var; empty = no proxy
CURSOR_PROXY_OWNER=""
TUNNEL_WAIT_FAIL_STREAK=0
TUNNEL_WAIT_BACKOFF_SEC=2

cursor_proxy_owner_path() {
    local dir="$HOME/.config/claude-connect"
    mkdir -p "$dir" 2>/dev/null || true
    printf '%s/cursor-proxy-owner.json' "$dir"
}

_process_alive() {
    # kill -0 is true for zombies; filter state Z (Claim/CanClaim must adopt).
    local pid="${1:-0}" state
    [ "$pid" -gt 0 ] 2>/dev/null || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    state="$(ps -o state= -p "$pid" 2>/dev/null | tr -d '[:space:]')"
    case "$state" in
        Z*) return 1 ;;
    esac
    return 0
}

get_cursor_proxy_owner_info() {
    local path pid
    path="$(cursor_proxy_owner_path)"
    [ -f "$path" ] || return 1
    python3 - "$path" <<'PY' 2>/dev/null || return 1
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        json.load(f)
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
}

test_is_cursor_proxy_owner() {
    local path pid_own
    path="$(cursor_proxy_owner_path)"
    [ -f "$path" ] || return 1
    pid_own="$(python3 - "$path" <<'PY' 2>/dev/null || exit 1
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)
print(int(d.get("pid", 0)))
PY
)" || return 1
    _process_alive "$pid_own" || return 1
    [ "$pid_own" -eq "$$" ]
}

can_claim_cursor_proxy_owner() {
    # Read-only mirror of claim success (no owner.json write). Return 0 = CanBindL.
    local path pid_own cmd
    path="$(cursor_proxy_owner_path)"
    [ -f "$path" ] || return 0
    pid_own="$(python3 - "$path" <<'PY' 2>/dev/null || printf '0'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)
print(int(d.get("pid", 0)))
PY
)"
    [ -n "${pid_own:-}" ] && [ "${pid_own}" -gt 0 ] 2>/dev/null || return 0
    [ "$pid_own" = "$$" ] && return 0
    if ! _process_alive "$pid_own"; then return 0; fi
    cmd="$(ps -p "$pid_own" -o args= 2>/dev/null || true)"
    if [ -n "$cmd" ]; then
        case "$cmd" in
            *connect.sh*|*connect-boot*) return 1 ;;
            *) return 0 ;; # non-Connect PID reuse -> claim would adopt
        esac
    fi
    # Unreadable cmdline: treat as foreign-live (safe: skip kill)
    return 1
}

proxy_reseed_should_kill() {
    # ReseedEffective = ReseedRaw AND CanClaim. Return 0 => kill/reseed; non-zero => keep -R.
    local tunnel_pid="${1:-}"
    [ -n "$tunnel_pid" ] || return 1
    tunnel_needs_proxy_reseed "$tunnel_pid" || return 1
    if ! can_claim_cursor_proxy_owner; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "ENSURE_TUNNEL reseed_skip reason=foreign_owner_cannot_bind pid=$tunnel_pid port=${PORT:-}" 'INFO'
        fi
        return 1
    fi
    return 0
}

claim_cursor_proxy_owner() {
    local force="${1:-0}" path info pid_own slot socks http started cmd
    path="$(cursor_proxy_owner_path)"
    if [ -f "$path" ] && [ "$force" != "1" ]; then
        pid_own="$(python3 - "$path" <<'PY' 2>/dev/null || printf '0'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    d = json.load(f)
print(int(d.get("pid", 0)))
PY
)"
        if [ "${pid_own:-0}" -eq "$$" ]; then
            CURSOR_PROXY_OWNER=1
            export CURSOR_PROXY_OWNER
            return 0
        fi
        if _process_alive "$pid_own"; then
            cmd="$(ps -p "$pid_own" -o args= 2>/dev/null || true)"
            if [ -z "$cmd" ]; then
                CURSOR_PROXY_OWNER=0
                export CURSOR_PROXY_OWNER
                declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROXY_OWNER: skip live_owner pid=$pid_own self=$$" 'INFO'
                return 1
            fi
            case "$cmd" in
                *connect.sh*|*connect-boot*)
                    CURSOR_PROXY_OWNER=0
                    export CURSOR_PROXY_OWNER
                    declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROXY_OWNER: skip live_owner pid=$pid_own self=$$" 'INFO'
                    return 1
                    ;;
                *)
                    declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROXY_OWNER: adopt stale_non_connect pid=$pid_own self=$$" 'INFO'
                    ;;
            esac
        else
            declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROXY_OWNER: adopt stale pid=$pid_own self=$$" 'INFO'
        fi
    fi
    slot="${TUNNEL_SLOT:--1}"
    socks="$(socks_proxy_port)"
    http="$(http_proxy_port)"
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '')"
    if python3 - "$path" "$$" "$slot" "$socks" "$http" "$started" <<'PY'; then
import json, sys
path, pid, slot, socks, http, started = sys.argv[1:7]
payload = {"pid": int(pid), "slot": int(slot), "socks": int(socks), "http": int(http), "started_utc": started}
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f)
PY
        CURSOR_PROXY_OWNER=1
        export CURSOR_PROXY_OWNER
        declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROXY_OWNER: claimed pid=$$ socks=$socks" 'INFO'
        return 0
    fi
    CURSOR_PROXY_OWNER=0
    export CURSOR_PROXY_OWNER
    declare -F connect_log >/dev/null 2>&1 && connect_log 'CURSOR_PROXY_OWNER: claim_fail' 'WARN'
    return 1
}

release_cursor_proxy_owner() {
    local reason="${1:-}"
    test_is_cursor_proxy_owner || return 0
    rm -f "$(cursor_proxy_owner_path)" 2>/dev/null || true
    CURSOR_PROXY_OWNER=0
    export CURSOR_PROXY_OWNER
    _PROXY_OWNER_SERVICE_DEAD_SINCE=0
    if [ "$reason" = "service_dead" ]; then
        # S2 token must appear literally (Win/Mac parity).
        declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROXY_OWNER: released reason=service_dead pid=$$" 'INFO'
    elif [ -n "$reason" ]; then
        declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROXY_OWNER: released reason=$reason pid=$$" 'INFO'
    else
        declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROXY_OWNER: released pid=$$" 'INFO'
    fi
}

_cursor_proxy_health_now() {
    if [ -n "${_CURSOR_PROXY_HEALTH_NOW:-}" ]; then
        printf '%s' "$_CURSOR_PROXY_HEALTH_NOW"
        return 0
    fi
    date +%s 2>/dev/null || printf '0'
}

_no_proc_zombie_now() {
    if [ -n "${_NO_PROC_ZOMBIE_NOW:-}" ]; then
        printf '%s' "$_NO_PROC_ZOMBIE_NOW"
        return 0
    fi
    date +%s 2>/dev/null || printf '0'
}

# Returns 0 (keep) when no_proc age < NO_PROC_ZOMBIE_SEC, or age>=threshold with auth+banner.
# Returns 1 when age gate should drop (caller logs soft_fail_exhausted_zombie_drop).
_no_proc_should_keep() {
    local now age auth_owned=0 banner_ok=0 zbanner
    now="$(_no_proc_zombie_now)"
    if [ -z "${_NO_PROC_KEEPALIVE_SINCE:-}" ] || [ "${_NO_PROC_KEEPALIVE_SINCE}" -eq 0 ]; then
        _NO_PROC_KEEPALIVE_SINCE="$now"
    fi
    age=$(( now - _NO_PROC_KEEPALIVE_SINCE ))
    if [ "$age" -lt "${NO_PROC_ZOMBIE_SEC:-120}" ]; then
        return 0
    fi
    if declare -F tunnel_port_auth_owned >/dev/null 2>&1 && tunnel_port_auth_owned "${PORT:-0}"; then
        auth_owned=1
    fi
    zbanner="$(fetch_tunnel_banner 2>/dev/null || true)"
    if [ -n "$zbanner" ] && declare -F tunnel_banner_is_windows >/dev/null 2>&1 && tunnel_banner_is_windows "$zbanner"; then
        banner_ok=1
    fi
    [ "$auth_owned" -eq 1 ] && [ "$banner_ok" -eq 1 ] && return 0
    return 1
}

test_cursor_proxy_backends_up() {
    local back_s back_h
    back_s="${SOCKS_PROXY_PORT:-}"
    back_h="${HTTP_PROXY_PORT:-}"
    if [ -z "$back_s" ]; then back_s="$(socks_proxy_port)"; fi
    if [ -z "$back_h" ]; then back_h="$(http_proxy_port)"; fi
    [ -n "$back_s" ] && [ -n "$back_h" ] || return 1
    test_local_port_open "$back_s" && test_local_port_open "$back_h"
}

update_cursor_proxy_owner_service_health() {
    # OwnerServiceDead := IsOwner AND NOT BackendsUp AND XrayExpected
    #   AND age >= SERVICE_DEAD_SEC (60). XrayExpected := SESSION_EVER_HAD_PROXY_LEGS.
    # Called from complete AND sync (D5 Sync-tick path).
    local now age dead_sec
    test_is_cursor_proxy_owner || return 0
    if [ "${SESSION_EVER_HAD_PROXY_LEGS:-0}" != "1" ]; then
        _PROXY_OWNER_SERVICE_DEAD_SINCE=0
        return 0
    fi
    if test_cursor_proxy_backends_up; then
        _PROXY_OWNER_SERVICE_DEAD_SINCE=0
        return 0
    fi
    now="$(_cursor_proxy_health_now)"
    case "$now" in ''|*[!0-9]*) now=0 ;; esac
    if [ "${_PROXY_OWNER_SERVICE_DEAD_SINCE:-0}" -le 0 ] 2>/dev/null; then
        _PROXY_OWNER_SERVICE_DEAD_SINCE="$now"
        return 0
    fi
    dead_sec="${SERVICE_DEAD_SEC:-60}"
    case "$dead_sec" in ''|*[!0-9]*) dead_sec=60 ;; esac
    [ "$dead_sec" -ge 1 ] 2>/dev/null || dead_sec=60
    age=$(( now - _PROXY_OWNER_SERVICE_DEAD_SINCE ))
    if [ "$age" -ge "$dead_sec" ] 2>/dev/null; then
        declare -F connect_log >/dev/null 2>&1 && \
            connect_log "CURSOR_PROXY_OWNER: service_dead age_sec=$age threshold=$dead_sec" 'WARN'
        release_cursor_proxy_owner service_dead
    fi
    return 0
}

test_local_port_open() {
    local port="${1:-}" timeout_ms="${2:-400}"
    python3 - "$port" "$timeout_ms" <<'PY' 2>/dev/null
import socket, sys
port, ms = int(sys.argv[1]), int(sys.argv[2])
s = socket.socket()
s.settimeout(ms / 1000.0)
try:
    s.connect(("127.0.0.1", port))
    sys.exit(0)
except OSError:
    sys.exit(1)
finally:
    s.close()
PY
}

cursor_socks_front_port() {
    if [ -n "${CURSOR_SOCKS_FRONT_PORT:-}" ]; then printf '%s' "$CURSOR_SOCKS_FRONT_PORT"; return; fi
    socks_proxy_port
}

cursor_http_front_port() {
    if [ -n "${CURSOR_HTTP_FRONT_PORT:-}" ]; then printf '%s' "$CURSOR_HTTP_FRONT_PORT"; return; fi
    http_proxy_port
}


get_cursor_proxy_mode() {
    # sidecar | xray | server_direct (Win Get-CursorProxyMode parity)
    local front_s front_h back_s back_h
    front_s="$(cursor_socks_front_port)"
    front_h="$(cursor_http_front_port)"
    back_s="${SOCKS_PROXY_PORT:-$(socks_proxy_port)}"
    back_h="${HTTP_PROXY_PORT:-$(http_proxy_port)}"
    if [ -n "$front_s" ] && [ -n "$front_h" ] \
        && test_local_port_open "$front_s" && test_local_port_open "$front_h" \
        && [ -n "$back_s" ] && [ -n "$back_h" ] \
        && test_local_port_open "$back_s" && test_local_port_open "$back_h"; then
        printf '%s' sidecar
        return 0
    fi
    if [ -n "$back_s" ] && [ -n "$back_h" ] \
        && test_local_port_open "$back_s" && test_local_port_open "$back_h"; then
        printf '%s' xray
        return 0
    fi
    printf '%s' server_direct
}

complete_cursor_proxy_after_tunnel() {
    # Win Complete-CursorProxyAfterTunnel parity: heal sidecar, health-check,
    # clear dead 18998 on failure, log PROXY_FALLBACK / CURSOR_PROXY_MODE.
    #
    # Fast path (Win P0 2026-07-28): when THIS tunnel has no -L proxy legs
    # (xray closed), do not start sticky fronts against dead backends.
    # Skip predicate uses SESSION vars only — socks_proxy_port/http_proxy_port
    # always return 19080/19180 and would defeat the skip.
    # Never adopt orphan fixed-port listeners (Bugbot residual 2026-07-28).
    # Owner/service coupling: tick even on early skip (xray_closed must not service_dead).
    if declare -F update_cursor_proxy_owner_service_health >/dev/null 2>&1; then
        update_cursor_proxy_owner_service_health || true
    fi
    local session_socks="${SOCKS_PROXY_PORT:-}"
    local session_http="${HTTP_PROXY_PORT:-}"
    if [ -z "$session_socks" ] && [ -z "$session_http" ]; then
        declare -F connect_log >/dev/null 2>&1 && connect_log 'complete_cursor_proxy_after_tunnel skip_sidecar reason=no_tunnel_proxy_legs' 'INFO'
        local front_h_clear
        front_h_clear="$(cursor_http_front_port)"
        if [ -n "$front_h_clear" ] && test_local_port_open "$front_h_clear"; then
            if declare -F clear_cursor_proxy_settings >/dev/null 2>&1; then
                clear_cursor_proxy_settings || true
            fi
        fi
        declare -F connect_log >/dev/null 2>&1 && connect_log 'PROXY_FALLBACK mode=server_direct reason=no_tunnel_proxy_legs' 'INFO'
        declare -F connect_log >/dev/null 2>&1 && connect_log 'CURSOR_PROXY_MODE mode=server_direct' 'INFO'
        return 0
    fi
    local health_ok=0 front_h front_up=0 mode
    if declare -F start_cursor_proxy_sidecar >/dev/null 2>&1; then
        start_cursor_proxy_sidecar || true
    fi
    if declare -F proxy_health >/dev/null 2>&1; then
        if proxy_health; then health_ok=1; fi
    fi
    front_h="$(cursor_http_front_port)"
    if [ -n "$front_h" ] && test_local_port_open "$front_h"; then
        front_up=1
    fi
    if [ "$health_ok" -eq 0 ]; then
        if [ "$front_up" -eq 0 ]; then
            declare -F connect_log >/dev/null 2>&1 && \
                connect_log 'CURSOR_PROXY_CLEAR force reason=18998_down_windows_open' 'INFO'
            if declare -F clear_cursor_proxy_settings >/dev/null 2>&1; then
                if declare -F test_may_clear_cursor_proxy_settings >/dev/null 2>&1; then
                    if test_may_clear_cursor_proxy_settings 1; then
                        clear_cursor_proxy_settings || true
                    else
                        declare -F connect_log >/dev/null 2>&1 && connect_log 'CURSOR_PROXY_CLEAR_SKIP: reason=windows_open_or_non_owner action=reload_for_server_direct' 'WARN'
                    fi
                else
                    clear_cursor_proxy_settings || true
                fi
            fi
            declare -F connect_log >/dev/null 2>&1 && connect_log 'PROXY_FALLBACK mode=server_direct reason=proxy_health_fail_front_down' 'INFO'
        else
            declare -F connect_log >/dev/null 2>&1 && \
                connect_log 'CURSOR_PROXY_CLEAR force reason=backend_down' 'INFO'
            if declare -F clear_cursor_proxy_settings >/dev/null 2>&1; then
                if declare -F test_may_clear_cursor_proxy_settings >/dev/null 2>&1; then
                    if test_may_clear_cursor_proxy_settings 1; then
                        clear_cursor_proxy_settings || true
                    fi
                else
                    clear_cursor_proxy_settings || true
                fi
            fi
            declare -F connect_log >/dev/null 2>&1 && connect_log 'PROXY_FALLBACK mode=server_direct reason=proxy_health_fail' 'INFO'
        fi
    fi
    mode="$(get_cursor_proxy_mode)"
    declare -F connect_log >/dev/null 2>&1 && connect_log "CURSOR_PROXY_MODE mode=$mode" 'INFO'
}

proxy_health() {
    local http_port socks_port ip
    http_port="$(cursor_http_front_port)"
    socks_port="$(cursor_socks_front_port)"
    if [ -z "$http_port" ] || [ "$http_port" -le 0 ] 2>/dev/null; then
        declare -F connect_log >/dev/null 2>&1 && connect_log 'PROXY_HEALTH ok=0 reason=no_http_port' 'WARN'
        return 1
    fi
    if ! test_local_port_open "$http_port"; then
        declare -F connect_log >/dev/null 2>&1 && connect_log "PROXY_HEALTH socks=$socks_port http=$http_port ok=0 reason=http_not_listening" 'WARN'
        return 1
    fi
    # Fast-fail when backend legs are down (front up + dead backend makes the probe hang to timeout).
    local back_s back_h
    back_s="${SOCKS_PROXY_PORT:-$(socks_proxy_port)}"
    back_h="${HTTP_PROXY_PORT:-$(http_proxy_port)}"
    if ! test_local_port_open "$back_s" || ! test_local_port_open "$back_h"; then
        declare -F connect_log >/dev/null 2>&1 && connect_log "PROXY_HEALTH socks=$socks_port http=$http_port ok=0 reason=backend_not_listening" 'WARN'
        return 1
    fi
    ip="$(curl -sf --max-time 3 -x "http://127.0.0.1:${http_port}" -A claude-connect-proxy-health https://api.ipify.org 2>/dev/null | tr -d '
' || true)"
    if [ -z "$ip" ]; then
        declare -F connect_log >/dev/null 2>&1 && connect_log "PROXY_HEALTH socks=$socks_port http=$http_port ok=0 reason=empty_ip" 'WARN'
        return 1
    fi
    declare -F connect_log >/dev/null 2>&1 && connect_log "PROXY_HEALTH socks=$socks_port http=$http_port ok=1 ip=$ip" 'INFO'
    return 0
}

socks_proxy_port() {
    printf '%s' 19080
}

http_proxy_port() {
    printf '%s' 19180
}

local_port_free() {
    # Return 0 if can bind 127.0.0.1:$1 (port unused). Fail closed (busy) -> return 1.
    local port="$1"
    python3 -c "import socket,sys; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(('127.0.0.1',int(sys.argv[1]))); s.close()" "$port" 2>/dev/null
}

local_port_listening() {
    # Quiet TCP probe (no nc -z noise).
    local port="$1"
    test_local_port_open "$port" 400
}

remote_xray_http_open() {
    local port="${XRAY_SERVER_HTTP_PORT}"
    local out
    out="$(sshx "timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/${port} 2>/dev/null' && echo open || echo closed" 2>/dev/null | tr -d '\r\n')"
    [ "$out" = open ]
}
remote_xray_socks_open() {
    # Probe 10808 ON SERVER via sshx (defined in connect.sh). Fail closed.
    local port="${XRAY_SERVER_SOCKS_PORT}"
    local out
    out="$(sshx "timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/${port} 2>/dev/null' && echo open || echo closed" 2>/dev/null | tr -d '\r\n')"
    [ "$out" = open ]
}

set_socks_proxy_port_on_reuse() {
    # Reused tunnel may predate the -L proxy leg; fail closed unless cmdline, local listen,
    # and remote xray all check out. Keep prior ports on failure (Win parity).
    local tunnel_pid="${1:-${bg_pid:-}}" prev_socks prev_http
    prev_socks="${SOCKS_PROXY_PORT:-}"
    prev_http="${HTTP_PROXY_PORT:-}"
    [ -n "$tunnel_pid" ] || return 0
    local socks_candidate http_candidate args fwd_needle http_needle
    socks_candidate="$(socks_proxy_port)"
    http_candidate="$(http_proxy_port)"
    args="$(ps -p "$tunnel_pid" -o args= 2>/dev/null || true)"
    fwd_needle="-L 127.0.0.1:${socks_candidate}:127.0.0.1:${XRAY_SERVER_SOCKS_PORT}"
    http_needle="-L 127.0.0.1:${http_candidate}:127.0.0.1:${XRAY_SERVER_HTTP_PORT}"
    case "$args" in *"$fwd_needle"*) ;; *) return 0 ;; esac
    case "$args" in *"$http_needle"*) ;; *) return 0 ;; esac
    if ! local_port_listening "$socks_candidate"; then
        return 0
    fi
    if ! local_port_listening "$http_candidate"; then
        return 0
    fi
    if ! remote_xray_socks_open; then
        return 0
    fi
    if ! remote_xray_http_open; then
        return 0
    fi
    SOCKS_PROXY_PORT="$socks_candidate"
    HTTP_PROXY_PORT="$http_candidate"
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "ENSURE_TUNNEL reuse_proxy ok local=$socks_candidate remote=${XRAY_SERVER_SOCKS_PORT} http_local=$http_candidate http_remote=${XRAY_SERVER_HTTP_PORT}" 'INFO'
    fi
}


tunnel_proxy_leg_state() {
    local tunnel_pid="${1:-}"
    local socks_candidate args fwd_needle
    [ -n "$tunnel_pid" ] || { echo unknown; return 0; }
    socks_candidate="$(socks_proxy_port)"
    args="$(ps -p "$tunnel_pid" -o args= 2>/dev/null || true)"
    [ -n "$args" ] || { echo unknown; return 0; }
    local http_candidate http_needle
    http_candidate="$(http_proxy_port)"
    fwd_needle="-L 127.0.0.1:${socks_candidate}:127.0.0.1:${XRAY_SERVER_SOCKS_PORT}"
    http_needle="-L 127.0.0.1:${http_candidate}:127.0.0.1:${XRAY_SERVER_HTTP_PORT}"
    case "$args" in *"$fwd_needle"*)
        case "$args" in *"$http_needle"*) echo ok; return 0 ;; esac
        echo missing_http
        return 0
        ;;
    esac
    case "$args" in *"-D 127.0.0.1:${socks_candidate}"*) echo legacy_D; return 0 ;; esac
    echo missing
}


append_http_proxy_leg() {
    local http_candidate
    [ -n "${SOCKS_PROXY_PORT:-}" ] || return 0
    http_candidate="$(http_proxy_port)"
    if ! remote_xray_http_open; then
        declare -F connect_log >/dev/null 2>&1 && connect_log "ENSURE_TUNNEL remote_xray_http=closed port=${XRAY_SERVER_HTTP_PORT} skipping_http_proxy_leg" 'INFO'
        return 0
    fi
    if ! local_port_free "$http_candidate"; then
        declare -F connect_log >/dev/null 2>&1 && connect_log "ENSURE_TUNNEL http_port_busy port=$http_candidate skipping_http_proxy_leg" 'WARN'
        return 0
    fi
    socks_args+=(-L "127.0.0.1:${http_candidate}:127.0.0.1:${XRAY_SERVER_HTTP_PORT}")
    HTTP_PROXY_PORT="$http_candidate"
    declare -F connect_log >/dev/null 2>&1 && connect_log "ENSURE_TUNNEL http_proxy_leg=-L local=$http_candidate remote=${XRAY_SERVER_HTTP_PORT}" 'INFO'
}
tunnel_needs_proxy_reseed() {
    # Return 0 when reseed is needed; non-zero means keep/reuse (no reseed).
    # Callers: if ! tunnel_needs_proxy_reseed; then return 0; fi
    local tunnel_pid="${1:-}"
    [ -n "$tunnel_pid" ] || return 1
    remote_xray_socks_open || return 1
    local state socks_candidate http_candidate socks_front http_front
    state="$(tunnel_proxy_leg_state "$tunnel_pid")"
    case "$state" in
        ok|unknown) return 1 ;;
    esac
    # Adopted proxy: this pid has no -L (or only SOCKS), but another process already
    # serves fixed backends 19080/19180 or front doors 18998/18999 - do not reseed.
    # legacy_D still needs reseed (clears stale -D binding).
    case "$state" in
        missing|missing_http)
            socks_candidate="$(socks_proxy_port)"
            http_candidate="$(http_proxy_port)"
            socks_front="$(cursor_socks_front_port)"
            http_front="$(cursor_http_front_port)"
            if { test_local_port_open "$socks_candidate" && test_local_port_open "$http_candidate"; } \
                || { test_local_port_open "$socks_front" && test_local_port_open "$http_front"; }; then
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "ENSURE_TUNNEL reseed_skip reason=proxy_adopted_elsewhere state=$state pid=$tunnel_pid" 'INFO'
                fi
                [ -n "${SOCKS_PROXY_PORT:-}" ] || SOCKS_PROXY_PORT="$socks_candidate"
                [ -n "${HTTP_PROXY_PORT:-}" ] || HTTP_PROXY_PORT="$http_candidate"
                return 1
            fi
            ;;
    esac
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "ENSURE_TUNNEL reseed_needed reason=$state pid=$tunnel_pid socks=$(socks_proxy_port)" 'WARN'
    fi
    return 0
}

clear_legacy_dynamic_socks_tunnels() {
    # Free OUR socks port only when a legacy ssh -D still holds it (never mass-kill other slots).
    local protect="${1:-}"
    local socks="${2:-}"
    [ -n "$socks" ] || socks="$(socks_proxy_port)"
    local killed=0
    local pid args needle
    needle="-D 127.0.0.1:${socks}"
    for pid in $(pgrep -x ssh 2>/dev/null || true); do
        [ -n "$protect" ] && [ "$pid" = "$protect" ] && continue
        args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
        case "$args" in
            *' -N '*|*-N\ *) ;;
            *) continue ;;
        esac
        case "$args" in *"-R "*|*"-R="*) ;;
            *) continue ;;
        esac
        case "$args" in
            *":localhost:22"*|*":127.0.0.1:22"*) ;;
            *) continue ;;
        esac
        case "$args" in *"$needle"*) ;; *) continue ;; esac
        case "$args" in *"-L 127.0.0.1:${socks}:"*) continue ;; esac
        case "$args" in *claude-server-sepidz*) continue ;; esac
        case "$args" in *claude-server*) ;; *) continue ;; esac
        kill "$pid" 2>/dev/null || true
        killed=$((killed + 1))
    done
    if [ "$killed" -gt 0 ] && declare -F connect_log >/dev/null 2>&1; then
        connect_log "ENSURE_TUNNEL legacy_D_cleanup killed=$killed socks=$socks" 'WARN'
    fi
}


# Reuse live tunnel when possible; sets TUNNEL_REUSED=0|1 and bg_pid.
ensure_session_tunnel() {
    TUNNEL_REUSED=0
    _PROXY_RESEED=0
    local now_ts
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "ENSURE_TUNNEL begin port=${PORT:-?} alias=${ALIAS:-}" 'INFO'
    fi
    # Once per Ensure: pin preferred → orphan reclaim → then reuse/adopt (Win Ensure parity).
    # Honor CLAUDE_CONNECT_AUTO_RECLAIM=0 killswitch inside invoke_connect_orphan_reclaim.
    if [ "${_ORPHAN_RECLAIM_DONE_THIS_ENSURE:-0}" != "1" ]; then
        _ORPHAN_RECLAIM_DONE_THIS_ENSURE=1
        local _uid_reclaim="" _pref_port="${PORT:-0}"
        _uid_reclaim="${SERVER_UID_STR:-}"
        if [ -z "$_uid_reclaim" ]; then
            _uid_reclaim="$(sshx 'id -u' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+$' | head -1 | tr -dc '0-9')"
            [ -n "$_uid_reclaim" ] && SERVER_UID_STR="$_uid_reclaim"
        fi
        if declare -F invoke_connect_orphan_reclaim >/dev/null 2>&1; then
            invoke_connect_orphan_reclaim "$_uid_reclaim" "$_pref_port" \
                "${ACTIVE_PROJECT_PATH:-${go_path:-}}" "${ACTIVE_PROJECT_ID:-${go_id:-}}" || true
        fi
        unset _uid_reclaim _pref_port
    fi
    # PID loss is not authoritative: a re-parented reverse forward can remain usable.
    # Reuse valid banner/TCP evidence before any kill or stale-forward cleanup.
    if [ -n "${bg_pid:-}" ]; then
        if tunnel_up; then
            TUNNEL_REUSED=1
            _TUNNEL_SYNC_FAIL_COUNT=0
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "ENSURE_TUNNEL reused=1 pid=$bg_pid port=$PORT reason=tunnel_up" 'DEBUG'
            fi
            set_socks_proxy_port_on_reuse "$bg_pid"
            if ! proxy_reseed_should_kill "$bg_pid"; then
                if declare -F complete_cursor_proxy_after_tunnel >/dev/null 2>&1; then
                    complete_cursor_proxy_after_tunnel || true
                fi
                declare -F connect_log >/dev/null 2>&1 && connect_log "ENSURE_TUNNEL end outcome=reused reason=tunnel_up port=$PORT" 'INFO'
                return 0
            fi
            TUNNEL_REUSED=0
            _PROXY_RESEED=1
        fi
        # Banner miss + TCP open: zombie forward. Do not return success / TUNNEL_REUSED.
        # Match Windows Ensure-SessionTunnel: soft_fail then fall through to kill + reseed.
        # Skip when we already decided to reseed for missing/legacy proxy leg.
        if [ "${_PROXY_RESEED:-0}" != "1" ] && tunnel_port_tcp_open "$PORT"; then
            connect_log "ENSURE_TUNNEL soft_fail pid=$bg_pid port=$PORT reason=banner_miss_tcp_open action=reseed$(_tunnel_session_diag_suffix)" 'WARN'
            # Fall through unless recent_success (5s) covers brief banner flicker.
        fi
        # 5s recent_success reuse (Win parity).
        now_ts="$(date +%s 2>/dev/null || printf '0')"
        if [ "${_PROXY_RESEED:-0}" != "1" ] \
            && [ -n "${_LAST_TUNNEL_SPAWN_SUCCESS_AT:-}" ] && [ "${_LAST_TUNNEL_SPAWN_SUCCESS_AT:-0}" != "0" ] \
            && [ -n "${_LAST_TUNNEL_SPAWN_PID:-}" ] && [ "$_LAST_TUNNEL_SPAWN_PID" = "$bg_pid" ] \
            && [ "${_LAST_TUNNEL_SPAWN_SUCCESS_PORT:-}" = "${PORT:-}" ] \
            && [ "$now_ts" != "0" ] \
            && [ $(( now_ts - _LAST_TUNNEL_SPAWN_SUCCESS_AT )) -lt 5 ]; then
            TUNNEL_REUSED=1
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "ENSURE_TUNNEL reused=1 pid=$bg_pid port=$PORT reason=recent_success" 'DEBUG'
            fi
            set_socks_proxy_port_on_reuse "$bg_pid"
            if ! proxy_reseed_should_kill "$bg_pid"; then
                if declare -F complete_cursor_proxy_after_tunnel >/dev/null 2>&1; then
                    complete_cursor_proxy_after_tunnel || true
                fi
                declare -F connect_log >/dev/null 2>&1 && connect_log "ENSURE_TUNNEL end outcome=reused reason=recent_success port=$PORT" 'INFO'
                return 0
            fi
            TUNNEL_REUSED=0
            _PROXY_RESEED=1
            TUNNEL_REUSED=0
        fi
    fi
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "ENSURE_TUNNEL start port=$PORT alias=${ALIAS:-} had_bg=$([ -n "${bg_pid:-}" ] && echo 1 || echo 0)" 'DEBUG'
    fi
    local _old_bg="${bg_pid:-}"
    if [ -n "${bg_pid:-}" ]; then
        # Belt: never kill -R for proxy reseed when foreign owner cannot bind -L
        if [ "${_PROXY_RESEED:-0}" = "1" ] && ! can_claim_cursor_proxy_owner; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "ENSURE_TUNNEL reseed_skip reason=foreign_owner_cannot_bind pid=$bg_pid port=${PORT:-}" 'INFO'
            fi
            if declare -F complete_cursor_proxy_after_tunnel >/dev/null 2>&1; then
                complete_cursor_proxy_after_tunnel || true
            fi
            TUNNEL_REUSED=1
            declare -F connect_log >/dev/null 2>&1 && connect_log "ENSURE_TUNNEL end outcome=reused reason=reseed_skip_foreign port=${PORT:-}" 'INFO'
            return 0
        fi
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "ENSURE_TUNNEL killing stale bg pid=$bg_pid" 'DEBUG'
        fi
        kill "$bg_pid" 2>/dev/null || true
        [ -n "${PORT:-}" ] && clear_server_stale_tunnel_forward "$PORT" || true
    fi
    bg_pid=""
    # Prefer orphan helper with no protect (old bg already killed) over blind pkill storms.
    remove_local_orphan_tunnel "$PORT" "" || true
    local uid_str=""
    uid_str="$(sshx 'id -u' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+$' | head -1 | tr -dc '0-9')"
    if [ -n "$uid_str" ]; then
        acquire_tunnel_port "$uid_str" || true
    fi
    release_stale_tunnel_port || true
    sanitize_ssh_alias_config
    clear_tunnel_banner_cache
    _LAST_FORWARD_PROBE_AT=0
    _TUNNEL_SYNC_FAIL_COUNT=0
    SOCKS_PROXY_PORT=""
    HTTP_PROXY_PORT=""
    # socks port known after assignment below; cleanup runs in busy branch / after candidate
    local socks_candidate socks_args=()
    socks_candidate="$(socks_proxy_port)"
    clear_legacy_dynamic_socks_tunnels "${_old_bg:-}" "$socks_candidate"
    local _is_proxy_owner=0
    if claim_cursor_proxy_owner; then
        _is_proxy_owner=1
    fi
    if ! remote_xray_socks_open; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "ENSURE_TUNNEL remote_xray_socks=closed port=${XRAY_SERVER_SOCKS_PORT} skipping_proxy_leg" 'INFO'
            connect_log 'PROXY_FALLBACK mode=server_direct reason=xray_closed' 'INFO'
            connect_log 'CURSOR_PROXY_MODE mode=server_direct' 'INFO'
        fi
    elif [ "$_is_proxy_owner" -eq 0 ]; then
        if test_local_port_open "$socks_candidate" && test_local_port_open "$(http_proxy_port)"; then
            SOCKS_PROXY_PORT="$socks_candidate"
            HTTP_PROXY_PORT="$(http_proxy_port)"
            declare -F connect_log >/dev/null 2>&1 && connect_log "ENSURE_TUNNEL proxy_adopt non_owner local=$socks_candidate" 'INFO'
        else
            declare -F connect_log >/dev/null 2>&1 && connect_log 'ENSURE_TUNNEL proxy_skip reason=non_owner_no_listener' 'INFO'
        fi
    elif ! local_port_free "$socks_candidate"; then
        if test_local_port_open "$socks_candidate"; then
            SOCKS_PROXY_PORT="$socks_candidate"
            HTTP_PROXY_PORT="$(http_proxy_port)"
            if test_local_port_open "$(http_proxy_port)"; then
                :
            else
                HTTP_PROXY_PORT=""
            fi
            SESSION_EVER_HAD_PROXY_LEGS=1
            declare -F connect_log >/dev/null 2>&1 && connect_log "ENSURE_TUNNEL proxy_adopt busy_healthy local=$socks_candidate" 'INFO'
        else
            clear_legacy_dynamic_socks_tunnels "" "$socks_candidate"
            if local_port_free "$socks_candidate"; then
                socks_args=(-L "127.0.0.1:${socks_candidate}:127.0.0.1:${XRAY_SERVER_SOCKS_PORT}")
                SOCKS_PROXY_PORT="$socks_candidate"
                SESSION_EVER_HAD_PROXY_LEGS=1
                declare -F connect_log >/dev/null 2>&1 && connect_log "ENSURE_TUNNEL proxy_leg=-L local=$socks_candidate remote=${XRAY_SERVER_SOCKS_PORT} after_legacy_cleanup" 'INFO'
                append_http_proxy_leg
            elif declare -F connect_log >/dev/null 2>&1; then
                connect_log "ENSURE_TUNNEL socks_port_busy port=$socks_candidate skipping_proxy_leg" 'WARN'
            fi
        fi
    else
        socks_args=(-L "127.0.0.1:${socks_candidate}:127.0.0.1:${XRAY_SERVER_SOCKS_PORT}")
        SOCKS_PROXY_PORT="$socks_candidate"
        SESSION_EVER_HAD_PROXY_LEGS=1
        declare -F connect_log >/dev/null 2>&1 && connect_log "ENSURE_TUNNEL proxy_leg=-L local=$socks_candidate remote=${XRAY_SERVER_SOCKS_PORT}" 'INFO'
        append_http_proxy_leg
    fi
    # Still-busy: never spawn -R on sticky busy port (D4). Rebind to another free slot;
    # cap consecutive refuse cycles so a renewing still-busy marker cannot self-deadlock.
    if stale_forward_still_busy_abort "$PORT"; then
        local busy_port="$PORT" prev_port="$PORT" saved_slot="${TUNNEL_SLOT:-}" rebound=0
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "ENSURE_TUNNEL refuse_spawn reason=stale_port_busy port=$busy_port" 'WARN'
        fi
        _REFUSE_SPAWN_STREAK=$(( ${_REFUSE_SPAWN_STREAK:-0} + 1 ))
        if [ "$_REFUSE_SPAWN_STREAK" -ge "${REFUSE_SPAWN_STREAK_CAP:-5}" ]; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "ENSURE_TUNNEL refuse_spawn_streak_exhausted port=$busy_port streak=$_REFUSE_SPAWN_STREAK cap=${REFUSE_SPAWN_STREAK_CAP:-5}" 'ERROR'
            fi
            bg_pid=""
            return 1
        fi
        if [ -n "${uid_str:-}" ] && declare -F acquire_tunnel_port >/dev/null 2>&1; then
            if acquire_tunnel_port "$uid_str"; then
                if [ -n "${PORT:-}" ] && [ "$PORT" != "$prev_port" ]; then
                    rebound=1
                fi
            fi
        fi
        if [ "$rebound" -eq 1 ]; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "ENSURE_TUNNEL refuse_spawn reason=stale_port_busy_rebind from=$prev_port to=$PORT streak=$_REFUSE_SPAWN_STREAK" 'WARN'
            fi
            _LAST_STALE_FORWARD_STILL_BUSY_PORT=
            _LAST_STALE_FORWARD_STILL_BUSY_AT=0
            _REFUSE_SPAWN_STREAK=0
        else
            PORT="$prev_port"
            TUNNEL_SLOT="$saved_slot"
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "ENSURE_TUNNEL refuse_spawn reason=stale_port_busy_no_rebind port=$busy_port streak=$_REFUSE_SPAWN_STREAK" 'WARN'
            fi
            bg_pid=""
            return 1
        fi
    fi
    ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=20 -o ServerAliveCountMax=5 \
        -R "${PORT}:localhost:22" "${socks_args[@]}" "$ALIAS" 2>/dev/null &
    bg_pid=$!
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "ENSURE_TUNNEL spawned pid=$bg_pid port=$PORT slot=${TUNNEL_SLOT:-} socks_port=${SOCKS_PROXY_PORT:-} http_port=${HTTP_PROXY_PORT:-}" 'INFO'
    fi
    if poll_tunnel_with_progress "$bg_pid"; then
        _LAST_TUNNEL_SPAWN_SUCCESS_AT="$(date +%s 2>/dev/null || printf '0')"
        _LAST_TUNNEL_SPAWN_SUCCESS_PORT="${PORT:-}"
        _LAST_TUNNEL_SPAWN_PID="$bg_pid"
        _TUNNEL_SYNC_FAIL_COUNT=0
        TUNNEL_WAIT_FAIL_STREAK=0
        TUNNEL_WAIT_BACKOFF_SEC=2
        _REFUSE_SPAWN_STREAK=0
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "ENSURE_TUNNEL ok=1 pid=$bg_pid" 'INFO'
            connect_log "ENSURE_TUNNEL end outcome=ok port=$PORT" 'INFO'
        fi
        if declare -F complete_cursor_proxy_after_tunnel >/dev/null 2>&1; then
            complete_cursor_proxy_after_tunnel || true
        else
            if declare -F proxy_health >/dev/null 2>&1; then
                proxy_health || true
            fi
            if declare -F start_cursor_proxy_sidecar >/dev/null 2>&1; then
                start_cursor_proxy_sidecar || true
            fi
        fi
        return 0
    fi
    TUNNEL_WAIT_FAIL_STREAK=$(( TUNNEL_WAIT_FAIL_STREAK + 1 ))
    [ -n "${TUNNEL_WAIT_BACKOFF_SEC:-}" ] || TUNNEL_WAIT_BACKOFF_SEC=2
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "ENSURE_TUNNEL ok=0 reason=wait_timeout pid=$bg_pid streak=$TUNNEL_WAIT_FAIL_STREAK backoff_sec=$TUNNEL_WAIT_BACKOFF_SEC" 'WARN'
        connect_log "ENSURE_TUNNEL end outcome=fail reason=wait_timeout port=${PORT:-}" 'WARN'
    fi
    if [ "$TUNNEL_WAIT_FAIL_STREAK" -ge 6 ]; then
        declare -F connect_log >/dev/null 2>&1 && connect_log 'ENSURE_TUNNEL wait_timeout_budget_exhausted surfacing_ui' 'ERROR'
    fi
    # Monotonic capped backoff — never skip sleep at high streak.
    sleep "$TUNNEL_WAIT_BACKOFF_SEC" 2>/dev/null || sleep 2
    if [ "$TUNNEL_WAIT_BACKOFF_SEC" -lt 60 ]; then
        TUNNEL_WAIT_BACKOFF_SEC=$(( TUNNEL_WAIT_BACKOFF_SEC * 2 ))
    fi
    kill "$bg_pid" 2>/dev/null || true
    bg_pid=""
    return 1
}


clear_server_stale_tunnel_forward() {
    local target_port="${1:-$PORT}"
    [ -n "$target_port" ] || return 0
    # Never fuser-kill another laptop's reverse tunnel (Windows peer banners look foreign on Mac).
    if tunnel_port_is_foreign_peer "$target_port"; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "STALE_FORWARD: refuse_kill_foreign port=$target_port" 'WARN'
        fi
        return 0
    fi
    if tunnel_hostkey_mismatch "$target_port"; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "STALE_FORWARD: refuse_kill_hostkey_mismatch port=$target_port" 'WARN'
        fi
        return 0
    fi
    sshx "fuser -k ${target_port}/tcp 2>/dev/null || true; pkill -u \\\$USER -f '127\\.0\\.0\\.1:${target_port}' 2>/dev/null || true; pkill -u \\\$USER -f ' -p ${target_port} ' 2>/dev/null || true" 2>/dev/null || true
    clear_tunnel_banner_cache
    local i=0
    while [ "$i" -lt 8 ]; do
        i=$(( i + 1 ))
        sleep 0.25
        clear_tunnel_banner_cache
        if ! tunnel_port_tcp_open "$target_port"; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "STALE_FORWARD: port released port=$target_port wait=$i" 'DEBUG'
            fi
            _LAST_STALE_FORWARD_STILL_BUSY_PORT=
            _LAST_STALE_FORWARD_STILL_BUSY_AT=0
            return 0
        fi
    done
    _LAST_STALE_FORWARD_STILL_BUSY_PORT="$target_port"
    _LAST_STALE_FORWARD_STILL_BUSY_AT="$(date +%s 2>/dev/null || printf '0')"
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "STALE_FORWARD: port still busy port=$target_port after wait" 'WARN'
    fi
    return 1
}

# StillBusyAbort: recent clear still-busy + TCP open + no local -R => refuse spawn same port.
stale_forward_still_busy_abort() {
    local target_port="${1:-$PORT}"
    [ -n "$target_port" ] || return 1
    [ -n "${_LAST_STALE_FORWARD_STILL_BUSY_PORT:-}" ] || return 1
    [ "$_LAST_STALE_FORWARD_STILL_BUSY_PORT" = "$target_port" ] || return 1
    [ -n "${_LAST_STALE_FORWARD_STILL_BUSY_AT:-}" ] && [ "${_LAST_STALE_FORWARD_STILL_BUSY_AT:-0}" != "0" ] || return 1
    local now_ts age window_sec
    now_ts="$(date +%s 2>/dev/null || printf '0')"
    [ "$now_ts" != "0" ] || return 1
    age=$(( now_ts - _LAST_STALE_FORWARD_STILL_BUSY_AT ))
    window_sec="${STILL_BUSY_WINDOW_SEC:-15}"
    [ "$age" -lt "$window_sec" ] || return 1
    tunnel_port_tcp_open "$target_port" || return 1
    # Empty local -R set required (own forward would make spawn appropriate).
    if declare -F get_local_tunnel_ssh_pids >/dev/null 2>&1; then
        local pids
        pids="$(get_local_tunnel_ssh_pids "$target_port" 2>/dev/null || true)"
        [ -z "$pids" ] || return 1
    fi
    return 0
}

# Shared local ssh -R matcher (Win Test-LocalTunnelSshCommandLine parity).
test_local_tunnel_ssh_command() {
    local target_port="$1"
    local cmd="$2"
    [ -n "$target_port" ] || return 1
    [ -n "$cmd" ] || return 1
    case "$cmd" in
        *ssh-keygen*) return 1 ;;
    esac
    if echo "$cmd" | grep -Eq -- "-R[[:space:]]*=[[:space:]]*${target_port}:(localhost|127\\.0\\.0\\.1):22([^0-9]|$)"; then
        return 0
    fi
    if echo "$cmd" | grep -Eq -- "-R[[:space:]]+${target_port}:(localhost|127\\.0\\.0\\.1):22([^0-9]|$)"; then
        return 0
    fi
    return 1
}

get_local_tunnel_ssh_pids() {
    local target_port="$1"
    local pid args
    [ -n "$target_port" ] || return 0
    for pid in $(pgrep -x ssh 2>/dev/null || true); do
        args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
        if test_local_tunnel_ssh_command "$target_port" "$args"; then
            printf '%s\n' "$pid"
        fi
    done
}

test_process_command_is_connect_ui() {
    # Mac Connect UI: connect.sh / connect-boot (Win: connect.ps1 / connect-boot.ps1).
    local cmd="${1:-}"
    [ -n "$cmd" ] || return 1
    printf '%s' "$cmd" | grep -qE '(^|[[:space:]/])connect\.sh|(^|[[:space:]/])connect-boot'
}

get_sibling_connect_tunnel_pids() {
    # Mirror Win Get-SiblingConnectTunnelPids: ssh -R whose ancestor is another Connect UI.
    local target_port="$1"
    local protect_extra="${2:-}"
    local ssh_pid cur hops is_sib ui_pid cmd parent
    [ -n "$target_port" ] || return 0
    for ssh_pid in $(get_local_tunnel_ssh_pids "$target_port" 2>/dev/null || true); do
        # Skip protected (current bg / extra list).
        if [ -n "${bg_pid:-}" ] && [ "$ssh_pid" = "$bg_pid" ]; then
            continue
        fi
        if [ -n "$protect_extra" ]; then
            case " $protect_extra " in *" $ssh_pid "*) continue ;; esac
        fi
        cur="$ssh_pid"
        hops=0
        is_sib=0
        while [ -n "$cur" ] && [ "$cur" -gt 0 ] 2>/dev/null && [ "$hops" -lt 14 ]; do
            hops=$((hops + 1))
            cmd="$(ps -p "$cur" -o command= 2>/dev/null || true)"
            if test_process_command_is_connect_ui "$cmd"; then
                ui_pid="$cur"
                if [ "$ui_pid" = "$$" ]; then
                    break
                fi
                if [ -n "$protect_extra" ]; then
                    case " $protect_extra " in *" $ui_pid "*) break ;; esac
                fi
                is_sib=1
                break
            fi
            parent="$(ps -p "$cur" -o ppid= 2>/dev/null | tr -d ' ')"
            [ -n "$parent" ] || break
            [ "$parent" = "$cur" ] && break
            cur="$parent"
        done
        if [ "$is_sib" -eq 1 ]; then
            printf '%s\n' "$ssh_pid"
        fi
    done
}

remove_local_orphan_tunnel() {
    local target_port="$1" killed=0 protect_pid="${2:-${bg_pid:-}}"
    local p siblings="" protect_set=""
    [ -n "$target_port" ] || return 0
    # Hybrid multi-UI: never kill a sibling's live ssh -R (ORPHAN_TUNNEL: skip_sibling).
    protect_set="$$"
    if [ -n "$protect_pid" ] && kill -0 "$protect_pid" 2>/dev/null; then
        protect_set="$protect_set $protect_pid"
    fi
    if [ -n "${bg_pid:-}" ] && kill -0 "$bg_pid" 2>/dev/null; then
        protect_set="$protect_set $bg_pid"
    fi
    siblings="$(get_sibling_connect_tunnel_pids "$target_port" "$protect_set" 2>/dev/null | tr '\n' ' ')"
    siblings="$(printf '%s' "$siblings" | sed 's/[[:space:]]*$//')"
    if [ -n "$siblings" ]; then
        protect_set="$protect_set $siblings"
    fi
    for p in $(get_local_tunnel_ssh_pids "$target_port" 2>/dev/null || true); do
        case " $protect_set " in
            *" $p "*)
                if declare -F connect_log >/dev/null 2>&1; then
                    case " $siblings " in
                        *" $p "*) connect_log "ORPHAN_TUNNEL: skip_sibling pid=$p port=$target_port" 'INFO' ;;
                        *) connect_log "ORPHAN_TUNNEL: skip_current pid=$p port=$target_port" 'DEBUG' ;;
                    esac
                fi
                continue
                ;;
        esac
        if kill -0 "$p" 2>/dev/null; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "ORPHAN_TUNNEL: kill pid=$p port=$target_port reason=unprotected_live" 'INFO'
            fi
            kill "$p" 2>/dev/null || true
            killed=1
        fi
    done
    clear_tunnel_banner_cache
    if [ "$killed" -eq 1 ]; then
        clear_server_stale_tunnel_forward "$target_port" || true
    fi
    # Return killed count via global for Soft callers (0/1 sufficient).
    _ORPHAN_TUNNEL_KILLED="$killed"
}

stop_session_tunnel_cleanup() {
    local clear_server="${1:-1}"
    if [ -n "${bg_pid:-}" ]; then
        kill "$bg_pid" 2>/dev/null || true
        bg_pid=""
    fi
    if [ -n "${PORT:-}" ]; then
        local _p
        for _p in $(get_local_tunnel_ssh_pids "$PORT" 2>/dev/null || true); do
            kill "$_p" 2>/dev/null || true
        done
        if [ "$clear_server" = "1" ]; then
            clear_server_stale_tunnel_forward "$PORT" || true
        fi
    fi
    clear_tunnel_banner_cache
}

release_stale_tunnel_port() {
    local banner=""
    [ -n "${PORT:-}" ] || return 0
    clear_tunnel_banner_cache
    banner="$(fetch_tunnel_banner 2>/dev/null || true)"
    if tunnel_port_is_foreign_peer "$PORT"; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "STALE_FORWARD: skip_foreign_peer port=$PORT banner=$banner" 'INFO'
        fi
        return 0
    fi
    if [ -n "$banner" ] && tunnel_banner_is_this_laptop "$banner"; then
        if tunnel_port_has_local_reverse "$PORT"; then
            return 0
        fi
        if tunnel_port_auth_owned "$PORT"; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "STALE_FORWARD: sticky_ours port=$PORT reclaim" 'DEBUG'
            fi
            clear_server_stale_tunnel_forward "$PORT" || true
            return 0
        fi
        # Windows peer banners are NOT "this laptop" on Mac - never kill them here.
        if tunnel_banner_is_windows "$banner"; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "STALE_FORWARD: skip_foreign_peer port=$PORT banner=$banner" 'INFO'
            fi
            return 0
        fi
        return 0
    fi
    if [ -n "$banner" ] && ! tunnel_banner_is_this_laptop "$banner"; then
        if tunnel_banner_is_transport_noise "$banner"; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "STALE_FORWARD: transport_fail skip_foreign_clear port=$PORT banner=$banner" 'DEBUG'
            fi
            return 0
        fi
        if tunnel_banner_is_windows "$banner"; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "STALE_FORWARD: skip_foreign_peer port=$PORT banner=$banner" 'INFO'
            fi
            return 0
        fi
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "STALE_FORWARD: foreign banner port=$PORT banner=$banner" 'DEBUG'
        fi
        clear_server_stale_tunnel_forward "$PORT" || true
        return 0
    fi
    if tunnel_port_tcp_open "$PORT"; then
        if tunnel_port_is_foreign_peer "$PORT"; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "STALE_FORWARD: skip_foreign_peer port=$PORT tcp=open" 'INFO'
            fi
            return 0
        fi
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "STALE_FORWARD: zombie port=$PORT tcp=open banner=(empty)" 'WARN'
        fi
        clear_server_stale_tunnel_forward "$PORT" || true
    fi
}

save_tunnel_slot() {
    [ -n "${TUNNEL_SLOT:-}" ] || return 0
    [ -f "${CFG:-}" ] || return 0
    grep -vE '^(TUNNEL_SLOT|PORT|TUNNEL_PORT)=' "$CFG" > "$CFG.tmp" 2>/dev/null && mv "$CFG.tmp" "$CFG"
    echo "TUNNEL_SLOT=$TUNNEL_SLOT" >> "$CFG"
    if [ -n "${PORT:-}" ]; then
        echo "PORT=$PORT" >> "$CFG"
        echo "TUNNEL_PORT=$PORT" >> "$CFG"
    fi
}

sanitize_ssh_alias_config() {
    local alias="${ALIAS:-claude-server}"
    [ -f "$HOME/.ssh/config" ] || return 0
    local tmp="$HOME/.ssh/config.tmp.${alias}.$$"
    local i
    for i in 1 2 3 4 5 6 7 8; do
        if awk -v a="$alias" '
            /^[[:space:]]*Host[[:space:]]+/ {
                skip=0
                for (j = 2; j <= NF; j++) if ($j == a) skip = 1
            }
            skip && /^[[:space:]]*RemoteForward/ { next }
            { print }
        ' "$HOME/.ssh/config" > "$tmp" 2>/dev/null \
            && mv -f "$tmp" "$HOME/.ssh/config" 2>/dev/null; then
            chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
            return 0
        fi
        rm -f "$tmp" 2>/dev/null || true
        sleep 0.15
    done
    rm -f "$tmp" 2>/dev/null || true
    return 0
}


tunnel_banner_is_windows() {
    local banner="${1:-}"
    [ -n "$banner" ] || return 1
    echo "$banner" | grep -qi 'OpenSSH_for_Windows'
}

tunnel_port_has_local_reverse() {
    local target_port="$1"
    local p
    [ -n "$target_port" ] || return 1
    for p in $(get_local_tunnel_ssh_pids "$target_port" 2>/dev/null || true); do
        [ -n "$p" ] && return 0
    done
    return 1
}


tunnel_hostkey_fp() {
    local port="${1:-$PORT}"
    [ -n "$port" ] || return 1
    timeout 4 ssh-keyscan -p "$port" -T 3 -t ed25519,rsa,ecdsa 127.0.0.1 2>/dev/null \
        | ssh-keygen -lf - 2>/dev/null | awk '{print $2}' | head -1
}

get_stored_laptop_hostkey_fp() {
    [ -f "${CFG:-}" ] || return 1
    grep -E '^LAPTOP_HOSTKEY_FP=' "$CFG" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\r\n '
}

save_laptop_hostkey_fp() {
    local fp="$1"
    [ -n "$fp" ] || return 0
    [ -f "${CFG:-}" ] || return 0
    grep -vE '^LAPTOP_HOSTKEY_FP=' "$CFG" > "$CFG.tmp" 2>/dev/null && mv "$CFG.tmp" "$CFG"
    echo "LAPTOP_HOSTKEY_FP=$fp" >> "$CFG"
}

tunnel_hostkey_mismatch() {
    local port="${1:-$PORT}" stored fp
    stored="$(get_stored_laptop_hostkey_fp || true)"
    [ -n "$stored" ] || return 1
    fp="$(tunnel_hostkey_fp "$port" || true)"
    [ -n "$fp" ] || return 1
    [ "$fp" != "$stored" ]
}

tunnel_port_auth_owned() {
    local target_port="$1"
    [ -n "${LAPTOP_USER:-}" ] && [ -n "$target_port" ] || return 1
    sshx "touch \$HOME/.ssh/known_hosts_claude_acquire 2>/dev/null; chmod 600 \$HOME/.ssh/known_hosts_claude_acquire 2>/dev/null; timeout 6 ssh -o BatchMode=yes -o ConnectTimeout=3 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=\$HOME/.ssh/known_hosts_claude_acquire -i ~/.ssh/claude_laptop -p ${target_port} ${LAPTOP_USER}@127.0.0.1 true" >/dev/null 2>&1
}

# Foreign peer: server has a listen/banner but this Mac has no local -R and auth fails.
tunnel_port_is_foreign_peer() {
    local target_port="$1" banner="" saved_port="${PORT:-}"
    [ -n "$target_port" ] || return 1
    PORT=$target_port
    clear_tunnel_banner_cache
    banner="$(fetch_tunnel_banner 2>/dev/null || true)"
    if ! tunnel_port_tcp_open "$target_port" && ! tunnel_banner_is_windows "$banner"; then
        PORT=$saved_port
        return 1
    fi
    if tunnel_hostkey_mismatch "$target_port"; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "ACQUIRE_SKIP: foreign_peer hostkey port=$target_port" 'INFO'
        fi
        PORT=$saved_port
        return 0
    fi
    if tunnel_port_has_local_reverse "$target_port"; then
        PORT=$saved_port
        return 1
    fi
    if tunnel_port_auth_owned "$target_port"; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "TUNNEL_OWNERSHIP port=$target_port sticky_ours=1" 'DEBUG'
        fi
        PORT=$saved_port
        return 1
    fi
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "ACQUIRE_SKIP: foreign_peer port=$target_port banner=$banner" 'INFO'
    fi
    PORT=$saved_port
    return 0
}

# Non-overlapping 10-port block per user, instead of the old `20000 + uid + slot(0-9)`
# scheme. That old formula overlapped by up to 6 of 10 ports between any two users with
# adjacent UIDs - true for this whole team, since Ubuntu assigns sequential UIDs from 1000.
# That overlap was the entire reason the foreign-peer/hostkey-mismatch/auth-owned
# verification chain below is needed so often: a port could genuinely be ambiguous between
# two different users' ranges. With disjoint ranges a port outside your own block is
# unambiguously someone else's, and a port inside your own block that isn't yours locally is
# unambiguously your own stale zombie. The verification chain itself is left fully in place
# as defense-in-depth - this only fixes the formula that made it so frequently necessary.
tunnel_port_user_base() {
    local uid_str="$1" base="${CONNECT_PORT_BASE:-20000}" offset=0
    case "$uid_str" in
        ''|*[!0-9]*) echo "$base"; return ;;
    esac
    offset=$(( uid_str - 1000 ))
    [ "$offset" -lt 0 ] && offset=0
    echo $(( base + offset * 10 ))
}

acquire_tunnel_port() {
    local uid_str="$1" port_base slot=0 port="" banner="" preferred="" try_slots="" s
    port_base="$(tunnel_port_user_base "$uid_str")"
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "ACQUIRE_BEGIN uid=${uid_str:-?} port_base=${port_base:-?}" 'INFO'
    fi
    [ -n "$uid_str" ] || {
        declare -F connect_log >/dev/null 2>&1 && connect_log 'ACQUIRE_END port=0 outcome=no_uid' 'WARN'
        return 1
    }
    if [ -f "${CFG:-}" ]; then
        preferred="$(grep -E '^TUNNEL_SLOT=' "$CFG" 2>/dev/null | tail -1 | cut -d= -f2- | tr -dc '0-9')"
    fi
    try_slots=""
    if [ -n "$preferred" ] && [ "$preferred" -le 9 ] 2>/dev/null; then
        try_slots="$preferred"
    fi
    for s in $(seq 0 9); do
        [ "$s" = "$preferred" ] && continue
        try_slots="$try_slots $s"
    done
    for slot in $try_slots; do
        port=$(( port_base + slot ))
        [ "$port" -gt 65535 ] && continue
        if tunnel_port_is_foreign_peer "$port"; then
            continue
        fi
        PORT=$port
        clear_tunnel_banner_cache
        banner="$(fetch_tunnel_banner 2>/dev/null || true)"
        if [ -n "$banner" ] && ! tunnel_banner_is_this_laptop "$banner" && ! tunnel_banner_is_windows "$banner"; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "ACQUIRE_STALE: foreign_banner port=$port banner=$banner" 'DEBUG'
            fi
            clear_server_stale_tunnel_forward "$port" || true
            clear_tunnel_banner_cache
            banner="$(fetch_tunnel_banner 2>/dev/null || true)"
            if tunnel_port_is_foreign_peer "$port"; then
                continue
            fi
        fi
        if [ -z "$banner" ] && tunnel_port_tcp_open "$port"; then
            if tunnel_port_auth_owned "$port"; then
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "ACQUIRE_STALE: sticky_ours port=$port reclaim" 'DEBUG'
                fi
                clear_server_stale_tunnel_forward "$port" || true
                clear_tunnel_banner_cache
                banner="$(fetch_tunnel_banner 2>/dev/null || true)"
            elif tunnel_port_is_foreign_peer "$port"; then
                continue
            else
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "ACQUIRE_STALE: zombie port=$port tcp=open banner=(empty)" 'WARN'
                fi
                clear_server_stale_tunnel_forward "$port" || true
                clear_tunnel_banner_cache
                banner="$(fetch_tunnel_banner 2>/dev/null || true)"
            fi
            if tunnel_port_is_foreign_peer "$port"; then
                continue
            fi
            if [ -z "$banner" ] && tunnel_port_tcp_open "$port"; then
                continue
            fi
        fi
        if [ -z "$banner" ] || tunnel_banner_is_this_laptop "$banner"; then
            if [ -n "$banner" ] && ! tunnel_port_has_local_reverse "$port" && ! tunnel_port_auth_owned "$port"; then
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "ACQUIRE_SKIP: unauth_windows port=$port slot=$slot" 'INFO'
                fi
                continue
            fi
            TUNNEL_SLOT=$slot
            PORT=$port
            save_tunnel_slot
            push_server_connect_conf
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "ACQUIRE_END port=$PORT outcome=claim slot=$TUNNEL_SLOT" 'INFO'
            fi
            return 0
        fi
    done
    PORT=$port_base
    TUNNEL_SLOT=0
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "ACQUIRE_END port=$PORT outcome=fail" 'WARN'
    fi
    return 1
}
verify_laptop_reverse_ssh() {
    [ -n "${PORT:-}" ] && [ -n "${LAPTOP_USER:-}" ] || return 1
    tunnel_banner_is_this_laptop || return 1
    sshx "ssh-keygen -f \$HOME/.ssh/known_hosts -R '[127.0.0.1]:${PORT}' 2>/dev/null; ssh-keygen -f \$HOME/.ssh/known_hosts -R '127.0.0.1' 2>/dev/null; rm -f \$HOME/.ssh/known_hosts_claude_tunnel 2>/dev/null; touch \$HOME/.ssh/known_hosts_claude_tunnel; chmod 600 \$HOME/.ssh/known_hosts_claude_tunnel 2>/dev/null; timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=\$HOME/.ssh/known_hosts_claude_tunnel -i ~/.ssh/claude_laptop -p ${PORT} ${LAPTOP_USER}@127.0.0.1 true" >/dev/null 2>&1
}

wait_laptop_sshd() {
    local _i
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        nc -zw1 127.0.0.1 22 2>/dev/null && return 0
        sleep 1
    done
    return 1
}

restart_laptop_sshd() {
    [ "$(uname -s)" = "Darwin" ] || return 0
    run_mac_admin_cmd "launchctl kickstart -k system/com.openssh.sshd" || return 1
    wait_laptop_sshd
}

laptop_ssh_bootstrap_local() {
    local user="${LAPTOP_USER:-$(whoami)}" askpass="" rc=1
    read_laptop_admin_password || return 1
    askpass="$(mktemp "${TMPDIR:-/tmp}/claude-askpass.XXXXXX")"
    secref="$(mktemp "${TMPDIR:-/tmp}/claude-askpass-secret.XXXXXX")"
    umask 077
    # Password lives only in mode-600 secret file; askpass argv is "cat <file>" (no pw on cmdline).
    printf '%s\n' "$LAPTOP_ADMIN_PW" > "$secref"
    chmod 600 "$secref"
    {
        printf '#!/bin/sh\n'
        printf 'cat %q\n' "$secref"
    } > "$askpass"
    chmod 700 "$askpass"
    SSH_ASKPASS="$askpass" SSH_ASKPASS_REQUIRE=force \
        ssh -o BatchMode=no -o PreferredAuthentications=password,keyboard-interactive \
            -o PubkeyAuthentication=no -o StrictHostKeyChecking=accept-new \
            -o ConnectTimeout=10 -o NumberOfPasswordPrompts=1 \
            "${user}@127.0.0.1" true >/dev/null 2>&1
    rc=$?
    rm -f "$askpass" "$secref"
    [ "$rc" -eq 0 ]
}

invoke_laptop_admin_ops() {
    local pub="$1" firewall_fix="${2:-0}" user
    pub="$(printf '%s' "$pub" | tr -d '\r')"
    [ "$(uname -s)" = "Darwin" ] || return 1
    if [ -z "$pub" ] && [ "$firewall_fix" != "1" ]; then
        return 1
    fi
    user="${LAPTOP_USER:-$(whoami)}"

    warn "Fixing Mac SSH access for Mac user '${user}' (server user is '${REMOTE_USER:-?}'; password once)..."
    run_mac_admin_cmd "$(mac_ssh_clear_disabled_cmd "$user"); $(
        if [ "$firewall_fix" = "1" ]; then
            printf '%s' "/usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/sbin/sshd 2>/dev/null; /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /usr/sbin/sshd 2>/dev/null; "
        fi
    )launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true" || true
    wait_laptop_sshd || true

    if mac_ssh_access_blocked "$user"; then
        warn "STILL BLOCKED: '$user' is still in com.apple.access_ssh-disabled (password may have been wrong/cancelled)."
        warn "Fix once in Terminal, then press R:"
        warn "  sudo dseditgroup -o edit -d $(whoami) -t user com.apple.access_ssh-disabled"
        warn "Or Sharing > Remote Login > All users (UI name may be Full Name, e.g. Mohammad)."
    fi

    if [ -n "$pub" ]; then
        install_laptop_server_pubkey "$pub" || return 1
    fi
    if [ -n "$pub" ] && verify_laptop_local_pubkey "$pub"; then
        unset LAPTOP_ADMIN_PW
        return 0
    fi
    [ -z "$pub" ] && return 0

    warn "Retrying firewall + Remote Login allow list..."
    fix_laptop_ssh_firewall || true
    grant_laptop_ssh_access || true
    if mac_ssh_access_blocked "$user"; then
        warn "Allow-list still blocked after retry."
    fi
    install_laptop_server_pubkey "$pub" || return 1
    restart_laptop_sshd || true
    if verify_laptop_local_pubkey "$pub"; then
        unset LAPTOP_ADMIN_PW
        return 0
    fi

    if ! remote_login_on; then
        warn "Remote Login is off - enabling..."
        enable_remote_login || cycle_remote_login || true
        install_laptop_server_pubkey "$pub" || return 1
        if verify_laptop_local_pubkey "$pub"; then
            unset LAPTOP_ADMIN_PW
            return 0
        fi
    fi

    warn "Laptop SSH still not accepting the server key."
    warn "SSH uses Mac short name '${user}' (whoami). Server user is '${REMOTE_USER:-?}' (different)."
    _rn="$(mac_login_realname 2>/dev/null || true)"
    if mac_ssh_access_blocked "$user"; then
        warn "CONFIRMED: id shows com.apple.access_ssh-disabled for '${user}'."
        warn "  sudo dseditgroup -o edit -d ${user} -t user com.apple.access_ssh-disabled"
    elif [ -n "${_rn}" ] && [ "${_rn}" != "${user}" ]; then
        warn "In System Settings the name may look like '${_rn}' - allow THAT row (or All users)."
    else
        warn "System Settings -> Sharing -> Remote Login: ON, allow '${user}' or All users."
    fi
    diagnose_laptop_ssh_failure "$pub" || true
    unset LAPTOP_ADMIN_PW
    return 1
}

ensure_laptop_ssh_key() {
    local pub=""
    pub="$(fetch_laptop_server_pubkey "${1:-}")" || return 1
    install_laptop_server_pubkey "$pub" || return 1
    verify_laptop_local_pubkey "$pub" && return 0
    warn "Server cannot SSH back to this Mac yet - fixing (password at most once)..."
    if ! invoke_laptop_admin_ops "$pub"; then
        # diagnose already run inside invoke on failure
        return 1
    fi
    verify_laptop_local_pubkey "$pub" && return 0
    diagnose_laptop_ssh_failure "$pub" || true
    return 1
}

ensure_laptop_reverse_ssh() {
    local pub=""
    pub="$(fetch_laptop_server_pubkey "${1:-}")" || return 1
    if ! ensure_laptop_ssh_key "$pub"; then
        return 2
    fi
    if verify_laptop_reverse_ssh; then
        return 0
    fi
    uid_str="$(sshx 'id -u' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+$' | head -1 | tr -dc '0-9')"
    if [ -n "$uid_str" ] && acquire_tunnel_port "$uid_str"; then
        verify_laptop_reverse_ssh && return 0
    fi
    release_stale_tunnel_port || true
    restart_laptop_sshd 2>/dev/null || true
    verify_laptop_reverse_ssh && return 0
    return 1
}

warn_foreign_server_session() {
    # Return 1 when user aborts a likely wrong-account takeover.
    # Self-heal: if another laptop left a conf but its reverse tunnel is down,
    # clear the stale file and continue (no prompt).
    local existing_lu existing_os existing_port choice this_os="${GIT_MODE_LAPTOP_OS:-}" live=0
    existing_lu="$(sshx "grep -E '^LAPTOP_USER=' \$HOME/.claude-connect.conf 2>/dev/null | tail -1 | cut -d= -f2-" 2>/dev/null | tr -d '\r\n' || true)"
    existing_os="$(sshx "grep -E '^LAPTOP_OS=' \$HOME/.claude-connect.conf 2>/dev/null | tail -1 | cut -d= -f2-" 2>/dev/null | tr -d '\r\n' || true)"
    existing_port="$(sshx "grep -E '^TUNNEL_PORT=' \$HOME/.claude-connect.conf 2>/dev/null | tail -1 | cut -d= -f2-" 2>/dev/null | tr -d '\r\n' || true)"
    case "${existing_lu}" in
      ''|*"bash:"*|*"unexpected EOF"*|*"syntax error"*) return 0 ;;
    esac
    [ -n "${existing_lu:-}" ] || return 0
    [ "${existing_lu}" = "${LAPTOP_USER:-}" ] && return 0

    existing_port="$(printf '%s' "$existing_port" | tr -dc '0-9')"
    ss_ok=0
    if [ -n "$existing_port" ]; then
        live_raw="$(sshx "ss -ltn 2>/dev/null | grep -cE ':${existing_port}[[:space:]]' || echo SS_UNKNOWN" 2>/dev/null | tr -d '\r\n')"
        if printf '%s' "$live_raw" | grep -Eq '^[0-9]+$'; then
            live="$live_raw"
            ss_ok=1
        else
            live=0
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "SS:UNKNOWN port=$existing_port raw=$live_raw - not clearing connect conf" 'WARN'
            fi
        fi
    fi
    # Only auto-clear when ss positively reports zero listeners (or no port in conf).
    if [ -z "$existing_port" ] || { [ "$ss_ok" = "1" ] && [ "${live:-0}" = "0" ]; }; then
        warn "Cleared stale session from laptop '${existing_lu}' (no active tunnel)."
        sshx "rm -f \$HOME/.claude-connect.conf" 2>/dev/null || true
        return 0
    fi
    if [ "$ss_ok" != "1" ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "FOREIGN_SESSION ss_ambiguous port=$existing_port - prompting" 'WARN'
        fi
    fi

    warn "Server account '${REMOTE_USER:-?}' is already used by laptop '${existing_lu}'${existing_os:+ ($existing_os)} (tunnel active)."
    warn "Your laptop user is '${LAPTOP_USER:-unknown}'. Taking over will disconnect them."

    if [ -n "${existing_os:-}" ] && [ -n "${this_os:-}" ] && [ "$existing_os" != "$this_os" ]; then
        warn "OS mismatch ($existing_os vs $this_os) - confirm this is your server account."
    fi
    printf '    Continue and take over that session? [y/N]: '
    read -r choice </dev/tty 2>/dev/null || read -r choice || choice=""
    choice="$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')"
    if [ "$choice" != "y" ] && [ "$choice" != "yes" ]; then
        warn "Aborted. Fix username with: bash connect.sh --setup"
        return 1
    fi
    return 0
}

initialize_server_session() {
    local script_dir="$1"
    local port_base="${CONNECT_PORT_BASE:-20000}"
    local port_min="$port_base" _init uid_str pub_b server_dir
    local src="" git_src="" push_ok=1 _chmod
    local mount_pid="" git_pid="" mount_pushed=0 git_pushed=0
    INIT_SERVER_SESSION_ERROR=""

    # Use -N '' (single quotes): -N "" inside this double-quoted sshx collapses to bare -N,
    # so ssh-keygen sees -f as passphrase and fails with "Too many arguments" / empty pub key.
    _init="$(sshx "id -u && (test -f \$HOME/.ssh/claude_laptop || ssh-keygen -t ed25519 -N '' -f \$HOME/.ssh/claude_laptop -q) && cat \$HOME/.ssh/claude_laptop.pub" 2>/dev/null)"
    uid_str="$(printf '%s\n' "$_init" | tr -d '\r' | grep -E '^[0-9]+$' | head -1 | tr -dc '0-9')"
    pub_b="$(printf '%s\n' "$_init" | tr -d '\r' | grep '^ssh-' | head -1)"
    if [ -z "$uid_str" ]; then
        INIT_SERVER_SESSION_ERROR="could not get UID from server"
        if declare -F connect_log >/dev/null 2>&1; then connect_log "INIT_SERVER_SESSION fail=$INIT_SERVER_SESSION_ERROR" 'ERROR'; fi
        return 1
    fi
    if [ -z "$pub_b" ]; then
        INIT_SERVER_SESSION_ERROR="could not read server key"
        if declare -F connect_log >/dev/null 2>&1; then connect_log "INIT_SERVER_SESSION fail=$INIT_SERVER_SESSION_ERROR" 'ERROR'; fi
        return 1
    fi
    if ! acquire_tunnel_port "$uid_str"; then
        PORT="$(tunnel_port_user_base "$uid_str")"
        TUNNEL_SLOT=0
    fi
    if [ -z "${PORT:-}" ] || [ "$PORT" -le "$port_min" ] || [ "$PORT" -gt 65535 ]; then
        INIT_SERVER_SESSION_ERROR="invalid tunnel port (${PORT:-unset})"
        if declare -F connect_log >/dev/null 2>&1; then connect_log "INIT_SERVER_SESSION fail=$INIT_SERVER_SESSION_ERROR" 'ERROR'; fi
        return 1
    fi
    PUB_B="$pub_b"

    server_dir="$(resolve_server_script_dir "$script_dir" 2>/dev/null || true)"
    # Bundle layout: claude-mount.sh may live next to connect.sh (mac/)
    if [ -z "$server_dir" ] && [ -f "$script_dir/claude-mount.sh" ]; then
        server_dir="$script_dir"
    fi
    if [ -n "$server_dir" ]; then
        [ -f "$server_dir/claude-mount.sh" ] && src="$server_dir/claude-mount.sh"
        [ -f "$server_dir/claude-git-setup.sh" ] && git_src="$server_dir/claude-git-setup.sh"
        sshx "mkdir -p \$HOME/.local/bin" >/dev/null 2>&1 || true
        # claude-mount/claude-git-setup are live-executed (claude-watchdog polls
        # claude-mount every 30s server-side) - scp to a .new sibling below and mv
        # atomically into place once finished, so a concurrent exec never tears it.
        if [ -n "$src" ]; then
            local local_h remote_h
            local_h="$(local_file_sha256 "$src" 2>/dev/null || true)"
            remote_h="$(remote_claude_mount_sha256 2>/dev/null || true)"
            if [ -z "$local_h" ] || [ "$local_h" != "$remote_h" ]; then
                scp -o BatchMode=yes -o ConnectTimeout=30 -q "$src" "$ALIAS:~/.local/bin/claude-mount.new" &
                mount_pid=$!
            fi
        fi
        if [ -n "$git_src" ]; then
            local git_local git_remote
            git_local="$(local_file_sha256 "$git_src" 2>/dev/null || true)"
            git_remote="$(sshx "sha256sum \$HOME/.local/bin/claude-git-setup 2>/dev/null | awk '{print \$1}'" 2>/dev/null | tr -d '\r\n')"
            if [ -z "$git_local" ] || [ "$git_local" != "$git_remote" ]; then
                scp -o BatchMode=yes -o ConnectTimeout=30 -q "$git_src" "$ALIAS:~/.local/bin/claude-git-setup.new" &
                git_pid=$!
            fi
        fi
        push_laptop_exec_bundle "$server_dir"
    fi

    if ! install_laptop_server_pubkey "$pub_b"; then
        INIT_SERVER_SESSION_ERROR="laptop SSH key setup failed"
        if declare -F connect_log >/dev/null 2>&1; then connect_log "INIT_SERVER_SESSION fail=$INIT_SERVER_SESSION_ERROR" 'ERROR'; fi
        return 1
    fi

    awk -v a="$ALIAS" '
        /^[[:space:]]*Host[[:space:]]+/ { skip=0; for(i=2;i<=NF;i++) if($i==a) skip=1 }
        !skip
    ' "$HOME/.ssh/config" > "$HOME/.ssh/config.tmp.${ALIAS}" 2>/dev/null \
        && mv "$HOME/.ssh/config.tmp.${ALIAS}" "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
    cat >> "$HOME/.ssh/config" <<EOF

Host $ALIAS
    HostName $SERVER_IP
    User $REMOTE_USER
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
EOF
    sanitize_ssh_alias_config
    push_server_connect_conf

    if [ -n "$mount_pid" ]; then
        if wait_pid_timeout "$mount_pid" server_scripts 30; then
            mount_pushed=1
        else
            push_ok=0
            warn "server script push failed (continuing; server already has scripts)"
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "SCP: server_scripts failed (non-fatal)" 'WARN'
            fi
        fi
    fi
    if [ -n "$git_pid" ]; then
        if wait_pid_timeout "$git_pid" server_scripts 30; then
            git_pushed=1
        else
            push_ok=0
            warn "server script push failed (continuing; server already has scripts)"
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "SCP: server_scripts failed (non-fatal)" 'WARN'
            fi
        fi
    fi
    # Finalize each .new file (chmod) then mv atomically onto the live path as the
    # last step, so a concurrently-executing claude-mount/claude-git-setup never
    # observes a partially-written file (claude-watchdog polls claude-mount every 30s).
    if [ -n "$server_dir" ] && { [ "$mount_pushed" = "1" ] || [ -n "$src" ] || [ "$git_pushed" = "1" ]; }; then
        _chmod=""
        [ "$mount_pushed" = "1" ] && _chmod="chmod +x \$HOME/.local/bin/claude-mount.new && mv -f \$HOME/.local/bin/claude-mount.new \$HOME/.local/bin/claude-mount"
        [ -n "$src" ] && _chmod="${_chmod:+"$_chmod; "}grep -q 'CLAUDE_LOCAL_BIN_PATH' \$HOME/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=\$HOME/.local/bin:\$PATH\n' >> \$HOME/.bashrc"
        [ "$git_pushed" = "1" ] && _chmod="${_chmod:+"$_chmod; "}chmod +x \$HOME/.local/bin/claude-git-setup.new && mv -f \$HOME/.local/bin/claude-git-setup.new \$HOME/.local/bin/claude-git-setup"
        [ -n "$_chmod" ] && sshx "$_chmod" 2>/dev/null || true
    fi

    # Match Windows: script push failure must not abort connect (port/key already OK).
    return 0
}

_connect_slot_marker_dir() {
    if [ -n "${CFG_DIR:-}" ]; then printf '%s' "$CFG_DIR"; else printf '%s' "$HOME/.config/claude-connect"; fi
}

write_connect_session_slot_marker() {
    local slot="${1:-0}" port="${2:-0}" project_id="${3:-}" remote_path="${4:-}" pid="${5:-$$}"
    local dir path
    dir="$(_connect_slot_marker_dir)"
    mkdir -p "$dir" 2>/dev/null || true
    path="$dir/session-slot-${slot}.json"
    printf '{"pid":%s,"slot":%s,"port":%s,"projectId":"%s","remotePath":"%s","updated":"%s"}\n' \
        "$pid" "$slot" "$port" \
        "$(printf '%s' "$project_id" | tr -d '"')" \
        "$(printf '%s' "$remote_path" | tr -d '"')" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$path" 2>/dev/null || true
}

clear_connect_session_slot_marker() {
    local slot="${1:-${CLAUDE_CONNECT_UI_SLOT:-}}"
    [ -n "$slot" ] || return 0
    rm -f "$(_connect_slot_marker_dir)/session-slot-${slot}.json" 2>/dev/null || true
}

_connect_keep_tunnel_marker_path() {
    local port="$1"
    printf '%s/keep-tunnel-%s.json' "$(_connect_slot_marker_dir)" "$port"
}

write_connect_keep_tunnel_marker() {
    # Args: port slot tunnel_pid project_id remote_path [alias] [editor_cmd]
    local port="${1:-0}" slot="${2:--1}" tunnel_pid="${3:-0}"
    local project_id="${4:-}" remote_path="${5:-}" alias="${6:-}" editor_cmd="${7:-}"
    local dir path tmp kept_at
    case "$port" in ''|*[!0-9]*|0) return 1 ;; esac
    dir="$(_connect_slot_marker_dir)"
    mkdir -p "$dir" 2>/dev/null || true
    path="$(_connect_keep_tunnel_marker_path "$port")"
    kept_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    tmp="${path}.write.$$.$RANDOM.tmp"
    if ! printf '{"port":%s,"slot":%s,"tunnelPid":%s,"projectId":"%s","remotePath":"%s","alias":"%s","editorCmd":"%s","keptAt":"%s"}\n' \
        "$port" "$slot" "$tunnel_pid" \
        "$(printf '%s' "$project_id" | tr -d '"')" \
        "$(printf '%s' "$remote_path" | tr -d '"')" \
        "$(printf '%s' "$alias" | tr -d '"')" \
        "$(printf '%s' "$editor_cmd" | tr -d '"')" \
        "$kept_at" > "$tmp" 2>/dev/null; then
        rm -f "$tmp" 2>/dev/null || true
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "KEEP_MARKER_WRITE_FAIL port=$port err=write" 'WARN'
        fi
        return 1
    fi
    if mv -f "$tmp" "$path" 2>/dev/null; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "KEEP_MARKER_WRITE port=$port slot=$slot tunnelPid=$tunnel_pid projectId=$project_id" 'INFO'
        fi
        return 0
    fi
    rm -f "$tmp" 2>/dev/null || true
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "KEEP_MARKER_WRITE_FAIL port=$port err=mv" 'WARN'
    fi
    return 1
}

clear_connect_keep_tunnel_marker() {
    local port="${1:-0}" dir f
    if [ -n "$port" ] && [ "$port" != "0" ]; then
        case "$port" in *[!0-9]*) return 0 ;; esac
        f="$(_connect_keep_tunnel_marker_path "$port")"
        if [ -f "$f" ]; then
            rm -f "$f" 2>/dev/null || true
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "KEEP_MARKER_CLEAR port=$port" 'INFO'
            fi
        fi
        return 0
    fi
    dir="$(_connect_slot_marker_dir)"
    [ -d "$dir" ] || return 0
    for f in "$dir"/keep-tunnel-*.json; do
        [ -f "$f" ] || continue
        rm -f "$f" 2>/dev/null || true
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "KEEP_MARKER_CLEAR file=$(basename "$f")" 'INFO'
        fi
    done
}

get_connect_keep_tunnel_markers() {
    # Print live markers as: port|slot|tunnelPid|projectId|remotePath|alias|editorCmd|keptAt
    # Dead tunnelPid markers are dropped (KEEP_MARKER_CLEAR reason=dead_tunnelPid).
    local dir f port slot tunnel_pid project_id remote_path alias editor_cmd kept_at raw
    dir="$(_connect_slot_marker_dir)"
    [ -d "$dir" ] || return 0
    for f in "$dir"/keep-tunnel-*.json; do
        [ -f "$f" ] || continue
        raw="$(cat "$f" 2>/dev/null || true)"
        [ -n "$raw" ] || continue
        port="$(printf '%s' "$raw" | sed -n 's/.*"port":[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)"
        tunnel_pid="$(printf '%s' "$raw" | sed -n 's/.*"tunnelPid":[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)"
        slot="$(printf '%s' "$raw" | sed -n 's/.*"slot":[[:space:]]*\(-\?[0-9][0-9]*\).*/\1/p' | head -1)"
        project_id="$(printf '%s' "$raw" | sed -n 's/.*"projectId":"\([^"]*\)".*/\1/p' | head -1)"
        remote_path="$(printf '%s' "$raw" | sed -n 's/.*"remotePath":"\([^"]*\)".*/\1/p' | head -1)"
        alias="$(printf '%s' "$raw" | sed -n 's/.*"alias":"\([^"]*\)".*/\1/p' | head -1)"
        editor_cmd="$(printf '%s' "$raw" | sed -n 's/.*"editorCmd":"\([^"]*\)".*/\1/p' | head -1)"
        kept_at="$(printf '%s' "$raw" | sed -n 's/.*"keptAt":"\([^"]*\)".*/\1/p' | head -1)"
        [ -n "$port" ] || continue
        [ -n "$tunnel_pid" ] || tunnel_pid=0
        [ -n "$slot" ] || slot=-1
        if [ "$tunnel_pid" -gt 0 ] 2>/dev/null && kill -0 "$tunnel_pid" 2>/dev/null; then
            printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
                "$port" "$slot" "$tunnel_pid" "$project_id" "$remote_path" "$alias" "$editor_cmd" "$kept_at"
        else
            rm -f "$f" 2>/dev/null || true
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "KEEP_MARKER_CLEAR port=$port reason=dead_tunnelPid pid=$tunnel_pid" 'INFO'
            fi
        fi
    done
}

test_connect_keep_editor_protect() {
    # Folder/window check for KEEP Soft/reclaim protect. Sticky <=15m only when checks unavailable
    # (Win catch/sticky path) — not when checks return false (editor closed).
    # Args: remote_path project_id [kept_at] [alias] [has_marker=1]
    local remote_path="${1:-}" project_id="${2:-}" kept_at="${3:-}" alias_use="${4:-claude-server}" has_marker="${5:-1}"
    local checked=0 age_min now_ts kept_ts
    [ -n "$alias_use" ] || alias_use="claude-server"
    if [ -n "$remote_path" ] && declare -F remote_editor_window_open >/dev/null 2>&1; then
        checked=1
        if remote_editor_window_open cursor "$alias_use" "$remote_path" 2>/dev/null; then
            return 0
        fi
    fi
    if [ -n "$remote_path" ] && declare -F remote_editor_on_correct_folder >/dev/null 2>&1; then
        checked=1
        if remote_editor_on_correct_folder cursor "$alias_use" "$remote_path" 2>/dev/null; then
            return 0
        fi
    fi
    if [ "$checked" -eq 1 ]; then
        return 1
    fi
    # No editor helpers available: sticky protect when marker present and keptAt within 15m.
    if [ "$has_marker" = "1" ]; then
        if [ -n "$kept_at" ]; then
            now_ts="$(date +%s 2>/dev/null || printf '0')"
            kept_ts="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$kept_at" +%s 2>/dev/null || date -d "$kept_at" +%s 2>/dev/null || printf '0')"
            if [ "$now_ts" != "0" ] && [ "$kept_ts" != "0" ]; then
                age_min=$(( (now_ts - kept_ts) / 60 ))
                if [ "$age_min" -ge 0 ] && [ "$age_min" -le 15 ]; then
                    if declare -F connect_log >/dev/null 2>&1; then
                        connect_log "KEEP_PROTECT sticky=1 age_min=$age_min reason=check_unavailable path=$remote_path" 'WARN'
                    fi
                    return 0
                fi
            fi
        else
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "KEEP_PROTECT sticky=1 reason=check_unavailable_no_keptAt path=$remote_path" 'WARN'
            fi
            return 0
        fi
    fi
    return 1
}

invoke_connect_mount_down_by_port() {
    # Soft/reclaim: down ALL sshfs mounts bound to Port P. Fail-open if remote helper missing.
    local port="$1" cm out one
    case "$port" in ''|*[!0-9]*|0) return 0 ;; esac
    if ! declare -F sshx >/dev/null 2>&1; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "HYGIENE_SOFT_DOWN_BY_PORT skip port=$port reason=no_sshx" 'WARN'
        fi
        return 0
    fi
    cm="${CM:-\$HOME/.local/bin/claude-mount}"
    out="$(sshx "timeout 20 $cm down-by-port $port 2>&1 || true" 2>/dev/null || true)"
    one="$(printf '%s' "$out" | tr '\n' ' ' | sed 's/[[:space:]]\{1,\}/ /g' | cut -c1-160)"
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "HYGIENE_SOFT_DOWN_BY_PORT port=$port out=$one" 'INFO'
    fi
}

invoke_connect_mount_down_dead_bound_ports() {
    # Soft mount-only litter: sshfs still bound to -p but TCP listener on that port is dead
    # (local -R already gone). Never tear mounts whose -p is still listening / protect list.
    # Arg1: optional space-separated protect ports (session PORT / still-listening).
    # Same remote logic as Win Invoke-ConnectMountDownDeadBoundPorts.
    local protect_list="${1:-}" cm out ln remote
    if ! declare -F sshx >/dev/null 2>&1; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log 'HYGIENE_SOFT_DEAD_BOUND skip reason=no_sshx' 'WARN'
        fi
        return 0
    fi
    cm="${CM:-\$HOME/.local/bin/claude-mount}"
    # shellcheck disable=SC2086,SC2016
    remote="set +e
CM='$cm'
PROTECT='$protect_list'
downed=0
seen=''
for pid in \$(pgrep -u \"\$(id -un)\" -f '[s]shfs' 2>/dev/null); do
  [ -r /proc/\$pid/cmdline ] || continue
  cmd=\$(tr '\\0' ' ' < /proc/\$pid/cmdline 2>/dev/null)
  p=\$(printf '%s' \"\$cmd\" | sed -n 's/.* -p \\([0-9][0-9]*\\).*/\\1/p; t; s/.* -p\\([0-9][0-9]*\\).*/\\1/p')
  [ -n \"\$p\" ] || continue
  case \" \$seen \" in *\" \$p \"*) continue ;; esac
  seen=\"\$seen \$p\"
  skip=0
  for pp in \$PROTECT; do
    [ \"\$pp\" = \"\$p\" ] && skip=1 && break
  done
  [ \"\$skip\" = \"1\" ] && continue
  if timeout 2 bash -c \"exec 3<>/dev/tcp/127.0.0.1/\$p\" 2>/dev/null; then
    continue
  fi
  echo \"HYGIENE_SOFT_DEAD_BOUND port=\$p\"
  timeout 20 \$CM down-by-port \$p 2>&1 || true
  downed=\$((downed + 1))
done
echo \"HYGIENE_SOFT_DEAD_BOUND_DONE n=\$downed\""
    out="$(sshx "$remote" 2>/dev/null || true)"
    while IFS= read -r ln; do
        [ -n "$ln" ] || continue
        case "$ln" in
            *HYGIENE_SOFT_DEAD_BOUND*)
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "$ln" 'INFO'
                fi
                ;;
        esac
    done <<EOF
$(printf '%s\n' "$out")
EOF
}

invoke_connect_orphan_reclaim() {
    # Scan UID base+0..9; skip current/sibling; pin preferred Port if keep marker live.
    # Args: uid_str [preferred_port] [protect_remote_path] [protect_project_id]
    local uid_str="${1:-}" preferred_port="${2:-0}" protect_path="${3:-}" protect_project="${4:-}"
    local port_base=20000 slot port killed=0 skipped_sib=0 skipped_keep=0 down_mounts=0
    local protect="" siblings="" line km_port km_slot km_tpid km_proj km_path km_alias km_ed km_kept
    local ssh_pids p killed_here keep_protect port_keeps

    if [ "${CLAUDE_CONNECT_AUTO_RECLAIM:-}" = "0" ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log 'RECLAIM_SKIP reason=AUTO_RECLAIM=0' 'INFO'
        fi
        return 0
    fi
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log 'RECLAIM_BEGIN' 'INFO'
    fi
    if [ -n "$uid_str" ] && declare -F tunnel_port_user_base >/dev/null 2>&1; then
        port_base="$(tunnel_port_user_base "$uid_str")"
    fi
    protect="$$"
    if [ -n "${bg_pid:-}" ] && kill -0 "$bg_pid" 2>/dev/null; then
        protect="$protect $bg_pid"
    fi

    # Pin preferred Port when keep marker is live (even if editor check is false).
    if [ -n "$preferred_port" ] && [ "$preferred_port" != "0" ]; then
        while IFS='|' read -r km_port km_slot km_tpid km_proj km_path km_alias km_ed km_kept; do
            [ "$km_port" = "$preferred_port" ] || continue
            if [ -n "$km_tpid" ] && [ "$km_tpid" -gt 0 ] 2>/dev/null; then
                protect="$protect $km_tpid"
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "RECLAIM_PIN preferred_port=$preferred_port tunnelPid=$km_tpid" 'INFO'
                fi
            fi
            break
        done < <(get_connect_keep_tunnel_markers 2>/dev/null || true)
    fi

    for slot in 0 1 2 3 4 5 6 7 8 9; do
        port=$((port_base + slot))
        [ "$port" -gt 20000 ] 2>/dev/null && [ "$port" -le 65535 ] 2>/dev/null || continue
        ssh_pids="$(get_local_tunnel_ssh_pids "$port" 2>/dev/null | tr '\n' ' ')"
        ssh_pids="$(printf '%s' "$ssh_pids" | sed 's/[[:space:]]*$//')"
        [ -n "$ssh_pids" ] || continue

        siblings="$(get_sibling_connect_tunnel_pids "$port" "$protect" 2>/dev/null | tr '\n' ' ')"
        siblings="$(printf '%s' "$siblings" | sed 's/[[:space:]]*$//')"
        [ -n "$siblings" ] && protect="$protect $siblings"

        keep_protect=0
        port_keeps=0
        while IFS='|' read -r km_port km_slot km_tpid km_proj km_path km_alias km_ed km_kept; do
            [ "$km_port" = "$port" ] || continue
            port_keeps=1
            if [ -n "$preferred_port" ] && [ "$preferred_port" != "0" ] && [ "$port" = "$preferred_port" ]; then
                keep_protect=1
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "RECLAIM_SKIP_KEEP port=$port reason=preferred_pin" 'INFO'
                fi
                break
            fi
            if test_connect_keep_editor_protect "$km_path" "$km_proj" "$km_kept" "${km_alias:-claude-server}" 1; then
                keep_protect=1
                [ -n "$km_tpid" ] && protect="$protect $km_tpid"
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "RECLAIM_SKIP_KEEP port=$port reason=keep_editor project=$km_proj" 'INFO'
                fi
                break
            fi
        done < <(get_connect_keep_tunnel_markers 2>/dev/null || true)
        if [ "$keep_protect" -eq 1 ]; then
            skipped_keep=$((skipped_keep + 1))
            continue
        fi

        killed_here=0
        for p in $ssh_pids; do
            case " $protect " in
                *" $p "*)
                    case " $siblings " in *" $p "*) skipped_sib=$((skipped_sib + 1)) ;; esac
                    continue
                    ;;
            esac
            if kill -0 "$p" 2>/dev/null; then
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "RECLAIM_KILL port=$port pid=$p" 'INFO'
                fi
                kill "$p" 2>/dev/null || true
                killed_here=$((killed_here + 1))
            fi
        done
        if [ "$killed_here" -gt 0 ]; then
            killed=$((killed + killed_here))
            clear_connect_keep_tunnel_marker "$port" || true
            invoke_connect_mount_down_by_port "$port" || true
            down_mounts=$((down_mounts + 1))
        fi
    done
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "RECLAIM_END killed=$killed skipped_sibling=$skipped_sib skipped_keep=$skipped_keep down_mounts=$down_mounts" 'INFO'
    fi
}

_close_cursor_project_windows_mac() {
    # Best-effort: close Cursor windows whose name contains project root; skip protect root.
    local root="$1" protect="${2:-}"
    [ -n "$root" ] || return 0
    if [ -n "$protect" ] && [ "$root" = "$protect" ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "HYGIENE_SIBLING_CURSOR_SKIP root=$root reason=protect_current" 'WARN'
        fi
        return 0
    fi
    osascript >/dev/null 2>&1 <<EOF || true
tell application "System Events"
  if not (exists process "Cursor") then return
  tell process "Cursor"
    set wins to every window
    repeat with w in wins
      try
        set t to name of w as text
        if t contains "$root" then
          if "$protect" is "" or t does not contain "$protect" then
            try
              click button 1 of w
            end try
          end if
        end if
      end try
    end repeat
  end tell
end tell
EOF
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "HYGIENE_SIBLING_CURSOR_WINDOW root=$root" 'INFO'
    fi
}

show_connect_hygiene_interactive() {
    local uid_str="${1:-}" protect_path="${2:-}" protect_project="${3:-}"
    local port_base=20000 slot port p protect_root="" orphans=0 siblings=0
    local -a sib_ports=() sib_pids=() sib_projects=()
    if declare -F connect_log >/dev/null 2>&1; then connect_log 'HYGIENE_SCAN begin' 'INFO'; fi
    if [ -n "$uid_str" ] && declare -F tunnel_port_user_base >/dev/null 2>&1; then
        port_base="$(tunnel_port_user_base "$uid_str")"
    fi
    if [ -n "$protect_path" ]; then
        protect_root="$(basename "$protect_path")"
    elif [ -n "$protect_project" ]; then
        protect_root="$protect_project"
    fi
    echo ""
    printf '    \033[0;36mHygiene scan\033[0m\n'
    for slot in 0 1 2 3 4 5 6 7 8 9; do
        port=$((port_base + slot))
        for p in $(get_local_tunnel_ssh_pids "$port" 2>/dev/null || true); do
            if [ -n "${bg_pid:-}" ] && [ "$p" = "$bg_pid" ]; then
                printf '      [current] port=%s tunnel=%s\n' "$port" "$p"
                continue
            fi
            # Heuristic: if parent tree includes connect.sh and not us -> sibling
            if ps -p "$p" -o command= 2>/dev/null | grep -q .; then
                local pp="$p" hops=0 is_sib=0
                while [ "$pp" -gt 1 ] && [ "$hops" -lt 12 ]; do
                    hops=$((hops + 1))
                    local cmd
                    cmd="$(ps -p "$pp" -o command= 2>/dev/null || true)"
                    if printf '%s' "$cmd" | grep -qE 'connect\.sh|connect-boot'; then
                        if [ "$pp" != "$$" ]; then is_sib=1; fi
                        break
                    fi
                    pp="$(ps -p "$pp" -o ppid= 2>/dev/null | tr -d ' ')"
                    [ -n "$pp" ] || break
                done
                if [ "$is_sib" -eq 1 ]; then
                    siblings=$((siblings + 1))
                    sib_ports+=("$port")
                    sib_pids+=("$p")
                    local proj="?"
                    if [ -f "$(_connect_slot_marker_dir)/session-slot-${slot}.json" ]; then
                        proj="$(sed -n 's/.*"projectId":"\([^"]*\)".*/\1/p' "$(_connect_slot_marker_dir)/session-slot-${slot}.json" | head -1)"
                        [ -n "$proj" ] || proj="?"
                    fi
                    sib_projects+=("$proj")
                    printf '      [sibling] port=%s tunnel=%s project=%s\n' "$port" "$p" "$proj"
                else
                    orphans=$((orphans + 1))
                    printf '      [orphan]  port=%s tunnel=%s\n' "$port" "$p"
                fi
            fi
        done
    done
    printf '    Orphan tunnels : %s\n' "$orphans"
    printf '    Sibling Connect: %s\n' "$siblings"
    echo ""
    if [ "$orphans" -le 0 ] && [ "$siblings" -le 0 ]; then
        printf '    \033[0;32mNothing to clean.\033[0m\n\n'
        return 0
    fi
    local ans=""
    if declare -F connect_prompt >/dev/null 2>&1; then
        ans="$(connect_prompt "    Soft-clean orphans/idle? [Y/N] " "HYGIENE_SOFT")"
    else
        read -rp "    Soft-clean orphans/idle? [Y/N] " ans || true
    fi
    ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
    if [ "$ans" != "y" ] && [ "$ans" != "yes" ]; then
        printf '    \033[0;90mCancelled.\033[0m\n\n'
        return 0
    fi
    if declare -F connect_log >/dev/null 2>&1; then connect_log 'HYGIENE_SOFT begin' 'INFO'; fi
    local before_n after_n killed_n skip_protect hint_id km_port km_slot km_tpid km_proj km_path km_alias km_ed km_kept orphans_killed=0 port_keeps_n
    for slot in 0 1 2 3 4 5 6 7 8 9; do
        port=$((port_base + slot))
        before_n=0
        for p in $(get_local_tunnel_ssh_pids "$port" 2>/dev/null || true); do
            before_n=$((before_n + 1))
        done

        skip_protect=0
        hint_id=""
        port_keeps_n=0
        while IFS='|' read -r km_port km_slot km_tpid km_proj km_path km_alias km_ed km_kept; do
            [ "$km_port" = "$port" ] || continue
            port_keeps_n=$((port_keeps_n + 1))
            [ -n "$hint_id" ] || hint_id="$km_proj"
            if test_connect_keep_editor_protect "$km_path" "$km_proj" "$km_kept" "${km_alias:-claude-server}" 1; then
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "HYGIENE_SOFT_PORT port=$port action=skip reason=keep_editor project=$km_proj" 'INFO'
                    connect_log "PROTECT_ROOT path=$km_path hit=1 sticky=0" 'INFO'
                fi
                skip_protect=1
                break
            fi
        done < <(get_connect_keep_tunnel_markers 2>/dev/null || true)
        if [ "$skip_protect" -eq 0 ] && [ -n "$protect_root" ]; then
            # protect_root from current session path/project — skip if editor still holds it.
            if test_connect_keep_editor_protect "$protect_path" "$protect_project" "" "claude-server" 0; then
                local root_match=""
                root_match="$(basename "${protect_path%/}")"
                [ -n "$root_match" ] || root_match="$protect_project"
                if [ -n "$root_match" ] && [ "$root_match" = "$protect_root" ]; then
                    if declare -F connect_log >/dev/null 2>&1; then
                        connect_log "HYGIENE_SOFT_PORT port=$port action=skip reason=protect_root root=$protect_root" 'INFO'
                    fi
                    # Only skip when this port's tunnels look tied to protect project via slot marker.
                    if [ -f "$(_connect_slot_marker_dir)/session-slot-${slot}.json" ]; then
                        local slot_proj
                        slot_proj="$(sed -n 's/.*"projectId":"\([^"]*\)".*/\1/p' "$(_connect_slot_marker_dir)/session-slot-${slot}.json" | head -1)"
                        if [ "$slot_proj" = "$protect_project" ] || [ "$slot_proj" = "$protect_root" ]; then
                            skip_protect=1
                        fi
                    fi
                fi
            fi
        fi
        if [ "$skip_protect" -eq 1 ]; then
            continue
        fi

        # Mount-only litter: no local -R left but keep marker still present → clear + down-by-port.
        if [ "$before_n" -eq 0 ]; then
            if [ "$port_keeps_n" -gt 0 ]; then
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "HYGIENE_SOFT_PORT port=$port action=mount_only_down hint_project=$hint_id" 'INFO'
                fi
                clear_connect_keep_tunnel_marker "$port" || true
                invoke_connect_mount_down_by_port "$port" || true
            fi
            continue
        fi

        _ORPHAN_TUNNEL_KILLED=0
        remove_local_orphan_tunnel "$port" "${bg_pid:-}" || true
        after_n=0
        for p in $(get_local_tunnel_ssh_pids "$port" 2>/dev/null || true); do
            after_n=$((after_n + 1))
        done
        killed_n=$((before_n - after_n))
        [ "$killed_n" -lt 0 ] && killed_n=0
        orphans_killed=$((orphans_killed + killed_n))
        # Unprotected Soft kill of Port P: clear keep-marker + down ALL mounts bound to P.
        if [ "$killed_n" -gt 0 ]; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "HYGIENE_SOFT_PORT port=$port action=kill killed=$killed_n hint_project=$hint_id" 'INFO'
            fi
            clear_connect_keep_tunnel_marker "$port" || true
            invoke_connect_mount_down_by_port "$port" || true
        fi
    done
    # Also down mounts whose bound -p has no TCP listener (tunnel already gone, no keep marker).
    local protect_live=""
    if [ -n "${PORT:-}" ] && [ "${PORT}" -gt 0 ] 2>/dev/null; then
        protect_live="$PORT"
    fi
    invoke_connect_mount_down_dead_bound_ports "$protect_live" || true
    if declare -F sshx >/dev/null 2>&1; then
        sshx 'command -v cursor-server-reaper >/dev/null && cursor-server-reaper --apply --user "$USER" 2>&1 | tail -3 || true' >/dev/null 2>&1 || true
        sshx 'n=0; for s in "$HOME/.cache/laptop-exec"/cm-*; do [ -e "$s" ] || continue; ssh -O check -o ControlPath="$s" -o ControlMaster=no -o BatchMode=yes -o ConnectTimeout=2 x >/dev/null 2>&1 || { rm -f "$s"; n=$((n+1)); }; done; echo MUX_DEAD_REMOVED=$n' >/dev/null 2>&1 || true
    fi
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "HYGIENE_SOFT done orphans_killed=$orphans_killed" 'INFO'
    fi
    printf '    \033[0;32mSoft done.\033[0m\n'
    # Re-scan siblings after soft (parity with Windows Get-ConnectHygieneReport -SkipServer).
    siblings=0
    sib_ports=()
    sib_pids=()
    sib_projects=()
    for slot in 0 1 2 3 4 5 6 7 8 9; do
        port=$((port_base + slot))
        for p in $(get_local_tunnel_ssh_pids "$port" 2>/dev/null || true); do
            if [ -n "${bg_pid:-}" ] && [ "$p" = "$bg_pid" ]; then
                continue
            fi
            local pp="$p" hops=0 is_sib=0
            while [ "$pp" -gt 1 ] && [ "$hops" -lt 12 ]; do
                hops=$((hops + 1))
                local cmd
                cmd="$(ps -p "$pp" -o command= 2>/dev/null || true)"
                if printf '%s' "$cmd" | grep -qE 'connect\.sh|connect-boot'; then
                    if [ "$pp" != "$$" ]; then is_sib=1; fi
                    break
                fi
                pp="$(ps -p "$pp" -o ppid= 2>/dev/null | tr -d ' ')"
                [ -n "$pp" ] || break
            done
            if [ "$is_sib" -eq 1 ]; then
                siblings=$((siblings + 1))
                sib_ports+=("$port")
                sib_pids+=("$p")
                local proj="?"
                if [ -f "$(_connect_slot_marker_dir)/session-slot-${slot}.json" ]; then
                    proj="$(sed -n 's/.*"projectId":"\([^"]*\)".*/\1/p' "$(_connect_slot_marker_dir)/session-slot-${slot}.json" | head -1)"
                    [ -n "$proj" ] || proj="?"
                fi
                sib_projects+=("$proj")
            fi
        done
    done

    # B9 / E5: Deep-clean offer — siblings, unmarked KEEP, or high Cursor profile litter.
    # Never touches personal Cursor (~/Library/... personal profile); server-profile only via
    # _close_cursor_project_windows_mac protect_root skip.
    local keep_left=0 profile_all=0 offer_deep=0
    keep_left="$(get_connect_keep_tunnel_markers 2>/dev/null | grep -c . || echo 0)"
    profile_all="$(pgrep -af 'Cursor Helper|cursor-server|ClaudeServerCursor' 2>/dev/null | grep -c . || echo 0)"
    if [ "${siblings:-0}" -gt 0 ] 2>/dev/null || [ "${keep_left:-0}" -gt 0 ] 2>/dev/null || [ "${profile_all:-0}" -ge 10 ] 2>/dev/null; then
        offer_deep=1
    fi
    if [ "$offer_deep" -eq 1 ]; then
        echo ""
        printf '    \033[0;33mDeep-clean candidate: siblings=%s keep_markers=%s profile_all=%s\033[0m\n' \
            "$siblings" "$keep_left" "$profile_all"
        printf '    \033[0;90mStops sibling Connect, closes other project Cursor windows, clears unmarked KEEP.\033[0m\n'
        printf '    \033[0;90mNever touches personal Cursor profile.\033[0m\n'
        local ans_deep=""
        if declare -F connect_prompt >/dev/null 2>&1; then
            ans_deep="$(connect_prompt "    Run Deep-clean? [Y/N] " "HYGIENE_DEEP")"
        else
            read -rp "    Run Deep-clean? [Y/N] " ans_deep || true
        fi
        ans_deep="$(printf '%s' "$ans_deep" | tr '[:upper:]' '[:lower:]')"
        if [ "$ans_deep" = "y" ] || [ "$ans_deep" = "yes" ]; then
            if declare -F connect_log >/dev/null 2>&1; then connect_log 'HYGIENE_DEEP begin' 'INFO'; fi
            local deep_sib_t=0 deep_sib_ui=0 deep_cursor=0 deep_keep=0 deep_orphans=0
            # (a) Sibling stop (same as HYGIENE_SIBLING)
            local i=0
            for i in "${!sib_pids[@]}"; do
                p="${sib_pids[$i]}"
                port="${sib_ports[$i]}"
                local proj="${sib_projects[$i]:-}"
                kill "$p" 2>/dev/null || true
                deep_sib_t=$((deep_sib_t + 1))
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "HYGIENE_DEEP_SIBLING tunnels=1 port=$port pid=$p" 'INFO'
                fi
                local mark_slot=$((port - port_base)) mark_file mark_pid=""
                mark_file="$(_connect_slot_marker_dir)/session-slot-${mark_slot}.json"
                if [ -f "$mark_file" ]; then
                    mark_pid="$(sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' "$mark_file" | head -1)"
                fi
                if [ -n "$mark_pid" ] && [ "$mark_pid" != "$$" ] && kill -0 "$mark_pid" 2>/dev/null; then
                    kill "$mark_pid" 2>/dev/null || true
                    deep_sib_ui=$((deep_sib_ui + 1))
                fi
                if [ -n "$proj" ] && [ "$proj" != "?" ]; then
                    _close_cursor_project_windows_mac "$proj" "$protect_root" || true
                    deep_cursor=$((deep_cursor + 1))
                fi
                clear_connect_session_slot_marker "$mark_slot" || true
            done
            # (b) Clear unmarked KEEP (no editor protect) — kill tunnel + marker + down-by-port
            while IFS='|' read -r km_port km_slot km_tpid km_proj km_path km_alias km_ed km_kept; do
                [ -n "$km_port" ] || continue
                if test_connect_keep_editor_protect "$km_path" "$km_proj" "$km_kept" "${km_alias:-claude-server}" 1; then
                    if declare -F connect_log >/dev/null 2>&1; then
                        connect_log "HYGIENE_DEEP_KEEP_SKIP port=$km_port reason=editor_protect project=$km_proj" 'INFO'
                    fi
                    continue
                fi
                if [ -n "$km_tpid" ] && [ "$km_tpid" -gt 0 ] 2>/dev/null \
                    && { [ -z "${bg_pid:-}" ] || [ "$km_tpid" != "$bg_pid" ]; }; then
                    if declare -F connect_log >/dev/null 2>&1; then
                        connect_log "HYGIENE_DEEP_KEEP_KILL port=$km_port pid=$km_tpid" 'INFO'
                    fi
                    kill "$km_tpid" 2>/dev/null || true
                    deep_orphans=$((deep_orphans + 1))
                fi
                clear_connect_keep_tunnel_marker "$km_port" || true
                if declare -F invoke_connect_mount_down_by_port >/dev/null 2>&1; then
                    invoke_connect_mount_down_by_port "$km_port" || true
                fi
                deep_keep=$((deep_keep + 1))
            done < <(get_connect_keep_tunnel_markers 2>/dev/null || true)
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "HYGIENE_DEEP done siblings_t=$deep_sib_t siblings_ui=$deep_sib_ui cursor=$deep_cursor keep_cleared=$deep_keep orphans=$deep_orphans" 'INFO'
            fi
            printf '    \033[0;32mDeep-clean: siblings_t=%s ui=%s cursor=%s keep_cleared=%s\033[0m\n\n' \
                "$deep_sib_t" "$deep_sib_ui" "$deep_cursor" "$deep_keep"
            return 0
        fi
        printf '    \033[0;90mSkipped Deep-clean.\033[0m\n'
    fi

    if [ "$siblings" -le 0 ]; then echo ""; return 0; fi
    echo ""
    printf '    \033[0;33m%s sibling Connect session(s) still listed.\033[0m\n' "$siblings"
    printf '    \033[0;90mCloses their tunnel, Connect process, and that project Cursor window only.\033[0m\n'
    local ans2=""
    if declare -F connect_prompt >/dev/null 2>&1; then
        ans2="$(connect_prompt "    Close sibling sessions? [Y/N] " "HYGIENE_SIBLING")"
    else
        read -rp "    Close sibling sessions? [Y/N] " ans2 || true
    fi
    ans2="$(printf '%s' "$ans2" | tr '[:upper:]' '[:lower:]')"
    if [ "$ans2" != "y" ] && [ "$ans2" != "yes" ]; then
        printf '    \033[0;90mLeft siblings running.\033[0m\n\n'
        return 0
    fi
    if declare -F connect_log >/dev/null 2>&1; then connect_log 'HYGIENE_SIBLING begin' 'INFO'; fi
    local i=0
    for i in "${!sib_pids[@]}"; do
        p="${sib_pids[$i]}"
        port="${sib_ports[$i]}"
        local proj="${sib_projects[$i]:-}"
        kill "$p" 2>/dev/null || true
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "HYGIENE_SIBLING_STOP tunnel pid=$p port=$port" 'INFO'
        fi
        # Kill sibling connect.sh from slot marker pid (never $$).
        local mark_slot=$((port - port_base)) mark_file mark_pid=""
        mark_file="$(_connect_slot_marker_dir)/session-slot-${mark_slot}.json"
        if [ -f "$mark_file" ]; then
            mark_pid="$(sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' "$mark_file" | head -1)"
        fi
        if [ -n "$mark_pid" ] && [ "$mark_pid" != "$$" ] && kill -0 "$mark_pid" 2>/dev/null; then
            kill "$mark_pid" 2>/dev/null || true
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "HYGIENE_SIBLING_STOP connect_ui pid=$mark_pid" 'INFO'
            fi
        fi
        if [ -n "$proj" ] && [ "$proj" != "?" ]; then
            _close_cursor_project_windows_mac "$proj" "$protect_root"
        fi
        clear_connect_session_slot_marker "$mark_slot" || true
    done
    printf '    \033[0;32mSibling clean done.\033[0m\n\n'
}

configure_git_mode() {
    echo ""
    printf '    \033[1;37mGit on server (SSHFS)\033[0m\n\n'
    printf '    \033[0;33mHIDE/SLOW disabled site-wide. Forced OFF (no .git rename).\033[0m\n'
    printf 'off\n' > "$GIT_CONF"
    push_server_connect_conf
    echo ""
    printf '    \033[0;32mSaved: git OFF.\033[0m\n'
    if [ -n "${ACTIVE_PROJECT_ID:-}" ]; then
        ACTIVE_MOUNT_ID="$ACTIVE_PROJECT_ID"
        push_server_connect_conf
        remount_project_git "$ACTIVE_PROJECT_ID"
    else
        printf '    \033[0;90mReconnect to apply on first mount.\033[0m\n'
    fi
    echo ""
}


show_mount_git_warn() {
    local out="$1" line
    line="$(printf '%s\n' "$out" | grep '^warn: git hide failed' | head -1 || true)"
    if [ -n "$line" ]; then
        warn "$line"
        warn "Close the editor on this project folder, then press R to retry."
    fi
    line="$(printf '%s\n' "$out" | grep '^warn: laptop tunnel down' | head -1 || true)"
    [ -n "$line" ] && warn "$line"
}

test_mount_success() {
    local out="$1" ec="${2:-0}"
    echo "$out" | grep -qE 'error:|FAILED|No tunnel|not configured|unbound variable' && return 1
    [ "$ec" -eq 0 ] && return 0
    echo "$out" | grep -q 'already mounted:' && return 0
    return 1
}

read_retry_quit_key() {
    local timeout="${1:-30}" rk="" ki="" now
    local deadline=$(( $(date +%s) + timeout ))
    while [ "$rk" != r ] && [ "$rk" != q ]; do
        if read -r -t 1 -n 1 ki </dev/tty 2>/dev/null; then
            ki="$(printf '%s' "$ki" | tr '[:upper:]' '[:lower:]')"
            [ "$ki" = r ] && rk=r
            [ "$ki" = q ] && rk=q
        else
            now=$(date +%s)
            if [ "$now" -ge "$deadline" ]; then
                rk=q
                break
            fi
        fi
    done
    printf '%s' "$rk"
}

# When tunnel drops during session wait: honor buffered Q, else auto-reconnect.
# Sets globals: _action, _got_key (requires _tunnel_alive, bg_pid).
tunnel_drop_session_action() {
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
            if declare -F log_tunnel_drop >/dev/null 2>&1; then
                log_tunnel_drop auto_reconnect "${ACTIVE_PROJECT_ID:-?}" false "${_editor_opened:-0}" "${_editor_seen_open:-0}" "${RECOVERY_GENERATION:-0}"
            fi
            printf '\n    Connection dropped - reconnecting...\n'
        fi
    fi
}

_git_mode_tunnel_ok() {
    if [ -n "${bg_pid:-}" ] && declare -F _tunnel_alive >/dev/null 2>&1; then
        _tunnel_alive "$bg_pid" && return 0
        return 1
    fi
    if declare -F tunnel_up >/dev/null 2>&1; then
        tunnel_up && return 0
        return 1
    fi
    return 0
}

remount_project_git() {
    local pid="$1"
    [ -n "$pid" ] || return 1
    echo ""
    printf '    \033[0;36mRemounting with git mode...\033[0m\n'
    sshx "$CM down '$pid'" 2>/dev/null || true
    printf '      -> recovering stale mounts...\n'
    sshx "$CM recover" 2>/dev/null || true
    if ! _git_mode_tunnel_ok; then
        warn "Tunnel dropped during remount - press R to reconnect"
        return 1
    fi
    local mount_out
    mount_out="$(sshx "CLAUDE_TRUSTED_TUNNEL=1 $CM up '$pid' 2>&1")"
    show_mount_git_warn "$mount_out"
    if ! test_mount_success "$mount_out"; then
        warn "$(printf '%s' "$mount_out" | head -3)"
        return 1
    fi
    printf '    \033[0;32mGit mode: %s applied.\033[0m\n\n' "$(get_git_mode)"
    return 0
}

# Remote SSH Chat reads laptop Cursor globalStorage - pull golden tokens from server each connect.
get_cursor_remote_profile_dir() {
    # Isolated profile - separate from the developer's personal Cursor login (same as Windows).
    echo "$HOME/Library/Application Support/ClaudeServerCursorProfile"
}

patch_cursor_server_profile_settings() {
    local settings="$1"
    [ -f "$settings" ] || return 0
    if ! command -v python3 >/dev/null 2>&1; then
        grep -q 'remote.SSH.useLocalServer' "$settings" 2>/dev/null && return 0
        warn 'Install python3 to auto-patch Cursor profile SSH settings'
        return 1
    fi
    python3 - "$settings" <<'PY'
import json, sys
path = sys.argv[1]
defaults = {
    "remote.SSH.connectTimeout": 120,
    "remote.SSH.showLoginTerminal": False,
    "remote.SSH.useLocalServer": False,
}
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except (OSError, json.JSONDecodeError):
    data = {}
changed = False
for key, val in defaults.items():
    if key not in data:
        data[key] = val
        changed = True
if changed:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
PY
}

init_cursor_server_profile() {
    local profile user_dir settings
    profile="$(get_cursor_remote_profile_dir)"
    user_dir="$profile/User"
    settings="$user_dir/settings.json"
    mkdir -p "$user_dir"
    if [ ! -f "$settings" ]; then
        cat > "$settings" <<'JSON'
{
  "window.title": "${dirty}${activeEditorShort}${separator}[Claude Server] ${rootName}",
  "remote.SSH.connectTimeout": 120,
  "remote.SSH.showLoginTerminal": false,
  "remote.SSH.useLocalServer": false,
  "workbench.colorCustomizations": {
    "titleBar.activeBackground": "#1e3a5f",
    "titleBar.activeForeground": "#e8e8e8",
    "titleBar.inactiveBackground": "#152a45",
    "titleBar.inactiveForeground": "#a0a0a0"
  }
}
JSON
        return 0
    fi
    patch_cursor_server_profile_settings "$settings" || true
}

# Mac: shorten TMPDIR so Remote SSH askpass socket stays under 104-char sun_path limit.
ensure_mac_cursor_tmpdir() {
    [ "$(uname -s 2>/dev/null)" = "Darwin" ] || return 0
    local tmp="${TMPDIR:-}"
    case "$tmp" in
        /tmp|/tmp/) return 0 ;;
    esac
    if [ -z "$tmp" ] || [ "${#tmp}" -gt 40 ] || case "$tmp" in /var/folders/*) true ;; *) false ;; esac; then
        launchctl setenv TMPDIR /tmp 2>/dev/null || true
        export TMPDIR=/tmp
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log 'MAC_ENV: TMPDIR=/tmp (Remote SSH socket path limit)' 'DEBUG'
        fi
    fi
}

# Cursor officially supports anysphere.remote-ssh, not Microsoft's extension.
check_mac_cursor_remote_ssh_extension() {
    [ "$(uname -s 2>/dev/null)" = "Darwin" ] || return 0
    local ext_dir="$HOME/.cursor/extensions" d has_anysphere=0 has_ms=0
    [ -d "$ext_dir" ] || return 0
    for d in "$ext_dir"/anysphere.remote-ssh-*; do
        [ -d "$d" ] && has_anysphere=1
    done
    for d in "$ext_dir"/ms-vscode-remote.remote-ssh-*; do
        [ -d "$d" ] && has_ms=1
    done
    if [ "$has_ms" -eq 1 ]; then
        warn 'Remove ms-vscode-remote.remote-ssh - use anysphere.remote-ssh in Cursor Extensions'
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log 'MAC_EXT: ms-vscode-remote.remote-ssh installed (unsupported)' 'WARN'
        fi
    fi
    if [ "$has_anysphere" -eq 0 ]; then
        warn 'Install anysphere.remote-ssh: Cursor Extensions -> @id:anysphere.remote-ssh'
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log 'MAC_EXT: anysphere.remote-ssh missing' 'WARN'
        fi
        return 1
    fi
    return 0
}

ensure_mac_cursor_prerequisites() {
    ensure_mac_cursor_tmpdir || true
    init_cursor_server_profile
    check_mac_cursor_remote_ssh_extension || true
}

repair_cursor_composer_workspace_bindings() {
    local alias_name="$1" remote_path="$2" gs db ws_root ws_id="" folder_uri=""
    [ -n "$alias_name" ] && [ -n "$remote_path" ] || return 0
    gs="$(get_cursor_remote_profile_dir)/User/globalStorage"
    db="$gs/state.vscdb"
    [ -f "$db" ] || return 0
    remote_path="${remote_path%/}"
    folder_uri="vscode-remote://ssh-remote+${alias_name}${remote_path}"
    ws_root="$(get_cursor_remote_profile_dir)/User/workspaceStorage"
    if [ -d "$ws_root" ]; then
        local wj raw
        for wj in "$ws_root"/*/workspace.json; do
            [ -f "$wj" ] || continue
            raw="$(python3 - "$wj" "$remote_path" <<'PY'
import json, sys
wj, want = sys.argv[1], sys.argv[2]
try:
    folder = json.load(open(wj, encoding="utf-8")).get("folder") or ""
except (OSError, json.JSONDecodeError):
    sys.exit(0)
folder = folder.replace("%2B", "+")
if want in folder or folder.endswith(want):
    print(wj.rsplit("/", 1)[0].rsplit("/", 1)[-1])
PY
)" || true
            [ -n "$raw" ] && { ws_id="$raw"; break; }
        done
    fi
    export _CURSOR_REPAIR_DB="$db"
    export _CURSOR_REPAIR_URI="$folder_uri"
    export _CURSOR_REPAIR_WS_ID="$ws_id"
    python3 <<'PY'
import json, os, sqlite3, sys
db = os.environ.get("_CURSOR_REPAIR_DB", "")
folder_uri = os.environ.get("_CURSOR_REPAIR_URI", "")
ws_id = os.environ.get("_CURSOR_REPAIR_WS_ID") or ""
if not db or not folder_uri:
    sys.exit(0)
path = folder_uri.split("vscode-remote://ssh-remote+", 1)[-1]
if "/" in path:
    auth, remote_path = path.split("/", 1)
    remote_path = "/" + remote_path
else:
    auth, remote_path = path, "/"
conn = sqlite3.connect(db, timeout=30)
conn.execute("PRAGMA busy_timeout=30000")
try:
    row = conn.execute(
        "SELECT value FROM ItemTable WHERE key='composer.composerHeaders' LIMIT 1"
    ).fetchone()
    if not row:
        sys.exit(0)
    data = json.loads(row[0])
    composers = data.get("allComposers") or []
    changed = 0
    for item in composers:
        wi = item.get("workspaceIdentifier") or {}
        uri = wi.get("uri") or {}
        ext = uri.get("external") or uri.get("fsPath") or wi.get("id") or ""
        ext_norm = ext.replace("%2B", "+")
        if ext_norm:
            old_part = ext_norm.split("vscode-remote://ssh-remote+", 1)[-1]
            old_path = "/" + old_part.split("/", 1)[1] if "/" in old_part else old_part
            if old_path.rstrip("/") == remote_path.rstrip("/"):
                continue
            if not remote_path.startswith(old_path.rstrip("/") + "/"):
                continue
        cid = item.get("composerId") or ""
        if not cid:
            continue
        has_data = conn.execute(
            "SELECT 1 FROM cursorDiskKV WHERE key=? LIMIT 1",
            (f"composerData:{cid}",),
        ).fetchone()
        if not has_data:
            continue
        item["workspaceIdentifier"] = {
            "id": ws_id,
            "uri": {
                "$mid": 1,
                "fsPath": remote_path.replace("/", "\\"),
                "_sep": 1,
                "external": folder_uri.replace("+", "%2B"),
                "path": remote_path,
                "scheme": "vscode-remote",
                "authority": f"ssh-remote+{auth}",
            },
        }
        changed += 1
    if changed:
        conn.execute(
            "INSERT INTO ItemTable (key, value) VALUES (?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            ("composer.composerHeaders", json.dumps(data)),
        )
        conn.commit()
except (json.JSONDecodeError, sqlite3.Error, KeyError):
    sys.exit(1)
finally:
    conn.close()
PY
    unset _CURSOR_REPAIR_DB _CURSOR_REPAIR_URI _CURSOR_REPAIR_WS_ID
}

resolve_remote_cursor_global_base() {
    local line cmd
    for cmd in \
        'cursor-auth-source-path 2>/dev/null' \
        'python3 /usr/local/lib/claude-server/cursor-auth-lib.py source-path 2>/dev/null'; do
        line="$(sshx "$cmd" 2>/dev/null | head -1 || true)"
        if [ -n "$line" ]; then
            printf '%s' "$line"
            return 0
        fi
    done
    line="$(sshx 'python3 -c "
import os, sqlite3
for rel in (\".config/Cursor/User/globalStorage\", \".config/cursor/User/globalStorage\", \".cursor-server/data/User/globalStorage\"):
    p = os.path.expanduser(\"~/\" + rel + \"/state.vscdb\")
    if not os.path.isfile(p):
        continue
    try:
        c = sqlite3.connect(p)
        a = c.execute(\"SELECT 1 FROM ItemTable WHERE key='"'"'cursorAuth/accessToken'"'"' LIMIT 1\").fetchone()
        r = c.execute(\"SELECT 1 FROM ItemTable WHERE key='"'"'cursorAuth/refreshToken'"'"' LIMIT 1\").fetchone()
        c.close()
        if a and r:
            print(rel)
            break
    except sqlite3.Error:
        pass
"' 2>/dev/null | head -1 || true)"
    if [ -n "$line" ]; then
        printf '%s' "$line"
        return 0
    fi
    return 1
}

cursor_sqlite3_available() {
    command -v sqlite3 >/dev/null 2>&1
}

cursor_sql_escape() {
    printf '%s' "$1" | sed "s/'/''/g"
}

cursor_db_has_key() {
    local db="$1" key="$2" row
    [ -f "$db" ] || return 1
    cursor_sqlite3_available || return 1
    row="$(sqlite3 "$db" "SELECT 1 FROM ItemTable WHERE key='$(cursor_sql_escape "$key")' LIMIT 1;" 2>/dev/null || true)"
    [ -n "$row" ]
}

cursor_db_value_length() {
    local db="$1" key="$2" len
    [ -f "$db" ] || return 1
    cursor_sqlite3_available || return 1
    len="$(sqlite3 "$db" "SELECT length(value) FROM ItemTable WHERE key='$(cursor_sql_escape "$key")' LIMIT 1;" 2>/dev/null || true)"
    [ -n "$len" ] && [ "$len" -gt 0 ]
}

cursor_json_get_string() {
    local json="$1" key="$2" line
    line="$(printf '%s' "$json" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" 2>/dev/null | head -1 || true)"
    [ -n "$line" ] || return 1
    printf '%s' "$line" | sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/'
}

cursor_json_get_string_file() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 1
    cursor_json_get_string "$(cat "$file")" "$key"
}

cursor_json_set_string_key_file() {
    local file="$1" key="$2" val="$3" tmp escaped content
    escaped="$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    tmp="${file}.merge-tmp"
    if [ ! -f "$file" ]; then
        printf '{\n  "%s": "%s"\n}\n' "$key" "$escaped" > "$tmp"
    else
        content="$(tr -d '\n' <"$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if printf '%s' "$content" | grep -q "\"$key\""; then
            content="$(printf '%s' "$content" | sed "s/\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"$key\": \"$escaped\"/")"
        else
            content="${content%\}}"
            content="${content},\"$key\":\"$escaped\"}"
        fi
        printf '%s\n' "$content" > "$tmp"
    fi
    mv "$tmp" "$file"
}

cursor_auth_payload_to_pairs() {
    local payload="$1" out="$2" key val
    : >"$out"
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$payload" | jq -r 'to_entries[] | select(.value != null and (.value | tostring) != "") | [.key, .value] | @tsv' >"$out" 2>/dev/null || return 1
        [ -s "$out" ]
        return
    fi
    for key in \
        cursorAuth/accessToken cursorAuth/refreshToken cursorAuth/cachedEmail \
        cursorAuth/cachedSignUpType cursorAuth/stripeMembershipType cursorAuth/stripeSubscriptionStatus \
        storage.serviceMachineId telemetry.machineId telemetry.macMachineId \
        telemetry.devDeviceId telemetry.sqmId; do
        val="$(cursor_json_get_string "$payload" "$key" || true)"
        [ -n "$val" ] && printf '%s\t%s\n' "$key" "$val" >>"$out"
    done
    [ -s "$out" ]
}

cursor_sqlite_merge_pairs() {
    local db="$1" pairs_file="$2" pair_key pair_val esc_key esc_val
    [ -f "$pairs_file" ] || return 1
    cursor_sqlite3_available || return 1
    sqlite3 "$db" "PRAGMA busy_timeout=30000; CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT);" >/dev/null 2>&1 || return 1
    while IFS=$'\t' read -r pair_key pair_val || [ -n "$pair_key" ]; do
        [ -n "$pair_key" ] && [ -n "$pair_val" ] || continue
        esc_key="$(cursor_sql_escape "$pair_key")"
        esc_val="$(cursor_sql_escape "$pair_val")"
        sqlite3 "$db" "INSERT INTO ItemTable (key, value) VALUES ('${esc_key}', '${esc_val}') ON CONFLICT(key) DO UPDATE SET value = excluded.value;" >/dev/null 2>&1 || return 1
    done <"$pairs_file"
    return 0
}

fetch_golden_auth_dir() {
    local tmp auth_ok
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/cursor-golden.XXXXXX")" || return 1
    auth_ok=0
    scp -o BatchMode=yes -o ConnectTimeout=20 -q \
        "$ALIAS:/etc/cursor-auth/golden/auth.json" \
        "$tmp/auth.json" 2>/dev/null && auth_ok=1
    scp -o BatchMode=yes -o ConnectTimeout=20 -q \
        "$ALIAS:/etc/cursor-auth/golden/state-keys.json" \
        "$tmp/state-keys.json" 2>/dev/null || true
    scp -o BatchMode=yes -o ConnectTimeout=20 -q \
        "$ALIAS:/etc/cursor-auth/golden/machine-id.txt" \
        "$tmp/machine-id.txt" 2>/dev/null || true
    if [ "$auth_ok" -eq 1 ]; then
        printf '%s' "$tmp"
        return 0
    fi
    rm -rf "$tmp"
    return 1
}

build_cursor_auth_payload_from_golden_dir() {
    local dir="$1" auth="$dir/auth.json" sk="$dir/state-keys.json" mid="$dir/machine-id.txt"
    local machine_id payload
    [ -f "$auth" ] || return 1

    if [ -f "$sk" ] && command -v jq >/dev/null 2>&1; then
        machine_id=""
        [ -f "$mid" ] && machine_id="$(tr -d '[:space:]' <"$mid")"
        payload="$(jq -n \
            --slurpfile sk "$sk" \
            --slurpfile auth "$auth" \
            --arg mid "$machine_id" \
            '($sk[0] // {}) as $vals
            | ($auth[0] // {}) as $a
            | $vals
            | if $a.accessToken then .["cursorAuth/accessToken"] = $a.accessToken else . end
            | if $a.refreshToken then .["cursorAuth/refreshToken"] = $a.refreshToken else . end
            | if $a.cachedEmail then .["cursorAuth/cachedEmail"] = $a.cachedEmail else . end
            | if $a.cachedSignUpType then .["cursorAuth/cachedSignUpType"] = $a.cachedSignUpType else . end
            | if $a.stripeMembershipType then .["cursorAuth/stripeMembershipType"] = $a.stripeMembershipType else . end
            | if $a.stripeSubscriptionStatus then .["cursorAuth/stripeSubscriptionStatus"] = $a.stripeSubscriptionStatus else . end
            | if ($mid | length) > 0 then
                .["storage.serviceMachineId"] = $mid
                | .["telemetry.machineId"] = (.["telemetry.machineId"] // $mid)
                | .["telemetry.macMachineId"] = (.["telemetry.macMachineId"] // $mid)
                | .["telemetry.devDeviceId"] = (.["telemetry.devDeviceId"] // $mid)
                | .["telemetry.sqmId"] = (.["telemetry.sqmId"] // $mid)
              else . end
            | with_entries(select(.value != null and (.value | tostring) != ""))' 2>/dev/null || true)"
        if [ -n "$payload" ] && printf '%s' "$payload" | grep -q 'cursorAuth/accessToken'; then
            printf '%s' "$payload"
            return 0
        fi
    fi

    if [ -f "$sk" ] && grep -q 'cursorAuth/accessToken' "$sk" 2>/dev/null; then
        payload="$(tr -d '\n' <"$sk")"
        machine_id=""
        [ -f "$mid" ] && machine_id="$(tr -d '[:space:]' <"$mid")"
        if [ -n "$machine_id" ]; then
            for key in storage.serviceMachineId telemetry.machineId telemetry.macMachineId telemetry.devDeviceId telemetry.sqmId; do
                if ! printf '%s' "$payload" | grep -q "\"$key\""; then
                    payload="${payload%\}}"
                    payload="${payload}, \"$key\": \"$machine_id\"}"
                fi
            done
        fi
        printf '%s' "$payload"
        return 0
    fi

    payload='{'
    local first=1 tok
    for tok in accessToken:cursorAuth/accessToken refreshToken:cursorAuth/refreshToken \
        cachedEmail:cursorAuth/cachedEmail cachedSignUpType:cursorAuth/cachedSignUpType \
        stripeMembershipType:cursorAuth/stripeMembershipType stripeSubscriptionStatus:cursorAuth/stripeSubscriptionStatus; do
        local src="${tok%%:*}" dst="${tok#*:}" val
        val="$(cursor_json_get_string_file "$auth" "$src" || true)"
        [ -n "$val" ] || continue
        [ "$first" -eq 1 ] || payload="${payload},"
        first=0
        payload="${payload}\"${dst}\":\"${val}\""
    done
    machine_id=""
    [ -f "$mid" ] && machine_id="$(tr -d '[:space:]' <"$mid")"
    if [ -n "$machine_id" ]; then
        for key in storage.serviceMachineId telemetry.machineId telemetry.macMachineId telemetry.devDeviceId telemetry.sqmId; do
            [ "$first" -eq 1 ] || payload="${payload},"
            first=0
            payload="${payload}\"${key}\":\"${machine_id}\""
        done
    fi
    payload="${payload}}"
    printf '%s' "$payload" | grep -q 'cursorAuth/accessToken' || return 1
    printf '%s' "$payload"
}

local_cursor_auth_db_ok() {
    local db="$1"
    [ -f "$db" ] || return 1
    cursor_db_has_key "$db" 'cursorAuth/accessToken' && cursor_db_has_key "$db" 'cursorAuth/refreshToken'
}

fetch_golden_auth_payload() {
    local payload dir cmd tmp
    if dir="$(fetch_golden_auth_dir 2>/dev/null)"; then
        payload="$(build_cursor_auth_payload_from_golden_dir "$dir" 2>/dev/null || true)"
        rm -rf "$dir"
        if [ -n "$payload" ] && printf '%s' "$payload" | grep -q 'cursorAuth/accessToken'; then
            printf '%s' "$payload"
            return 0
        fi
    fi
    for cmd in \
        'python3 /usr/local/lib/claude-server/cursor-auth-lib.py laptop-auth-json 2>/dev/null' \
        'python3 -c "
import json, os
g = \"/etc/cursor-auth/golden\"
auth = json.load(open(os.path.join(g, \"auth.json\"), encoding=\"utf-8\"))
vals = {}
if auth.get(\"accessToken\"):
    vals[\"cursorAuth/accessToken\"] = auth[\"accessToken\"]
if auth.get(\"refreshToken\"):
    vals[\"cursorAuth/refreshToken\"] = auth[\"refreshToken\"]
if auth.get(\"cachedEmail\"):
    vals[\"cursorAuth/cachedEmail\"] = auth[\"cachedEmail\"]
sk = os.path.join(g, \"state-keys.json\")
if os.path.isfile(sk):
    vals.update(json.load(open(sk, encoding=\"utf-8\")))
mid = open(os.path.join(g, \"machine-id.txt\"), encoding=\"utf-8\").read().strip()
if mid:
    vals[\"storage.serviceMachineId\"] = mid
    for k in (\"telemetry.machineId\", \"telemetry.macMachineId\", \"telemetry.devDeviceId\", \"telemetry.sqmId\"):
        vals.setdefault(k, mid)
print(json.dumps(vals))
"'; do
        payload="$(sshx "$cmd" 2>/dev/null | tail -1 || true)"
        if [ -n "$payload" ] && printf '%s' "$payload" | grep -q 'cursorAuth/accessToken'; then
            printf '%s' "$payload"
            return 0
        fi
    done
    return 1
}

write_cursor_profile_machineid() {
    # Electron reads profile-root machineid; SQLite telemetry alone is not enough.
    local profile mid_file mid=""
    profile="$(get_cursor_remote_profile_dir)"
    mid_file="$profile/machineid"
    [ -d "$profile" ] || mkdir -p "$profile" 2>/dev/null || true
    if [ -n "${1:-}" ]; then
        mid="$(printf '%s' "$1" | tr -d '[:space:]')"
    fi
    if [ -z "$mid" ]; then
        mid="$(sshx 'tr -d "[:space:]" < /etc/cursor-auth/golden/machine-id.txt 2>/dev/null' 2>/dev/null | tr -d '\r\n' || true)"
    fi
    [ -n "$mid" ] || return 1
    printf '%s' "$mid" > "$mid_file"
    printf '%s' "$mid" > "$profile/machineId"
    return 0
}

# Lightweight (no SSH) machineid heal: read storage.serviceMachineId straight out of the
# local SQLite db. write_cursor_profile_machineid() still falls back to an sshx golden read
# only when this local read comes back empty - Windows parity for the outer/stamp skip paths.
heal_cursor_profile_machineid_from_local() {
    local db="$1" mid=""
    if [ -f "$db" ] && declare -F cursor_sqlite3_available >/dev/null 2>&1 && cursor_sqlite3_available; then
        mid="$(sqlite3 "$db" "SELECT value FROM ItemTable WHERE key='storage.serviceMachineId' LIMIT 1;" 2>/dev/null | tr -d '\r\n' || true)"
    fi
    write_cursor_profile_machineid "${mid:-}"
}

merge_cursor_auth_into_local_db() {
    local gs="$1" payload="$2" attempt db="${1}/state.vscdb" pairs_file mid=""
    [ -n "$payload" ] || return 1
    cursor_sqlite3_available || return 1
    pairs_file="$(mktemp "${TMPDIR:-/tmp}/cursor-auth-pairs.XXXXXX")"
    cursor_auth_payload_to_pairs "$payload" "$pairs_file" || { rm -f "$pairs_file"; return 1; }
    for attempt in 1 2 3 4 5; do
        if cursor_sqlite_merge_pairs "$db" "$pairs_file"; then
            sqlite3 "$db" "PRAGMA wal_checkpoint(FULL);" >/dev/null 2>&1 || true
            if command -v jq >/dev/null 2>&1; then
                mid="$(printf '%s' "$payload" | jq -r '."storage.serviceMachineId" // ."telemetry.machineId" // empty' 2>/dev/null || true)"
            else
                mid="$(awk -F'\t' '$1=="storage.serviceMachineId"{print $2; exit}' "$pairs_file" 2>/dev/null || true)"
                [ -n "$mid" ] || mid="$(awk -F'\t' '$1=="telemetry.machineId"{print $2; exit}' "$pairs_file" 2>/dev/null || true)"
            fi
            write_cursor_profile_machineid "$mid" || true
            rm -f "$pairs_file"
            return 0
        fi
        sleep 0.4
    done
    rm -f "$pairs_file"
    return 1
}

merge_cursor_storage_json_from_golden() {
    local gs="$1" dst="$gs/storage.json" src="$gs/storage.json.merge-src" key val
    scp -o BatchMode=yes -o ConnectTimeout=20 -q "$ALIAS:/etc/cursor-auth/golden/storage.json" "$src" 2>/dev/null || return 1
    if command -v jq >/dev/null 2>&1; then
        local tmp_out="${dst}.merge-tmp"
        if [ -f "$dst" ]; then
            jq -s '
                .[0] as $local
                | .[1] as $remote
                | $local
                | .["telemetry.machineId"] = ($remote["telemetry.machineId"] // .["telemetry.machineId"])
                | .["telemetry.macMachineId"] = ($remote["telemetry.macMachineId"] // .["telemetry.macMachineId"])
                | .["telemetry.devDeviceId"] = ($remote["telemetry.devDeviceId"] // $remote["telemetry.machineId"] // .["telemetry.devDeviceId"])
                | .["telemetry.sqmId"] = ($remote["telemetry.sqmId"] // .["telemetry.sqmId"])
            ' "$dst" "$src" >"$tmp_out" 2>/dev/null || { rm -f "$src" "$tmp_out"; return 1; }
        else
            jq '{
                "telemetry.machineId": .["telemetry.machineId"],
                "telemetry.macMachineId": .["telemetry.macMachineId"],
                "telemetry.devDeviceId": .["telemetry.devDeviceId"],
                "telemetry.sqmId": .["telemetry.sqmId"]
            } | with_entries(select(.value != null and (.value | tostring) != ""))' "$src" >"$tmp_out" 2>/dev/null || { rm -f "$src" "$tmp_out"; return 1; }
        fi
        printf '\n' >>"$tmp_out"
        mv "$tmp_out" "$dst"
        rm -f "$src"
        return 0
    fi
    [ -f "$dst" ] || printf '{}\n' >"$dst"
    for key in telemetry.machineId telemetry.macMachineId telemetry.devDeviceId telemetry.sqmId; do
        val="$(cursor_json_get_string_file "$src" "$key" || true)"
        [ -n "$val" ] && cursor_json_set_string_key_file "$dst" "$key" "$val"
    done
    rm -f "$src"
}

sync_cursor_golden_auth() {
    sshx "test -f /etc/cursor-auth/golden/auth.json" 2>/dev/null || return 1
    sshx "cursor-auth-sync --force 2>&1" 2>/dev/null || true
    local gs payload
    gs="$(get_cursor_remote_profile_dir)/User/globalStorage"
    mkdir -p "$gs"
    payload="$(fetch_golden_auth_payload)" || return 1
    merge_cursor_auth_into_local_db "$gs" "$payload" || return 1
    merge_cursor_storage_json_from_golden "$gs" || true
    local_cursor_auth_db_ok "$gs/state.vscdb"
}

local_cursor_auth_complete() {
    local db="$1"
    [ -f "$db" ] || return 1
    cursor_db_value_length "$db" 'cursorAuth/accessToken' \
        && cursor_db_value_length "$db" 'cursorAuth/refreshToken' \
        && cursor_db_value_length "$db" 'cursorAuth/cachedEmail' \
        && cursor_db_value_length "$db" 'cursorAuth/stripeMembershipType' \
        && cursor_db_value_length "$db" 'storage.serviceMachineId'
}

# True when local auth is missing keys, personal Cursor dominates, or golden
# export stamp is newer than last laptop merge (token rotates every ~6h).
cursor_auth_needs_refresh() {
    local db="${1:-}" auth_complete="${2:-0}" gs synced_at_path synced_at golden_exported="" reasons=""
    if [ -z "$db" ]; then
        db="$(get_cursor_remote_profile_dir)/User/globalStorage/state.vscdb"
    fi
    gs="$(dirname "$db")"
    synced_at_path="$gs/golden-synced-at.txt"

    if [ ! -f "$db" ]; then
        declare -F connect_log >/dev/null 2>&1 && connect_log 'AUTH_REFRESH: reason=db_missing' 'DEBUG'
        return 0
    fi
    if ! cursor_sqlite3_available; then
        declare -F connect_log >/dev/null 2>&1 && connect_log 'AUTH_REFRESH: reason=sqlite_unavailable' 'DEBUG'
        return 0
    fi
    if ! cursor_db_value_length "$db" 'storage.serviceMachineId'; then
        reasons="${reasons}serviceMachineId_empty "
    fi
    # Electron machineid file must match golden (login breaks when it drifts).
    _prof="$(get_cursor_remote_profile_dir)"
    _file_mid=""
    [ -f "$_prof/machineid" ] && _file_mid="$(tr -d "[:space:]" < "$_prof/machineid")"
    _gold_mid="$(sshx 'tr -d "[:space:]" < /etc/cursor-auth/golden/machine-id.txt 2>/dev/null' 2>/dev/null | tr -d '\r\n' || true)"
    if [ -n "$_gold_mid" ] && [ "$_file_mid" != "$_gold_mid" ]; then
        reasons="${reasons}machineid_file_mismatch "
    fi
    # Any single personal Cursor window with no profile window (parity with
    # Windows Test-CursorAuthNeedsRefresh personal_without_profile check).
    local personal_main=0 profile_main=0 pc_line pc_cmd
    while IFS= read -r pc_line; do
        [ -z "$pc_line" ] && continue
        pc_cmd="${pc_line#* }"
        case "$pc_cmd" in *--type=*) continue ;; esac
        case "$pc_cmd" in *Cursor*|*cursor*)
            case "$pc_cmd" in *"$_prof"*) profile_main=$(( profile_main + 1 )) ;;
            *) personal_main=$(( personal_main + 1 )) ;;
            esac
        ;; esac
    done < <(ps ax -o command= 2>/dev/null || true)
    if [ $personal_main -gt 0 ] && [ $profile_main -eq 0 ] && [ "$auth_complete" != "1" ]; then
        reasons="${reasons}personal_without_profile "
    fi
    golden_exported="$(sshx 'cat /etc/cursor-auth/golden/exported-at 2>/dev/null' 2>/dev/null | tr -d '\r\n' || true)"
    synced_at=""
    [ -f "$synced_at_path" ] && synced_at="$(tr -d '\r\n' < "$synced_at_path")"
    if [ -n "$golden_exported" ] && [ "$synced_at" != "$golden_exported" ]; then
        reasons="${reasons}golden_stale "
    fi
    if [ -n "$reasons" ]; then
        declare -F connect_log >/dev/null 2>&1 && connect_log "AUTH_REFRESH: needs_refresh reasons=$reasons" 'DEBUG'
        return 0
    fi
    return 1
}

sync_cursor_golden_auth_status() {
    CURSOR_AUTH_SYNC_RESULT=fail
    local gs payload db force="${CURSOR_AUTH_FORCE:-0}"
    local synced_at_path synced_at golden_exported="" golden_current=0
    gs="$(get_cursor_remote_profile_dir)/User/globalStorage"
    mkdir -p "$gs"
    db="$gs/state.vscdb"
    synced_at_path="$gs/golden-synced-at.txt"

    golden_exported="$(sshx 'cat /etc/cursor-auth/golden/exported-at 2>/dev/null' 2>/dev/null | tr -d '\r\n' || true)"
    synced_at=""
    [ -f "$synced_at_path" ] && synced_at="$(tr -d '\r\n' < "$synced_at_path")"
    if [ -n "$golden_exported" ] && [ "$synced_at" = "$golden_exported" ]; then
        golden_current=1
    fi

    # Skip only when auth is complete AND stamped with the CURRENT golden export.
    # Presence alone is not enough: OAuth rotate every 6h invalidates old pairs.
    # Even on skip, heal Electron machineid file (SQLite-complete profiles can still drift).
    if [ "$force" != "1" ] && [ "$golden_current" -eq 1 ] && [ -f "$db" ] && local_cursor_auth_complete "$db"; then
        # Prefer local SQLite machine id (already golden); fall back to server file.
        heal_cursor_profile_machineid_from_local "$db" || true
        CURSOR_AUTH_SYNC_RESULT=ok
        declare -F connect_log >/dev/null 2>&1 && connect_log "AUTH_SYNC: skip already_complete golden_exported_at=$golden_exported (machineid healed)" 'DEBUG'
        return 0
    fi

    sshx "test -f /etc/cursor-auth/golden/auth.json" 2>/dev/null || { CURSOR_AUTH_SYNC_RESULT=skipped; return 1; }
    sshx "cursor-auth-sync --force 2>&1" 2>/dev/null || true
    # Re-read export stamp after server sync (refresh may have updated it)
    golden_exported="$(sshx 'cat /etc/cursor-auth/golden/exported-at 2>/dev/null' 2>/dev/null | tr -d '\r\n' || true)"
    payload="$(fetch_golden_auth_payload)" || { CURSOR_AUTH_SYNC_RESULT=skipped; return 1; }
    merge_cursor_auth_into_local_db "$gs" "$payload" || { CURSOR_AUTH_SYNC_RESULT=fail; return 1; }
    merge_cursor_storage_json_from_golden "$gs" || true
    db="$gs/state.vscdb"
    if local_cursor_auth_complete "$db"; then
        CURSOR_AUTH_SYNC_RESULT=ok
        if [ -n "$golden_exported" ]; then
            printf '%s' "$golden_exported" > "$synced_at_path" 2>/dev/null || true
        fi
        [ "$force" = "1" ] && unset CURSOR_AUTH_FORCE
        return 0
    fi
    if local_cursor_auth_db_ok "$db"; then
        CURSOR_AUTH_SYNC_RESULT=tokens_only
        return 0
    fi
    CURSOR_AUTH_SYNC_RESULT=fail
    return 1
}

push_cursor_golden_from_server_profile() {
    printf 'P-key push removed - server auth is managed on server only'
    return 1
}


laptop_rpath_compatible() {
    local rpath="$1" os="${2:-${GIT_MODE_LAPTOP_OS:-mac}}"
    rpath="${rpath//\\//}"
    rpath="$(printf '%s' "$rpath" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$rpath" ] && return 1
    case "$os" in
        mac)
            case "$rpath" in
                [A-Za-z]:*) return 1 ;;
            esac
            ;;
        windows)
            case "$rpath" in
                /Users/*) return 1 ;;
            esac
            ;;
    esac
    return 0
}

laptop_rpath_exists() {
    local rpath="$1"
    rpath="${rpath//\\//}"
    rpath="$(printf '%s' "$rpath" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$rpath" ] && return 1
    [ -d "$rpath" ] || [ -e "$rpath" ]
}

laptop_rpath_os_hint() {
    local rpath="$1" os="${2:-${GIT_MODE_LAPTOP_OS:-mac}}"
    if laptop_rpath_compatible "$rpath" "$os"; then
        return 1
    fi
    case "$os" in
        mac) printf 'Windows only' ;;
        *) printf 'Mac only' ;;
    esac
    return 0
}

warn_invalid_project_rpath() {
    local rpath="$1" num="${2:-}" os="${3:-${GIT_MODE_LAPTOP_OS:-mac}}"
    if ! laptop_rpath_compatible "$rpath" "$os"; then
        if [ "$os" = "mac" ]; then
            warn "Windows path - not usable on Mac.${num:+ Press e to edit project #$num.}"
        else
            warn "Mac path - not usable on Windows.${num:+ Press e to edit project #$num.}"
        fi
        return 1
    fi
    if ! laptop_rpath_exists "$rpath"; then
        warn "Folder not found on this laptop: $rpath${num:+ - press e to edit project #$num.}"
        return 1
    fi
    return 0
}

filter_mounts_for_laptop() {
    local raw="$1" os="${2:-${GIT_MODE_LAPTOP_OS:-mac}}" mid mlabel mrpath mlpath
    while IFS='|' read -r mid mlabel mrpath mlpath; do
        [ -z "$mid" ] && continue
        laptop_rpath_compatible "$mrpath" "$os" || continue
        printf '%s|%s|%s|%s\n' "$mid" "$mlabel" "$mrpath" "$mlpath"
    done <<< "$raw"
}

count_skipped_mounts_for_laptop() {
    local raw="$1" os="${2:-${GIT_MODE_LAPTOP_OS:-mac}}" mid mrpath total=0 visible=0
    while IFS='|' read -r mid _ mrpath _; do
        [ -z "$mid" ] && continue
        total=$(( total + 1 ))
        if laptop_rpath_compatible "$mrpath" "$os"; then
            visible=$(( visible + 1 ))
        fi
    done <<< "$raw"
    printf '%s' $(( total - visible ))
}

purge_incompatible_server_mounts() {
    # Remove mount configs whose laptop path cannot work on this OS (e.g. D:/ on Mac).
    local os="${1:-${GIT_MODE_LAPTOP_OS:-}}" raw line mid mrpath n=0
    [ -n "$os" ] || return 0
    raw="$(sshx "$CM list 2>/dev/null" 2>/dev/null || true)"
    [ -n "$raw" ] || return 0
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        IFS='|' read -r mid _label mrpath _lpath <<< "$line"
        [ -n "$mid" ] && [ -n "$mrpath" ] || continue
        if laptop_rpath_compatible "$mrpath" "$os"; then
            continue
        fi
        sshx "$CM remove '$mid' 2>/dev/null" >/dev/null 2>&1 || \
            sshx "rm -f \"\$HOME/.claude-mounts.d/${mid}.conf\"" >/dev/null 2>&1 || true
        n=$((n + 1))
    done <<< "$raw"
    [ "$n" -gt 0 ] && warn "Removed $n leftover project(s) incompatible with this laptop OS."
    return 0
}

mount_list_step_label() {
    local raw="$1" os="${2:-${GIT_MODE_LAPTOP_OS:-mac}}" visible hidden label
    visible="$(filter_mounts_for_laptop "$raw" "$os" | grep -c '|' 2>/dev/null || echo 0)"
    hidden="$(count_skipped_mounts_for_laptop "$raw" "$os")"
    if [ "$hidden" -gt 0 ]; then
        if [ "$os" = "mac" ]; then
            label="${visible} for this Mac (${hidden} Windows-only hidden)"
        else
            label="${visible} for this PC (${hidden} Mac-only hidden)"
        fi
    else
        label="${visible} project(s)"
    fi
    printf '%s' "$label"
}

read_post_disconnect_key() {
    local default="${1:-m}" timeout="${2:-10}" deadline key left
    deadline=$(( $(date +%s) + timeout ))
    echo ""
    printf '    \033[0;36mDisconnected. What would you like to do?\033[0m\n'
    printf '    \033[0;90mM = project menu   C = connect again   X = exit\033[0m\n\n'
    while [ "$(date +%s)" -lt "$deadline" ]; do
        left=$(( deadline - $(date +%s) ))
        printf '\r    Default %s in %ss...   ' "$default" "$left"
        if read -r -t 1 -n 1 key </dev/tty 2>/dev/null; then
            printf '\n'
            # Bug 59: Mac TTY has no ConsoleKey VK (Win useVk). ASCII m/c/x only;
            # ignore Persian/other glyphs so they never false-trigger.
            key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
            case "$key" in
                m) printf 'm'; return 0 ;;
                c) printf 'c'; return 0 ;;
                x) printf 'x'; return 0 ;;
                *) ;; # non-ASCII / other: ignore until timeout default
            esac
        fi
    done
    printf '\n    Default %s\n' "$default"
    printf '%s' "$default"
}
