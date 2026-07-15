# git-mode.sh - shared GIT_MODE helpers (sourced by connect.sh forks)
# Requires: CFG_DIR, CM, PORT, LAPTOP_USER; functions sshx, warn; optional bg_pid + _tunnel_alive

if ! declare -f warn >/dev/null 2>&1; then
    warn() { printf '  [!] %s\n' "$*" >&2; }
fi

GIT_CONF="$CFG_DIR/git.conf"

get_git_mode() {
    local saved="hide"
    if [ -f "$GIT_CONF" ]; then
        saved="$(tr '[:upper:]' '[:lower:]' < "$GIT_CONF" | tr -d '[:space:]')"
    fi
    case "$saved" in
        server|on|yes|1|slow) echo server ;;
        *) echo hide ;;
    esac
}

get_active_mount_id() {
    local line
    line="$(sshx "grep -E '^ACTIVE_MOUNT=' ~/.claude-connect.conf 2>/dev/null" 2>/dev/null | tail -1 || true)"
    line="${line#ACTIVE_MOUNT=}"
    line="${line//$'\r'/}"
    line="${line//$'\n'/}"
    printf '%s' "$line"
}

get_git_mode_label() {
    case "${1:-hide}" in
        server|slow) printf 'SLOW' ;;
        *) printf 'FAST' ;;
    esac
}

_TUNNEL_BANNER_CACHE_AT=0
_TUNNEL_BANNER_CACHE_BANNER=''
_TUNNEL_BANNER_CACHE_UP=0
_TUNNEL_BANNER_CACHE_INVALID=0
_LAST_FORWARD_PROBE_AT=0

clear_tunnel_banner_cache() {
    _TUNNEL_BANNER_CACHE_AT=0
    _TUNNEL_BANNER_CACHE_BANNER=''
    _TUNNEL_BANNER_CACHE_UP=0
    _TUNNEL_BANNER_CACHE_INVALID=1
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

push_server_connect_conf() {
    local mode os="${GIT_MODE_LAPTOP_OS:-mac}" active="${ACTIVE_MOUNT_ID:-}"
    mode="$(get_git_mode)"
    sshx "printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=%s\nACTIVE_MOUNT=%s\n' '${LAPTOP_USER}' '$PORT' '${mode}' '${os}' '${active}' > ~/.claude-connect.conf && chmod 600 ~/.claude-connect.conf" 2>/dev/null || true
}

unmount_other_projects() {
    local keep="${1:-}"
    [ -n "$keep" ] || return 0
    sshx "$CM down-others '$keep'" 2>/dev/null || true
}

resolve_server_script_dir() {
    local script_dir="$1" _rel _candidate d i
    for _rel in "../server" "../../server" "../../../server"; do
        _candidate="$(cd "$script_dir/$_rel" 2>/dev/null && pwd)" || continue
        if [ -f "$_candidate/claude-mount.sh" ]; then
            printf '%s' "$_candidate"
            return 0
        fi
    done
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

    if [ "$editor_cmd" = "cursor" ]; then
        _stop_cursor_server_profile
        return
    fi
    if [ "$editor_cmd" = "code" ]; then
        _stop_code_server_profile
        return
    fi

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
    local project_id="$1" editor_cmd="${2:-}" alias_name="${3:-}" remote_path="${4:-}" skip_editor="${5:-0}"
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "CLEAR_MOUNT project=$project_id skip_editor=$skip_editor editor=$editor_cmd path=$remote_path" 'INFO'
    fi
    if [ "$skip_editor" != "1" ] && [ -n "$editor_cmd" ] && [ -n "$alias_name" ] && [ -n "$remote_path" ]; then
        stop_remote_editor "$editor_cmd" "$alias_name" "$remote_path"
    fi
    clear_tunnel_banner_cache
    if [ -n "$project_id" ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "CLEAR_MOUNT: down begin project=$project_id" 'DEBUG'
        fi
        sshx "timeout 8 $CM down '$project_id' 2>/dev/null" 2>/dev/null || true
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "CLEAR_MOUNT: down end project=$project_id" 'DEBUG'
        fi
    fi
    ACTIVE_MOUNT_ID=""
    push_server_connect_conf
}

laptop_ssh_prepare_dir() {
    mkdir -p "$HOME/.ssh"
    chmod 755 "$HOME" 2>/dev/null || true
    chmod 700 "$HOME/.ssh" 2>/dev/null || true
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
    printf '    \033[0;33mMac password (one time, fixes Remote Login):\033[0m\n' >/dev/tty 2>/dev/null || true
    read -rs LAPTOP_ADMIN_PW </dev/tty 2>/dev/null || read -rs LAPTOP_ADMIN_PW || true
    echo '' >/dev/tty 2>/dev/null || echo ''
    [ -n "${LAPTOP_ADMIN_PW:-}" ]
}

run_mac_admin_cmd() {
    local cmd="$1"
    [ "$(uname -s)" = "Darwin" ] || return 1
    [ -n "$cmd" ] || return 1
    if osascript -e "do shell script \"${cmd//\"/\\\"}\" with administrator privileges" >/dev/null 2>&1; then
        return 0
    fi
    if read_laptop_admin_password; then
        printf '%s\n' "$LAPTOP_ADMIN_PW" | sudo -S sh -c "$cmd" >/dev/null 2>&1 && return 0
    fi
    return 1
}

grant_laptop_ssh_access() {
    local user="${LAPTOP_USER:-$(whoami)}"
    run_mac_admin_cmd "dseditgroup -o edit -a '$user' -t user com.apple.access_ssh 2>/dev/null || true"
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
    local pub="$1"
    pub="${pub//$'\r'/}"
    [ -n "$pub" ] || return 1
    laptop_ssh_prepare_dir
    touch "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    awk -v pub="$pub" 'index($0, pub) == 0 && NF > 0' "$HOME/.ssh/authorized_keys" > "$HOME/.ssh/authorized_keys.tmp" 2>/dev/null \
        && mv "$HOME/.ssh/authorized_keys.tmp" "$HOME/.ssh/authorized_keys"
    rm -f "$HOME/.ssh/authorized_keys.tmp"
    chmod 600 "$HOME/.ssh/authorized_keys"
    echo "$(laptop_key_from_prefix) $pub" >> "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    xattr -c "$HOME/.ssh/authorized_keys" 2>/dev/null || true
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
    pub="$(sshx "cat ~/.ssh/claude_laptop.pub" 2>/dev/null | tr -d '\r' | grep '^ssh-' | head -1)"
    [ -n "$pub" ] || return 1
    printf '%s' "$pub"
}

verify_laptop_local_pubkey() {
    local pub="$1" frag="" key_tmp="" rc=1
    pub="${pub//$'\r'/}"
    frag="$(printf '%s' "$pub" | awk '{print $2}')"
    [ -n "$frag" ] || return 1
    grep -Fq "$frag" "$HOME/.ssh/authorized_keys" 2>/dev/null || return 1
    key_tmp="$(mktemp "${TMPDIR:-/tmp}/claude-laptop-key.XXXXXX")"
    umask 077
    if sshx "cat ~/.ssh/claude_laptop" 2>/dev/null > "$key_tmp"; then
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
    sshx "timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/${PORT} 2>/dev/null && timeout 2 nc 127.0.0.1 ${PORT} 2>/dev/null | head -1' 2>/dev/null" 2>/dev/null | tr -d '\r\n'
}

tunnel_fetch_banner() {
    local now age_ms banner
    [ -n "${PORT:-}" ] || return 1
    if [ "$_TUNNEL_BANNER_CACHE_INVALID" -eq 0 ] && [ "$_TUNNEL_BANNER_CACHE_AT" -gt 0 ]; then
        now="$(date +%s 2>/dev/null || printf '0')"
        age_ms=$(( (now - _TUNNEL_BANNER_CACHE_AT) * 1000 ))
        if [ "$age_ms" -lt 3000 ]; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_BANNER cache hit age_ms=$age_ms banner=$_TUNNEL_BANNER_CACHE_BANNER" 'TRACE'
            fi
            printf '%s' "$_TUNNEL_BANNER_CACHE_BANNER"
            return 0
        fi
    fi
    _TUNNEL_BANNER_CACHE_INVALID=0
    banner="$(tunnel_fetch_banner_raw 2>/dev/null || true)"
    _TUNNEL_BANNER_CACHE_AT="$(date +%s 2>/dev/null || printf '0')"
    _TUNNEL_BANNER_CACHE_BANNER="$banner"
    if [ -n "$banner" ] && tunnel_banner_is_this_laptop "$banner"; then
        _TUNNEL_BANNER_CACHE_UP=1
    else
        _TUNNEL_BANNER_CACHE_UP=0
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
    local banner age_ms now
    if [ "$_TUNNEL_BANNER_CACHE_INVALID" -eq 0 ] && [ "$_TUNNEL_BANNER_CACHE_AT" -gt 0 ]; then
        now="$(date +%s 2>/dev/null || printf '0')"
        age_ms=$(( (now - _TUNNEL_BANNER_CACHE_AT) * 1000 ))
        if [ "$age_ms" -lt 3000 ]; then
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "TUNNEL_UP port=$PORT up=$_TUNNEL_BANNER_CACHE_UP cache=1" 'TRACE'
            fi
            [ "$_TUNNEL_BANNER_CACHE_UP" -eq 1 ]
            return
        fi
    fi
    banner="$(tunnel_fetch_banner 2>/dev/null || true)"
    [ -n "$banner" ] || return 1
    tunnel_banner_is_this_laptop "$banner"
}

# When bg tunnel process is alive, probe forward every 30s (zombie forward detection).
sync_session_tunnel_forward() {
    local bg_pid="${1:-}" now probe_up
    [ -n "$bg_pid" ] || return 1
    kill -0 "$bg_pid" 2>/dev/null || return 1
    now="$(date +%s 2>/dev/null || printf '0')"
    if [ "$_LAST_FORWARD_PROBE_AT" -eq 0 ]; then
        _LAST_FORWARD_PROBE_AT="$now"
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "TUNNEL_SYNC: bg_alive pid=$bg_pid port=$PORT" 'TRACE'
        fi
        return 0
    fi
    if [ $(( now - _LAST_FORWARD_PROBE_AT )) -lt 30 ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "TUNNEL_SYNC: bg_alive pid=$bg_pid port=$PORT" 'TRACE'
        fi
        return 0
    fi
    _LAST_FORWARD_PROBE_AT="$now"
    clear_tunnel_banner_cache
    if tunnel_up; then
        probe_up=1
    else
        probe_up=0
    fi
    if [ "$probe_up" -eq 0 ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "TUNNEL_DROP pid=$bg_pid port=$PORT reason=bg_alive_forward_dead" 'WARN'
        fi
        return 1
    fi
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "TUNNEL_SYNC: bg_alive pid=$bg_pid port=$PORT forward_ok=1" 'TRACE'
    fi
    return 0
}

wait_for_tunnel_up() {
    local pid="${1:-}" i sleep_s
    for i in $(seq 1 12); do
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            return 1
        fi
        if tunnel_up; then
            return 0
        fi
        sleep_s="$(awk "BEGIN { s=0.25+($i-1)*0.2; print (s>1.5?1.5:s) }")"
        sleep "$sleep_s"
    done
    return 1
}

poll_tunnel_with_progress() {
    local pid="${1:-}" i sleep_s up=""
    for i in $(seq 1 12); do
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            printf '    Tunnel check... SSH process died\n'
            release_stale_tunnel_port || true
            return 1
        fi
        if tunnel_up; then
            if [ "$i" -eq 1 ]; then
                printf '    Tunnel check... port %d is open\n' "$PORT"
            else
                printf '    Tunnel check %d/12... port %d is open\n' "$i" "$PORT"
            fi
            return 0
        fi
        if [ "$i" -ge 12 ]; then
            break
        fi
        sleep_s="$(awk "BEGIN { s=0.25+($i-1)*0.2; print (s>1.5?1.5:s) }")"
        printf '    Tunnel check %d/12... port %d not open yet\n' "$i" "$PORT"
        sleep "$sleep_s"
    done
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
    sshx "sha256sum ~/.local/bin/claude-mount 2>/dev/null | awk '{print \$1}'" 2>/dev/null | tr -d '\r\n'
}

push_claude_mount_if_changed() {
    local src="$1" local_h="" remote_h=""
    [ -f "$src" ] || return 0
    local_h="$(local_file_sha256 "$src")"
    if [ -n "$local_h" ]; then
        remote_h="$(remote_claude_mount_sha256)"
        [ "$local_h" = "$remote_h" ] && return 0
    fi
    scp -o BatchMode=yes -o ConnectTimeout=20 -q "$src" "$ALIAS:~/.local/bin/claude-mount" 2>/dev/null \
        && sshx "chmod +x ~/.local/bin/claude-mount" 2>/dev/null || true
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
    local id="$1" fresh_tunnel="${2:-0}"
    if [ "$fresh_tunnel" = "0" ] && project_mount_healthy "$id"; then
        return 0
    fi
    printf '    \033[0;90mRecovering stale mounts...\033[0m\n'
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "RECOVER: begin project=$id fresh_tunnel=$fresh_tunnel" 'DEBUG'
    fi
    clear_tunnel_banner_cache
    timeout 30 sshx "$CM recover-one '$id' 2>/dev/null || timeout 30 sshx "$CM recover-if-needed '$id' 2>/dev/null || timeout 30 sshx "$CM recover" 2>/dev/null || true
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "RECOVER: end project=$id" 'DEBUG'
    fi
    printf '    \033[0;90mRecover done\033[0m\n'
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
    local id="$1" script_dir="${2:-${CONNECT_SCRIPT_DIR:-}}" mount_out="" ec=0 src=""
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

ensure_laptop_reverse_ssh_cached() {
    local pub="${1:-}" rc=0
    if [ "${LAPTOP_SSH_VERIFIED:-0}" = "1" ] && verify_laptop_reverse_ssh; then
        return 0
    fi
    ensure_laptop_reverse_ssh "$pub" || rc=$?
    [ "$rc" -eq 0 ] && LAPTOP_SSH_VERIFIED=1
    return "$rc"
}

# Reuse live tunnel when possible; sets TUNNEL_REUSED=0|1 and bg_pid.
ensure_session_tunnel() {
    TUNNEL_REUSED=0
    if [ -n "${bg_pid:-}" ] && _tunnel_alive "$bg_pid" && tunnel_up; then
        TUNNEL_REUSED=1
        return 0
    fi
    [ -n "${bg_pid:-}" ] && kill "$bg_pid" 2>/dev/null || true
    bg_pid=""
    pkill -f "ssh.*-R ${PORT}:localhost:22" 2>/dev/null || true
    local uid_str=""
    uid_str="$(sshx 'id -u' 2>/dev/null | tr -d '\r' | grep -E '^[0-9]+$' | head -1 | tr -dc '0-9')"
    if [ -n "$uid_str" ]; then
        acquire_tunnel_port "$uid_str" || true
    fi
    release_stale_tunnel_port || true
    sanitize_ssh_alias_config
    clear_tunnel_banner_cache
    _LAST_FORWARD_PROBE_AT=0
    ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=20 -o ServerAliveCountMax=5 \
        -R "${PORT}:localhost:22" "$ALIAS" 2>/dev/null &
    bg_pid=$!
    if poll_tunnel_with_progress "$bg_pid"; then
        return 0
    fi
    kill "$bg_pid" 2>/dev/null || true
    bg_pid=""
    return 1
}

release_stale_tunnel_port() {
    local banner=""
    [ -n "${PORT:-}" ] || return 0
    banner="$(fetch_tunnel_banner 2>/dev/null || true)"
    [ -n "$banner" ] || return 0
    tunnel_banner_is_this_laptop "$banner" && return 0
    sshx "pkill -u \\\$USER -f ' -p ${PORT} ' 2>/dev/null || true" 2>/dev/null || true
    sleep 1
}

save_tunnel_slot() {
    [ -n "${TUNNEL_SLOT:-}" ] || return 0
    [ -f "${CFG:-}" ] || return 0
    grep -v '^TUNNEL_SLOT=' "$CFG" > "$CFG.tmp" 2>/dev/null && mv "$CFG.tmp" "$CFG"
    echo "TUNNEL_SLOT=$TUNNEL_SLOT" >> "$CFG"
}

sanitize_ssh_alias_config() {
    local alias="${ALIAS:-claude-server}"
    [ -f "$HOME/.ssh/config" ] || return 0
    awk -v a="$alias" '
        /^[[:space:]]*Host[[:space:]]+/ {
            skip=0
            for (i = 2; i <= NF; i++) if ($i == a) skip = 1
        }
        skip && /^[[:space:]]*RemoteForward/ { next }
        { print }
    ' "$HOME/.ssh/config" > "$HOME/.ssh/config.tmp.${alias}" 2>/dev/null \
        && mv "$HOME/.ssh/config.tmp.${alias}" "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
}

acquire_tunnel_port() {
    local uid_str="$1" port_base="${CONNECT_PORT_BASE:-20000}" slot=0 port="" banner="" preferred=""
    [ -n "$uid_str" ] || return 1
    if [ -f "${CFG:-}" ]; then
        preferred="$(grep -E '^TUNNEL_SLOT=' "$CFG" 2>/dev/null | tail -1 | cut -d= -f2- | tr -dc '0-9')"
    fi
    if [ -n "$preferred" ] && [ "$preferred" -le 9 ] 2>/dev/null; then
        slot=$preferred
        port=$(( port_base + uid_str + slot ))
        if [ "$port" -le 65535 ]; then
            PORT=$port
            banner="$(fetch_tunnel_banner 2>/dev/null || true)"
            if [ -z "$banner" ] || tunnel_banner_is_this_laptop "$banner"; then
                TUNNEL_SLOT=$slot
                save_tunnel_slot
                push_server_connect_conf
                return 0
            fi
        fi
    fi
    for slot in $(seq 0 9); do
        [ "$slot" = "$preferred" ] && continue
        port=$(( port_base + uid_str + slot ))
        [ "$port" -gt 65535 ] && continue
        PORT=$port
        banner="$(fetch_tunnel_banner 2>/dev/null || true)"
        if [ -z "$banner" ] || tunnel_banner_is_this_laptop "$banner"; then
            TUNNEL_SLOT=$slot
            save_tunnel_slot
            push_server_connect_conf
            return 0
        fi
    done
    PORT=$(( port_base + uid_str ))
    TUNNEL_SLOT=0
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
    umask 077
    {
        printf '#!/bin/sh\n'
        printf 'echo '
        printf '%q' "$LAPTOP_ADMIN_PW"
        printf '\n'
    } > "$askpass"
    chmod 700 "$askpass"
    SSH_ASKPASS="$askpass" SSH_ASKPASS_REQUIRE=force \
        ssh -o BatchMode=no -o PreferredAuthentications=password,keyboard-interactive \
            -o PubkeyAuthentication=no -o StrictHostKeyChecking=accept-new \
            -o ConnectTimeout=10 -o NumberOfPasswordPrompts=1 \
            "${user}@127.0.0.1" true >/dev/null 2>&1
    rc=$?
    rm -f "$askpass"
    [ "$rc" -eq 0 ]
}

invoke_laptop_admin_ops() {
    local pub="$1" firewall_fix="${2:-0}"
    pub="$(printf '%s' "$pub" | tr -d '\r')"
    [ "$(uname -s)" = "Darwin" ] || return 1
    if [ -z "$pub" ] && [ "$firewall_fix" != "1" ]; then
        return 1
    fi

    grant_laptop_ssh_access || true
    [ "$firewall_fix" = "1" ] && fix_laptop_ssh_firewall || true
    if [ -n "$pub" ]; then
        install_laptop_server_pubkey "$pub" || return 1
    fi
    restart_laptop_sshd || true
    if [ -n "$pub" ] && verify_laptop_local_pubkey "$pub"; then
        unset LAPTOP_ADMIN_PW
        return 0
    fi
    [ -z "$pub" ] && return 0

    cycle_remote_login || true
    fix_laptop_ssh_firewall || true
    install_laptop_server_pubkey "$pub" || return 1
    restart_laptop_sshd || true
    verify_laptop_local_pubkey "$pub" && { unset LAPTOP_ADMIN_PW; return 0; }

    laptop_ssh_bootstrap_local || {
        warn "Remote Login fix needs your Mac password (GUI prompt or terminal)."
        warn "Or enable: System Settings -> General -> Sharing -> Remote Login"
        unset LAPTOP_ADMIN_PW
        return 1
    }
    fix_laptop_ssh_firewall || true
    install_laptop_server_pubkey "$pub" || return 1
    restart_laptop_sshd || true
    if verify_laptop_local_pubkey "$pub"; then
        unset LAPTOP_ADMIN_PW
        return 0
    fi
    warn "Remote Login still failing - check Mac password prompt or Sharing settings."
    unset LAPTOP_ADMIN_PW
    return 1
}

ensure_laptop_ssh_key() {
    local pub=""
    pub="$(fetch_laptop_server_pubkey "${1:-}")" || return 1
    install_laptop_server_pubkey "$pub" || return 1
    verify_laptop_local_pubkey "$pub" && return 0
    warn "Fixing Remote Login automatically..."
    invoke_laptop_admin_ops "$pub" || return 1
    verify_laptop_local_pubkey "$pub"
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

initialize_server_session() {
    local script_dir="$1"
    local port_base="${CONNECT_PORT_BASE:-20000}"
    local port_min="$port_base" _init uid_str pub_b server_dir
    local src="" git_src="" scp_pids="" push_ok=1 pid _chmod

    _init="$(sshx "id -u && (test -f ~/.ssh/claude_laptop || ssh-keygen -t ed25519 -N '' -f ~/.ssh/claude_laptop -q) && cat ~/.ssh/claude_laptop.pub" 2>/dev/null)"
    uid_str="$(printf '%s\n' "$_init" | tr -d '\r' | grep -E '^[0-9]+$' | head -1 | tr -dc '0-9')"
    pub_b="$(printf '%s\n' "$_init" | tr -d '\r' | grep '^ssh-' | head -1)"
    if ! acquire_tunnel_port "$uid_str"; then
        PORT=$(( port_base + ${uid_str:-0} ))
        TUNNEL_SLOT=0
    fi
    if [ "$PORT" -le "$port_min" ] || [ "$PORT" -gt 65535 ] || [ -z "$pub_b" ]; then
        return 1
    fi
    PUB_B="$pub_b"

    server_dir="$(resolve_server_script_dir "$script_dir" 2>/dev/null || true)"
    if [ -n "$server_dir" ]; then
        [ -f "$server_dir/claude-mount.sh" ] && src="$server_dir/claude-mount.sh"
        [ -f "$server_dir/claude-git-setup.sh" ] && git_src="$server_dir/claude-git-setup.sh"
        sshx "mkdir -p ~/.local/bin" 2>/dev/null || true
        if [ -n "$src" ]; then
            local local_h remote_h
            local_h="$(local_file_sha256 "$src" 2>/dev/null || true)"
            remote_h="$(remote_claude_mount_sha256 2>/dev/null || true)"
            if [ -z "$local_h" ] || [ "$local_h" != "$remote_h" ]; then
                scp -o BatchMode=yes -o ConnectTimeout=30 -q "$src" "$ALIAS:~/.local/bin/claude-mount" &
                scp_pids="$scp_pids $!"
            fi
        fi
        if [ -n "$git_src" ]; then
            local git_local git_remote
            git_local="$(local_file_sha256 "$git_src" 2>/dev/null || true)"
            git_remote="$(sshx "sha256sum ~/.local/bin/claude-git-setup 2>/dev/null | awk '{print \$1}'" 2>/dev/null | tr -d '\r\n')"
            if [ -z "$git_local" ] || [ "$git_local" != "$git_remote" ]; then
                scp -o BatchMode=yes -o ConnectTimeout=30 -q "$git_src" "$ALIAS:~/.local/bin/claude-git-setup" &
                scp_pids="$scp_pids $!"
            fi
        fi
    fi

    install_laptop_server_pubkey "$pub_b" || return 1

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

    for pid in $scp_pids; do
        [ -z "$pid" ] && continue
        wait_pid_timeout "$pid" server_scripts 30 || push_ok=0
    done
    if [ -n "$server_dir" ] && { [ -n "$src" ] || [ -n "$git_src" ]; }; then
        _chmod=""
        [ -n "$src" ] && _chmod="chmod +x ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=\$HOME/.local/bin:\$PATH\n' >> ~/.bashrc"
        [ -n "$git_src" ] && _chmod="${_chmod:+"$_chmod; "}chmod +x ~/.local/bin/claude-git-setup"
        [ -n "$_chmod" ] && sshx "$_chmod" 2>/dev/null || true
    fi

    [ "$push_ok" -eq 1 ]
}

configure_git_mode() {
    local cur choice cur_label saved_label
    cur="$(get_git_mode)"
    cur_label="$(get_git_mode_label "$cur")"
    echo ""
    printf '    \033[1;37mGit on server (SSHFS)\033[0m\n\n'
    if [ "$cur" = "server" ]; then
        printf '    \033[0;90mCurrent: %s (full git over SSHFS)\033[0m\n\n' "$cur_label"
    else
        printf '    \033[0;90mCurrent: %s (.git hidden on laptop)\033[0m\n\n' "$cur_label"
    fi
    printf '    \033[0;90m1  FAST - hide .git on laptop [default]\033[0m\n'
    printf '    \033[0;90m2  SLOW - keep .git on mount for git on server\033[0m\n\n'
    read -rp "    > " choice
    choice="$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')"
    case "$choice" in
        1|off|hide|fast|"") printf 'hide\n' > "$GIT_CONF" ;;
        2|on|server|slow) printf 'server\n' > "$GIT_CONF" ;;
        *) warn "Invalid choice."; return ;;
    esac
    push_server_connect_conf
    echo ""
    saved_label="$(get_git_mode_label "$(get_git_mode)")"
    printf '    \033[0;32mSaved: git %s.\033[0m\n' "$saved_label"
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
            else
                _action="q"
                _got_key=1
            fi
        else
            _action="r"
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

merge_cursor_auth_into_local_db() {
    local gs="$1" payload="$2" attempt db="${1}/state.vscdb" pairs_file
    [ -n "$payload" ] || return 1
    cursor_sqlite3_available || return 1
    pairs_file="$(mktemp "${TMPDIR:-/tmp}/cursor-auth-pairs.XXXXXX")"
    cursor_auth_payload_to_pairs "$payload" "$pairs_file" || { rm -f "$pairs_file"; return 1; }
    for attempt in 1 2 3 4 5; do
        if cursor_sqlite_merge_pairs "$db" "$pairs_file"; then
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
                | .["telemetry.devDeviceId"] = ($remote["telemetry.devDeviceId"] // .["telemetry.devDeviceId"])
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
    local db="${1:-}" gs synced_at_path synced_at golden_exported="" reasons=""
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
    if declare -F test_personal_cursor_dominant >/dev/null 2>&1 && test_personal_cursor_dominant; then
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
    if [ "$force" != "1" ] && [ "$golden_current" -eq 1 ] && [ -f "$db" ] && local_cursor_auth_complete "$db"; then
        CURSOR_AUTH_SYNC_RESULT=ok
        declare -F connect_log >/dev/null 2>&1 && connect_log "AUTH_SYNC: skip already_complete golden_exported_at=$golden_exported" 'DEBUG'
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
            key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
            case "$key" in
                m) printf 'm'; return 0 ;;
                c) printf 'c'; return 0 ;;
                x) printf 'x'; return 0 ;;
            esac
        fi
    done
    printf '\n    Default %s\n' "$default"
    printf '%s' "$default"
}
