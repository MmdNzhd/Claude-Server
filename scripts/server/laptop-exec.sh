#!/usr/bin/env bash
# laptop-exec - SSH-first: fast + accurate project ops on laptop via reverse tunnel.
set -euo pipefail

CONNECT_CONF="$HOME/.claude-connect.conf"
CONF_DIR="$HOME/.claude-mounts.d"
KEY="$HOME/.ssh/claude_laptop"
KNOWN_HOSTS="$HOME/.ssh/known_hosts_claude_mount"
CACHE_DIR="$HOME/.cache/laptop-exec"
CONTROL_PATH="$CACHE_DIR/cm-%C"
SSHFS_CACHE="$CACHE_DIR/sshfs-cache.tsv"
GIT_DIR_CACHE="$CACHE_DIR/git-dir-cache.tsv"
SSHFS_CACHE_TTL=45

LAPTOP_USER="" TUNNEL_PORT="" LAPTOP_OS="windows" ACTIVE_MOUNT="" GIT_MODE="off"
PROJECT_ID="" WORKSPACE_PATH="" REMOTE_PATH="" LOCAL_PATH=""

# Durable multi-agent audit log (hooks share the same helper).
_LE_AUDIT_SRC=""
for _LE_AUDIT_SRC in \
    "${HOME}/.cursor/hooks/laptop-exec-audit-log.sh" \
    "/usr/local/lib/claude-server/cursor-hooks/laptop-exec-audit-log.sh"; do
    if [ -f "$_LE_AUDIT_SRC" ]; then
        # shellcheck source=/dev/null
        . "$_LE_AUDIT_SRC"
        break
    fi
done
unset _LE_AUDIT_SRC
if ! declare -F _le_audit_log >/dev/null 2>&1; then
    _le_audit_log() { :; }
    _le_audit_trunc() { printf '%s' "$1"; }
    _le_audit_slots_busy() { printf '0'; }
    _le_audit_session_fields() { printf 'tunnel_port=?'; }
fi

# Real CLI argv from main() — must not reuse $msg (agents need the failing command).
_LE_LAST_ARGV=""

_die() {
    local msg="$*"
    local av="${_LE_LAST_ARGV:-}"
    _le_audit_log ERROR DIE "msg=$(_le_audit_trunc "$msg" 300)" \
        "project=${PROJECT_ID:-?}" "$(_le_audit_session_fields)" \
        "slots_busy=$(_le_audit_slots_busy)/8" \
        "argv=$(_le_audit_trunc "${av:-unknown}" 200)"
    echo "laptop-exec: $msg" >&2
    exit 1
}

# Shared NEXT hints (agents map Cursor tool APIs onto laptop-exec — steer them back).
_RG_FORBIDDEN='-i/-l/-n/-A/-B/-C/-m/-g/--glob/--type/--max-count/--pathspec'
_rg_next() {
    printf 'NEXT: mount MOUNTED → Cursor Grep on /home/%s/mounts/%s/ first (not LE rg). Else: laptop-exec rg [-p ID] PATTERN [pathspec...] — NO --glob/-A/--type (also NO %s); pathspecs like src/ or '\''*.cs'\''.' \
        "${USER:-USER}" "${PROJECT_ID:-PROJECT}" "$_RG_FORBIDDEN"
}
_read_next() {
    printf 'NEXT: mount MOUNTED → Cursor Read /home/%s/mounts/%s/REL with offset/limit. Else: laptop-exec read [-p ID] REL — ONE relative file only (no --offset/--limit, no multi-file).' \
        "${USER:-USER}" "${PROJECT_ID:-PROJECT}"
}

# Abort tracking: Cursor/tool cancel often SIGTERM this bash while timeout/ssh keep running
# (proven 2026-07-26: TERM LE → children ALIVE, Windows work continued). Trap kills the tree.
_LE_CMD_CHILD=0
_LE_CMD_ENDED=0
_LE_ACTIVE_CMD=""
_LE_ABORT_SLOT_FD=""
_LE_WIN_JOB_ID=""

_le_kill_tree() {
    local root="$1" c
    [ -n "${root:-}" ] || return 0
    case "$root" in *[!0-9]*) return 0 ;; esac
    [ "$root" -gt 1 ] 2>/dev/null || return 0
    while read -r c; do
        c=$(echo "$c" | tr -d ' ')
        [ -n "$c" ] || continue
        _le_kill_tree "$c"
    done < <(ps -o pid= --ppid "$root" 2>/dev/null || true)
    kill -TERM "$root" 2>/dev/null || true
}

_le_remote_kill_win_job() {
    # Best-effort: after local ssh dies, Windows powershell can outlive the channel.
    # Job id is visible on the outer powershell -Command line (not only inside EncodedCommand).
    local jid="${_LE_WIN_JOB_ID:-}" opts
    [ -n "$jid" ] || return 0
    [ "${LAPTOP_OS:-}" = "windows" ] || return 0
    [ -n "${TUNNEL_PORT:-}" ] && [ -n "${LAPTOP_USER:-}" ] || return 0
    [ -f "$KEY" ] || return 0
    mapfile -t opts < <(_ssh_common_opts)
    # taskkill /T kills the whole Windows process tree (outer LE_JOB_ID wrapper + EncodedCommand + -File).
    local remote_ps
    remote_ps="Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -and \$_.CommandLine -like '*${jid}*' } | ForEach-Object { Start-Process -FilePath taskkill.exe -ArgumentList @('/F','/T','/PID',\"\$(\$_.ProcessId)\") -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue }"
    if command -v timeout >/dev/null 2>&1; then
        timeout -k 2 --foreground 10 ssh -n "${opts[@]}" -i "$KEY" -p "$TUNNEL_PORT" \
            "${LAPTOP_USER}@127.0.0.1" \
            "powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command \"${remote_ps}\"" \
            >/dev/null 2>&1 || true
    else
        ssh -n "${opts[@]}" -i "$KEY" -p "$TUNNEL_PORT" \
            "${LAPTOP_USER}@127.0.0.1" \
            "powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command \"${remote_ps}\"" \
            >/dev/null 2>&1 || true
    fi
    _LE_WIN_JOB_ID=""
}

_le_abort_cleanup() {
    local reason="${1:-aborted}" exit_code="${2:-143}"
    if [ "${_LE_CMD_CHILD:-0}" -gt 0 ]; then
        _le_kill_tree "$_LE_CMD_CHILD"
        sleep 0.2
        _le_kill_tree "$_LE_CMD_CHILD"
        kill -KILL "$_LE_CMD_CHILD" 2>/dev/null || true
        _LE_CMD_CHILD=0
    fi
    if [ -n "${_LE_ABORT_SLOT_FD:-}" ]; then
        eval "exec ${_LE_ABORT_SLOT_FD}>&-" 2>/dev/null || true
        _LE_ABORT_SLOT_FD=""
    fi
    _le_remote_kill_win_job
    if [ "${_LE_CMD_ENDED:-0}" -eq 0 ] && [ -n "${_LE_ACTIVE_CMD:-}" ]; then
        _LE_CMD_ENDED=1
        # Literal meaning=aborted (contract/tests grep this exact token).
        _le_audit_log WARN CMD_END "cmd=${_LE_ACTIVE_CMD}" "exit=${exit_code}" \
            "meaning=aborted" "abort_reason=${reason}" \
            "project=${PROJECT_ID:-${ACTIVE_MOUNT:-?}}" \
            "$(_le_audit_session_fields)" "slots_busy=$(_le_audit_slots_busy)/8" \
            "hint=Parent aborted; killed timeout/ssh tree (slot released)."
    fi
}

_le_on_signal() {
    _le_abort_cleanup aborted 143
    trap - TERM INT HUP
    exit 143
}

_expand_home() {
    local p="$1"
    case "$p" in
        "~/"*) printf '%s' "${HOME}/${p#~/}" ;;
        "~") printf '%s' "$HOME" ;;
        *) printf '%s' "$p" ;;
    esac
}

_ensure_cache_dir() { mkdir -p "$CACHE_DIR" 2>/dev/null || true; }

_load_global() {
    GIT_MODE="off"; LAPTOP_OS="windows"
    if [ -f "$CONNECT_CONF" ]; then
        while IFS='=' read -r k v; do
            v="${v#\"}"; v="${v%\"}"
            case "$k" in
                LAPTOP_USER) LAPTOP_USER="$v" ;;
                TUNNEL_PORT|PORT) [ -n "$TUNNEL_PORT" ] || TUNNEL_PORT="$v" ;;
                GIT_MODE|git_mode) GIT_MODE="$v" ;;
                LAPTOP_OS|laptop_os) LAPTOP_OS="$v" ;;
                ACTIVE_MOUNT|active_mount) ACTIVE_MOUNT="$v" ;;
            esac
        done < "$CONNECT_CONF"
    fi
    # Match connect client: non-overlapping 10-port block per UID
    # (20000 + (UID-1000)*10 + slot). Slot 0 is the laptop-exec default when
    # conf omitted TUNNEL_PORT. NEVER use legacy 20000+UID (Smart -> 21002).
    if [ -z "$TUNNEL_PORT" ]; then
        _uid=$(id -u)
        _deprecated=$((20000 + _uid))
        if [ "$_uid" -ge 1000 ] 2>/dev/null; then
            _fallback=$((20000 + (_uid - 1000) * 10))
        else
            _fallback=20020
        fi
        # If formula fallback is actually listening, heal conf (self-heal may have
        # stripped TUNNEL_PORT while tunnel stayed up — amir 735× WARN day).
        _tp_live=0
        if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/${_fallback}" 2>/dev/null; then
            _tp_live=1
        fi
        _tp_stamp="${HOME:-/tmp}/.cache/laptop-exec/tunnel-port-missing.stamp"
        _tp_now=$(date +%s 2>/dev/null || echo 0)
        _tp_prev=0
        [ -f "$_tp_stamp" ] && _tp_prev=$(cat "$_tp_stamp" 2>/dev/null || echo 0)
        if [ "$_tp_live" -eq 1 ]; then
            if [ -f "$CONNECT_CONF" ]; then
                grep -vE '^(TUNNEL_PORT|PORT)=' "$CONNECT_CONF" > "${CONNECT_CONF}.tpnew" 2>/dev/null || true
                printf 'TUNNEL_PORT=%s\n' "$_fallback" >> "${CONNECT_CONF}.tpnew" 2>/dev/null || true
                mv -f "${CONNECT_CONF}.tpnew" "$CONNECT_CONF" 2>/dev/null || true
                chmod 600 "$CONNECT_CONF" 2>/dev/null || true
            fi
            if [ -z "${_LE_TUNNEL_WARNED:-}" ] || [ $((_tp_now - _tp_prev)) -ge 60 ]; then
                echo "info: TUNNEL_PORT healed to ${_fallback} (was missing in conf; tunnel live)" >&2
                if declare -F _le_audit_log >/dev/null 2>&1; then
                    _le_audit_log INFO TUNNEL_PORT_HEALED \
                        "port=${_fallback}" "deprecated_would_be=${_deprecated}" \
                        "hint=conf lacked TUNNEL_PORT; fallback was live — rewritten"
                fi
                mkdir -p "$(dirname "$_tp_stamp")" 2>/dev/null || true
                printf '%s' "$_tp_now" > "$_tp_stamp" 2>/dev/null || true
                _LE_TUNNEL_WARNED=1
            fi
        else
            if [ -z "${_LE_TUNNEL_WARNED:-}" ] || [ $((_tp_now - _tp_prev)) -ge 60 ]; then
                echo "warn: TUNNEL_PORT_MISSING fallback=${_fallback} deprecated_would_be=${_deprecated} (reconnect connect.bat/sh)" >&2
                if declare -F _le_audit_log >/dev/null 2>&1; then
                    _le_audit_log WARN TUNNEL_PORT_MISSING \
                        "fallback=${_fallback}" "deprecated_would_be=${_deprecated}" \
                        "hint=reconnect connect.bat/sh"
                fi
                mkdir -p "$(dirname "$_tp_stamp")" 2>/dev/null || true
                printf '%s' "$_tp_now" > "$_tp_stamp" 2>/dev/null || true
                _LE_TUNNEL_WARNED=1
            fi
        fi
        TUNNEL_PORT=$_fallback
        unset _uid _deprecated _fallback _tp_stamp _tp_now _tp_prev _tp_live
    else
        # Legacy heal: conf still has deprecated 20000+UID (e.g. Smart 21002)
        # while formula port (20000+(UID-1000)*10) is the live tunnel. Only
        # rewrite when TUNNEL_PORT equals legacy exactly AND formula is TCP-live
        # — never clobber arbitrary wrong ports or rewrite to a dead formula.
        _uid=$(id -u)
        _legacy=$((20000 + _uid))
        if [ "$_uid" -ge 1000 ] 2>/dev/null; then
            _formula=$((20000 + (_uid - 1000) * 10))
        else
            _formula=20020
        fi
        if [ "$TUNNEL_PORT" = "$_legacy" ] && [ "$_legacy" != "$_formula" ]; then
            _tp_live=0
            if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/${_formula}" 2>/dev/null; then
                _tp_live=1
            fi
            _tp_stamp="${HOME:-/tmp}/.cache/laptop-exec/tunnel-port-legacy.stamp"
            _tp_now=$(date +%s 2>/dev/null || echo 0)
            _tp_prev=0
            [ -f "$_tp_stamp" ] && _tp_prev=$(cat "$_tp_stamp" 2>/dev/null || echo 0)
            if [ "$_tp_live" -eq 1 ]; then
                if [ -f "$CONNECT_CONF" ]; then
                    grep -vE '^(TUNNEL_PORT|PORT)=' "$CONNECT_CONF" > "${CONNECT_CONF}.tpnew" 2>/dev/null || true
                    printf 'TUNNEL_PORT=%s\n' "$_formula" >> "${CONNECT_CONF}.tpnew" 2>/dev/null || true
                    mv -f "${CONNECT_CONF}.tpnew" "$CONNECT_CONF" 2>/dev/null || true
                    chmod 600 "$CONNECT_CONF" 2>/dev/null || true
                fi
                TUNNEL_PORT=$_formula
                if [ -z "${_LE_TUNNEL_LEGACY_WARNED:-}" ] || [ $((_tp_now - _tp_prev)) -ge 60 ]; then
                    echo "info: TUNNEL_PORT legacy healed to ${_formula} (was deprecated ${_legacy}; formula live)" >&2
                    if declare -F _le_audit_log >/dev/null 2>&1; then
                        _le_audit_log INFO TUNNEL_PORT_LEGACY_HEALED \
                            "port=${_formula}" "deprecated=${_legacy}" \
                            "hint=conf had legacy 20000+UID; formula was live — rewritten"
                    fi
                    mkdir -p "$(dirname "$_tp_stamp")" 2>/dev/null || true
                    printf '%s' "$_tp_now" > "$_tp_stamp" 2>/dev/null || true
                    _LE_TUNNEL_LEGACY_WARNED=1
                fi
            else
                # Formula not listening — do not rewrite (avoid false heal).
                if [ -z "${_LE_TUNNEL_LEGACY_WARNED:-}" ] || [ $((_tp_now - _tp_prev)) -ge 60 ]; then
                    echo "warn: TUNNEL_PORT_LEGACY_STALE port=${_legacy} formula=${_formula} not live (reconnect connect.bat/sh)" >&2
                    if declare -F _le_audit_log >/dev/null 2>&1; then
                        _le_audit_log WARN TUNNEL_PORT_LEGACY_STALE \
                            "port=${_legacy}" "formula=${_formula}" \
                            "hint=legacy port in conf but formula not listening — not rewritten"
                    fi
                    mkdir -p "$(dirname "$_tp_stamp")" 2>/dev/null || true
                    printf '%s' "$_tp_now" > "$_tp_stamp" 2>/dev/null || true
                    _LE_TUNNEL_LEGACY_WARNED=1
                fi
            fi
            unset _tp_live _tp_stamp _tp_now _tp_prev
        fi
        unset _uid _legacy _formula
    fi
    case "${GIT_MODE,,}" in
        server|on|yes|1|slow) GIT_MODE="server" ;;
        hide|fast) GIT_MODE="hide" ;;
        *) GIT_MODE="off" ;;
    esac
    case "${LAPTOP_OS,,}" in mac|darwin|osx) LAPTOP_OS="mac" ;; *) LAPTOP_OS="windows" ;; esac
    _ensure_cache_dir
}

_load_project() {
    local project_id="$1"
    local conf="$CONF_DIR/${project_id}.conf"
    [ -f "$conf" ] || _die "unknown project '$project_id' (no $conf)"
    REMOTE_PATH=""; LOCAL_PATH=""
    while IFS='=' read -r k v; do
        v="${v#\"}"; v="${v%\"}"
        case "$k" in
            rpath|REMOTE_PATH) REMOTE_PATH="$v" ;;
            lpath|LOCAL_PATH) LOCAL_PATH="$v" ;;
        esac
    done < "$conf"
    REMOTE_PATH="${REMOTE_PATH//\\//}"
    LOCAL_PATH="$(_expand_home "$LOCAL_PATH")"
    [ -n "$REMOTE_PATH" ] || _die "no remote path in $conf"
}

_mount_path_for_project() {
    local pid="$1" mp="" conf lp="" k v
    conf="$CONF_DIR/${pid}.conf"
    if [ -f "$conf" ]; then
        while IFS='=' read -r k v; do
            v="${v#\"}"; v="${v%\"}"
            case "$k" in lpath|LOCAL_PATH) lp="$(_expand_home "$v")" ;; esac
        done < "$conf"
    fi
    mp="${lp:-$HOME/mounts/$pid}"
    printf '%s' "$mp"
}

_project_id_from_path() {
    local path="$1"
    path="${path//\\//}"
    if [[ "$path" =~ /mounts/([^/]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

_guess_workspace_path() {
    local p=""
    for p in "$WORKSPACE_PATH" "${LAPTOP_EXEC_WORKSPACE:-}" "${CURSOR_WORKSPACE:-}" "${CURSOR_PROJECT_DIR:-}" "${PWD:-}"; do
        [ -n "$p" ] || continue
        p="${p//\\//}"
        if [[ "$p" == *"/mounts/"* ]]; then
            printf '%s' "$p"
            return 0
        fi
    done
    return 1
}

_sshfs_state_uncached() {
    local mp="$1" out="" rc=0
    [ -n "$mp" ] || { echo "UNKNOWN"; return; }
    mp="$(_expand_home "$mp")"
    if ! timeout 1 stat "$mp" >/dev/null 2>&1; then echo "NOT_MOUNTED"; return; fi
    # Prefer /proc/mounts over mountpoint -q (hangs on frozen SSHFS).
    if ! grep -F " $mp " /proc/mounts >/dev/null 2>&1; then echo "NOT_MOUNTED"; return; fi
    out=$(timeout 2 ls "$mp" 2>&1) || rc=$?
    if [ "$rc" -ne 0 ] || [[ "$out" == *"Input/output error"* ]] || [[ "$out" == *"Transport endpoint"* ]]; then
        echo "STALE"; return
    fi
    echo "MOUNTED"
}

_sshfs_state() {
    local mp="$1" now="" cached="" ts="" state=""
    [ -n "$mp" ] || { echo "UNKNOWN"; return; }
    mp="$(_expand_home "$mp")"
    now=$(date +%s)
    _ensure_cache_dir
    if [ -f "$SSHFS_CACHE" ]; then
        cached=$(grep -F "$mp|" "$SSHFS_CACHE" 2>/dev/null | tail -1 || true)
        if [ -n "$cached" ]; then
            ts="${cached##*|}"
            state="${cached#*|}"; state="${state%%|*}"
            if [ $((now - ts)) -le "$SSHFS_CACHE_TTL" ]; then
                echo "$state"; return
            fi
        fi
    fi
    state="$(_sshfs_state_uncached "$mp")"
    (
        flock 9 || exit 0
        grep -v -F "$mp|" "$SSHFS_CACHE" 2>/dev/null > "${SSHFS_CACHE}.tmp" || true
        printf '%s|%s|%s\n' "$mp" "$state" "$now" >> "${SSHFS_CACHE}.tmp"
        mv "${SSHFS_CACHE}.tmp" "$SSHFS_CACHE"
    ) 9>"$CACHE_DIR/cache.lock"
    echo "$state"
}

_ssh_common_opts() {
    printf '%s\n' \
        -o BatchMode=yes \
        -o ConnectTimeout=8 \
        -o ServerAliveInterval=15 \
        -o ServerAliveCountMax=3 \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$KNOWN_HOSTS" \
        -o ControlMaster=auto \
        -o "ControlPath=$CONTROL_PATH" \
        -o ControlPersist=300
}

_laptop_ssh() {
    local opts _lock="$CACHE_DIR/cm.lock" _s _attempt=1 _rc=0
    local _slot_fd="" _i _round
    mkdir -p "$CACHE_DIR"

    # Cap concurrent mux channels at 8 (under live MaxSessions; connect sets MaxSessions 32 — after reconnect can raise slots).
    # Without this, agent N+1 fails with 255; old code then killed the shared mux and
    # cascaded failures across ALL agents ("everyone blocked").
    for _round in $(seq 1 240); do
        for _i in 0 1 2 3 4 5 6 7; do
            exec {_slot_fd}<>"$CACHE_DIR/slot-${_i}.lock"
            if flock -n "$_slot_fd" 2>/dev/null; then
                break 2
            fi
            eval "exec ${_slot_fd}>&-"
            _slot_fd=""
        done
        sleep 0.2
    done
    if [ -z "$_slot_fd" ]; then
        _le_audit_log ERROR SLOT_FULL "max=8" "waited_rounds=240" "waited_ms=48000"             "project=${PROJECT_ID:-?}" "$(_le_audit_session_fields)"             "caller=_laptop_ssh" "hint=Wait; do NOT open new TCP/mux. Prefer ≤4 parallel agents."
        echo "laptop-exec: session slots full (max 8 concurrent SSH channels). Wait; do NOT open new TCP/mux." >&2
        return 255
    fi
    _LE_ABORT_SLOT_FD="$_slot_fd"
    if [ "${_round:-1}" -gt 5 ]; then
        _le_audit_log WARN SLOT_WAIT "rounds=${_round}" "waited_ms=$((_round * 200))"             "slots_busy=$(_le_audit_slots_busy)/8" "project=${PROJECT_ID:-?}"             "$(_le_audit_session_fields)" "caller=_laptop_ssh"
    fi

    # Cleanup dead sockets only (never delete cm.lock / slot-*.lock).
    shopt -s nullglob
    for _s in "$CACHE_DIR"/cm-*; do
        case "$_s" in *.lock|*/slot-*) continue ;; esac
        [[ "$_s" == *.lock ]] && continue
        case "$_s" in */cm.lock) continue ;; esac
        ssh -O check -o "ControlPath=$_s" -o ControlMaster=no -o BatchMode=yes \
            -o ConnectTimeout=1 -i "$KEY" -p "${TUNNEL_PORT}" \
            "${LAPTOP_USER}@127.0.0.1" >/dev/null 2>&1 && continue
        rm -f "$_s" 2>/dev/null || true
    done
    shopt -u nullglob

    mapfile -t opts < <(_ssh_common_opts)
    while [ "$_attempt" -le 4 ]; do
        # Brief lock for master bring-up only (ConnectTimeout 3s, not full command).
        (
            # If we cannot take cm.lock, do NOT race ssh -fN (multi-agent ControlSocket storm).
            if ! flock -w 8 9; then
                exit 0
            fi
            if ! ssh -O check -o "ControlPath=$CONTROL_PATH" -o ControlMaster=no \
                -o BatchMode=yes -o ConnectTimeout=1 -i "$KEY" -p "$TUNNEL_PORT" \
                "${LAPTOP_USER}@127.0.0.1" >/dev/null 2>&1; then
                ssh -fN -o BatchMode=yes -o ConnectTimeout=3 \
                    -o StrictHostKeyChecking=accept-new \
                    -o UserKnownHostsFile="$KNOWN_HOSTS" \
                    -o ControlMaster=yes -o "ControlPath=$CONTROL_PATH" \
                    -o ControlPersist=300 \
                    -i "$KEY" -p "$TUNNEL_PORT" \
                    "${LAPTOP_USER}@127.0.0.1" >/dev/null 2>&1 || true
            fi
        ) 9>"$_lock"

        set +e
        # Background + wait so TERM/INT trap can kill timeout/ssh (foreground wait alone orphans them).
        if [ -n "${LAPTOP_EXEC_CMD_TIMEOUT:-}" ] && command -v timeout >/dev/null 2>&1; then
            # Bound long searches so hung Select-String cannot pin mux slots for hours.
            timeout -k 5 --foreground "$LAPTOP_EXEC_CMD_TIMEOUT" \
                ssh -n "${opts[@]}" -i "$KEY" -p "$TUNNEL_PORT" "${LAPTOP_USER}@127.0.0.1" "$@" &
            _LE_CMD_CHILD=$!
            wait "$_LE_CMD_CHILD"
            _rc=$?
            _LE_CMD_CHILD=0
            if [ "$_rc" -eq 124 ]; then
                _le_audit_log ERROR CMD_TIMEOUT "timeout_s=${LAPTOP_EXEC_CMD_TIMEOUT}"                     "project=${PROJECT_ID:-?}" "$(_le_audit_session_fields)"                     "slots_busy=$(_le_audit_slots_busy)/8" "attempt=${_attempt}"                     "hint=Hung remote cmd pinned a mux slot; reduce parallel agents or narrow pathspecs."
                echo "laptop-exec: command timed out after ${LAPTOP_EXEC_CMD_TIMEOUT}s" >&2
            fi
        else
            ssh -n "${opts[@]}" -i "$KEY" -p "$TUNNEL_PORT" "${LAPTOP_USER}@127.0.0.1" "$@" &
            _LE_CMD_CHILD=$!
            wait "$_LE_CMD_CHILD"
            _rc=$?
            _LE_CMD_CHILD=0
        fi
        set -e
        if [ "$_rc" -ne 255 ]; then
            eval "exec ${_slot_fd}>&-"
            _LE_ABORT_SLOT_FD=""
            return "$_rc"
        fi
        # Master dead? recreate. If master alive, do NOT ssh -O exit (that cascades).
        if ! ssh -O check -o "ControlPath=$CONTROL_PATH" -o ControlMaster=no \
            -o BatchMode=yes -o ConnectTimeout=1 -i "$KEY" -p "$TUNNEL_PORT" \
            "${LAPTOP_USER}@127.0.0.1" >/dev/null 2>&1; then
            _le_audit_log WARN MUX_RECREATE "attempt=${_attempt}" "rc=${_rc}"                 "project=${PROJECT_ID:-?}" "$(_le_audit_session_fields)"                 "slots_busy=$(_le_audit_slots_busy)/8" "hint=ControlMaster dead; wiping stale cm-* sockets (not slot locks)."
            shopt -s nullglob
            for _s in "$CACHE_DIR"/cm-*; do
                case "$_s" in *.lock) continue ;; esac
                rm -f "$_s" 2>/dev/null || true
            done
            shopt -u nullglob
        else
            _le_audit_log WARN SSH_RETRY "attempt=${_attempt}" "rc=255"                 "project=${PROJECT_ID:-?}" "$(_le_audit_session_fields)"                 "mux=alive" "hint=Exit 255 with live mux — usually slot pressure or remote sshd flake; do NOT kill mux."
        fi
        sleep "0.$((5 + RANDOM % 5))"
        _attempt=$((_attempt + 1))
    done
    eval "exec ${_slot_fd}>&-" 2>/dev/null || true
    _LE_ABORT_SLOT_FD=""
    return "$_rc"
}

_laptop_scp_to() {
    local local_file="$1" rpath="$2" rel_file="$3"
    local opts _attempt=1 _rc=0
    mapfile -t opts < <(_ssh_common_opts)
    rel_file="${rel_file#./}"; rel_file="${rel_file//\\//}"
    # scp reuses mux via ControlPath; go through _laptop_ssh-equivalent slot via flock file
    local _slot_fd="" _i _round
    for _round in $(seq 1 240); do
        for _i in 0 1 2 3 4 5 6 7; do
            exec {_slot_fd}<>"$CACHE_DIR/slot-${_i}.lock"
            if flock -n "$_slot_fd" 2>/dev/null; then
                break 2
            fi
            eval "exec ${_slot_fd}>&-"
            _slot_fd=""
        done
        sleep 0.2
    done
    if [ -z "$_slot_fd" ]; then
        _le_audit_log ERROR SLOT_FULL "max=8" "waited_rounds=240" "waited_ms=48000"             "project=${PROJECT_ID:-?}" "$(_le_audit_session_fields)"             "caller=_laptop_scp_to" "hint=Wait; do NOT open new TCP/mux."
        echo "laptop-exec: session slots full (max 8 concurrent SSH channels). Wait; do NOT open new TCP/mux." >&2
        return 255
    fi
    if [ "${_round:-1}" -gt 5 ]; then
        _le_audit_log WARN SLOT_WAIT "rounds=${_round}" "waited_ms=$((_round * 200))"             "slots_busy=$(_le_audit_slots_busy)/8" "project=${PROJECT_ID:-?}"             "$(_le_audit_session_fields)" "caller=_laptop_scp_to"
    fi
    (
        if flock -w 8 9; then
            if ! ssh -O check -o "ControlPath=$CONTROL_PATH" -o ControlMaster=no \
                -o BatchMode=yes -o ConnectTimeout=1 -i "$KEY" -p "$TUNNEL_PORT" \
                "${LAPTOP_USER}@127.0.0.1" >/dev/null 2>&1; then
                ssh -fN -o BatchMode=yes -o ConnectTimeout=3 \
                    -o StrictHostKeyChecking=accept-new \
                    -o UserKnownHostsFile="$KNOWN_HOSTS" \
                    -o ControlMaster=yes -o "ControlPath=$CONTROL_PATH" \
                    -o ControlPersist=300 \
                    -i "$KEY" -p "$TUNNEL_PORT" \
                    "${LAPTOP_USER}@127.0.0.1" >/dev/null 2>&1 || true
            fi
        fi
    ) 9>"$CACHE_DIR/cm.lock"
    local _scp_t="${LAPTOP_EXEC_SCP_TIMEOUT:-120}"
    while [ "$_attempt" -le 4 ]; do
        set +e
        if [ -n "$_scp_t" ] && [ "$_scp_t" != "0" ] && command -v timeout >/dev/null 2>&1; then
            timeout --foreground "$_scp_t" scp -q "${opts[@]}" -i "$KEY" -P "$TUNNEL_PORT" \
                "$local_file" "${LAPTOP_USER}@127.0.0.1:${rpath}/${rel_file}"
        else
            scp -q "${opts[@]}" -i "$KEY" -P "$TUNNEL_PORT" \
                "$local_file" "${LAPTOP_USER}@127.0.0.1:${rpath}/${rel_file}"
        fi
        _rc=$?
        set -e
        if [ "$_rc" -eq 0 ]; then
            [ -n "$_slot_fd" ] && eval "exec ${_slot_fd}>&-"
            return 0
        fi
        [ "$_rc" -ne 255 ] && { [ -n "$_slot_fd" ] && eval "exec ${_slot_fd}>&-"; return "$_rc"; }
        sleep "0.$((5 + RANDOM % 5))"
        _attempt=$((_attempt + 1))
    done
    [ -n "$_slot_fd" ] && eval "exec ${_slot_fd}>&-"
    return "$_rc"
}

_ensure_remote_parent_dir() {
    local rpath="$1" file="$2" dir="${file%/*}"
    [ "$dir" = "$file" ] && return 0
    if [ "$LAPTOP_OS" = "mac" ]; then _run_in_project "$rpath" mkdir -p "$dir"; return; fi
    local win_path="${rpath//\//\\}" win_dir="${dir//\//\\}"
    _laptop_ssh "powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command \"New-Item -ItemType Directory -Force -Path '${win_path}\\${win_dir}' | Out-Null\""
}

_normalize_arg() { printf '%s' "${1//\\//}"; }

_detect_git_dir() {
    local rpath="$1" win_path="${rpath//\//\\}" out=""
    if [ "$LAPTOP_OS" = "mac" ]; then
        if _run_in_project "$rpath" test -d .git.server-session 2>/dev/null; then echo .git.server-session; return; fi
        if _run_in_project "$rpath" test -d .git 2>/dev/null; then echo .git; return; fi
        echo none; return
    fi
    out=$(_laptop_ssh "powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command \"if (Test-Path -LiteralPath '${win_path}\\.git.server-session\\HEAD') { '.git.server-session' } elseif (Test-Path -LiteralPath '${win_path}\\.git\\HEAD') { '.git' } else { 'none' }\"" 2>/dev/null | tr -d '\r' | head -1)
    printf '%s' "$out"
}

_detect_git_dir_cached() {
    local rpath="$1" pid="${PROJECT_ID:-$ACTIVE_MOUNT}" now="" line="" ts="" dir=""
    [ -n "$pid" ] || return 1
    now=$(date +%s)
    _ensure_cache_dir
    if [ -f "$GIT_DIR_CACHE" ]; then
        line=$(grep -F "${pid}|" "$GIT_DIR_CACHE" 2>/dev/null | tail -1 || true)
        if [ -n "$line" ]; then
            ts="${line##*|}"
            dir="${line#*|}"; dir="${dir%%|*}"
            if [ "$dir" != "none" ] && [ $((now - ts)) -le 300 ]; then
                printf '%s' "$dir"; return 0
            fi
        fi
    fi
    dir="$(_detect_git_dir "$rpath")"
    (
        flock 9 || exit 0
        grep -v -F "${pid}|" "$GIT_DIR_CACHE" 2>/dev/null > "${GIT_DIR_CACHE}.tmp" || true
        printf '%s|%s|%s\n' "$pid" "$dir" "$now" >> "${GIT_DIR_CACHE}.tmp"
        mv "${GIT_DIR_CACHE}.tmp" "$GIT_DIR_CACHE"
    ) 9>"$CACHE_DIR/cache.lock"
    [ "$dir" != "none" ] || return 1
    printf '%s' "$dir"
}

_run_in_project() {
    local rpath="$1"; shift
    if [ "$LAPTOP_OS" = "mac" ]; then
        local cmd=""; printf -v cmd '%q ' "$@"
        _laptop_ssh "bash -lc 'cd $(printf '%q' "$rpath") && $cmd'"; return
    fi
    # Windows: avoid nested-quote breakage for | & <> () and paths (no cmd.exe).
    # Encode a PowerShell Set-Location + argv splat as -EncodedCommand.
    # Outer -Command embeds LE_JOB_ID in the visible command line so abort can taskkill orphans.
    local enc
    _LE_WIN_JOB_ID="lejob_${$}_$(date +%s)_${RANDOM}"
    enc="$(python3 - "$rpath" "$@" <<'PY'
import base64, sys

def ps_quote(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"

rpath = sys.argv[1].replace("/", chr(92))
args = sys.argv[2:]
if not args:
    raise SystemExit("run_in_project: empty argv")
parts = [
    "$ProgressPreference='SilentlyContinue'",
    f"Set-Location -LiteralPath {ps_quote(rpath)}",
    f"& {ps_quote(args[0])} @({', '.join(ps_quote(a) for a in args[1:])})",
    "if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE } else { exit 0 }",
]
ps = "; ".join(parts)
sys.stdout.write(base64.b64encode(ps.encode("utf-16-le")).decode("ascii"))
PY
)"
    # \$env so bash does not expand; LE_JOB_ID stays visible on Windows command line for abort kill.
    _laptop_ssh "powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command \"\$env:LE_JOB_ID='${_LE_WIN_JOB_ID}'; powershell -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand ${enc}\""
    _LE_WIN_JOB_ID=""
}


_git_invoke() {
    local rpath="$1"; shift
    local git_dir
    if [ "$GIT_MODE" = "server" ]; then _run_in_project "$rpath" git "$@"; return; fi
    git_dir="$(_detect_git_dir_cached "$rpath")" || _die "no git repository on laptop for $rpath"
    _run_in_project "$rpath" git --git-dir="$git_dir" --work-tree=. "$@"
}

_parse_project_flag() {
    PROJECT_ID=""
    WORKSPACE_PATH=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -p|--project)
                [ $# -ge 2 ] || _die "missing value for $1"
                PROJECT_ID="$2"; shift 2 ;;
            -w|--workspace)
                [ $# -ge 2 ] || _die "missing value for $1"
                WORKSPACE_PATH="$2"; shift 2 ;;
            --) break ;;  # leave -- for subcommands (rg dash-leading patterns)
            *) break ;;
        esac
    done
    REMAINING=("$@")
}

# Agents write: laptop-exec git -p ID -- status  → leave -- for parse, strip before invoke.
_strip_leading_dd() {
    if [ "${#REMAINING[@]}" -gt 0 ] && [ "${REMAINING[0]}" = "--" ]; then
        REMAINING=("${REMAINING[@]:1}")
    fi
}

_require_session() {
    _load_global
    [ -n "$LAPTOP_USER" ] || _die "no connect session - run connect.bat/sh first"
}

_tunnel_up() {
    if [ "$LAPTOP_OS" = "mac" ]; then _laptop_ssh true >/dev/null 2>&1; else _laptop_ssh "powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command exit" >/dev/null 2>&1; fi
}

_resolve_project() {
    local pid="${PROJECT_ID:-}" ws=""
    if [ -z "$pid" ]; then
        ws="$(_guess_workspace_path 2>/dev/null || true)"
        [ -n "$ws" ] && pid="$(_project_id_from_path "$ws" 2>/dev/null || true)"
    fi
    pid="${pid:-$ACTIVE_MOUNT}"
    [ -n "$pid" ] || _die "no project (-p ID, -w ~/mounts/ID/..., cd ~/mounts/ID, or connect session)"
    PROJECT_ID="$pid"
    _load_project "$pid"
}

_cmd_status() {
    _load_global
    echo "tunnel_port:  ${TUNNEL_PORT}"
    echo "laptop_user:  ${LAPTOP_USER:-<unset>}"
    echo "laptop_os:    ${LAPTOP_OS}"
    echo "active_mount: ${ACTIVE_MOUNT:-<none>}"
    echo "git_mode:     ${GIT_MODE}"
    if [ -z "$LAPTOP_USER" ]; then
        echo "tunnel:       DOWN (no connect session)"
        echo "sshfs:        n/a"
        echo "prefer:       run connect.bat/sh"
        exit 1
    fi
    if _tunnel_up; then echo "tunnel:       UP"; else
        _le_audit_log ERROR TUNNEL_DOWN "project=${ACTIVE_MOUNT:-?}" "$(_le_audit_session_fields)"             "hint=User must run connect.bat/sh; agents must stop issuing laptop-exec until UP."
        echo "tunnel:       DOWN"; echo "prefer:       run connect.bat/sh"; exit 1
    fi
    if [ -n "$ACTIVE_MOUNT" ] && [ -f "$CONF_DIR/${ACTIVE_MOUNT}.conf" ]; then
        local mp="$(_mount_path_for_project "$ACTIVE_MOUNT")"
        echo "sshfs:        $(_sshfs_state "$mp") ($mp)"
    else
        echo "sshfs:        n/a (no active_mount)"
    fi
    echo "prefer:       READ/GREP=mount|MCP|LE; WRITE=MCP|mount|LE; Glob=MCP|mount; git=LE"
}

_cmd_health() {
    _parse_project_flag "$@"
    _cmd_status || true
    echo ""
    echo "projects:"
    LIST_FAST=1 _cmd_list
}

_cmd_list() {
    _load_global
    local conf pid mp state mark fast="${LIST_FAST:-0}" k v
    shopt -s nullglob
    for conf in "$CONF_DIR"/*.conf; do
        pid="$(basename "$conf" .conf)"
        REMOTE_PATH=""
        while IFS='=' read -r k v; do
            v="${v#\"}"; v="${v%\"}"
            case "$k" in rpath|REMOTE_PATH) REMOTE_PATH="${v//\\//}" ;; esac
        done < "$conf"
        if [ "$fast" = "1" ]; then
            state="(list --full)"
        else
            mp="$(_mount_path_for_project "$pid")"
            state="$(_sshfs_state "$mp")"
        fi
        mark=""; [ "$pid" = "$ACTIVE_MOUNT" ] && mark=" *"
        printf "  %-20s sshfs=%-22s laptop=%s%s\n" "$pid" "$state" "${REMOTE_PATH:-?}" "$mark"
    done
    shopt -u nullglob
}

_cmd_resolve() {
    local path="${1:-}" pid=""
    if [ -z "$path" ]; then
        path="$(_guess_workspace_path 2>/dev/null || true)"
        [ -n "$path" ] || _die "usage: laptop-exec resolve [PATH] (or -w / cd ~/mounts/ID)"
    fi
    path="${path//\\//}"
    if pid="$(_project_id_from_path "$path" 2>/dev/null)"; then
        echo "$pid"
        return 0
    fi
    _die "cannot resolve project from: $path"
}

_cmd_mount_status() {
    _parse_project_flag "$@"
    _require_session
    _resolve_project
    local pid="${PROJECT_ID:-$ACTIVE_MOUNT}" mp="" state=""
    mp="$(_mount_path_for_project "$pid")"
    state="$(_sshfs_state "$mp")"
    echo "project:      $pid"
    echo "local_path:   $mp"
    echo "laptop_path:  $REMOTE_PATH"
    echo "sshfs:        $state"
    if _tunnel_up; then echo "tunnel:       UP"; else echo "tunnel:       DOWN"; fi
    case "$state" in
        MOUNTED) echo "recommend:    mount Read/Grep; MCP Write/Glob when listed; LE for git + fallback" ;;
        *) echo "recommend:    MCP when listed else laptop-exec (git always LE)" ;;
    esac
}

_cmd_path() { _parse_project_flag "$@"; _require_session; _resolve_project; echo "$REMOTE_PATH"; }

_cmd_count() {
    _parse_project_flag "$@"; _strip_leading_dd
    _require_session; _resolve_project
    local _t="${LAPTOP_EXEC_CMD_TIMEOUT:-120}"
    if [ "$LAPTOP_OS" = "mac" ]; then
        LAPTOP_EXEC_CMD_TIMEOUT="$_t" _run_in_project "$REMOTE_PATH"             find . -type f \( -path './node_modules/*' -o -path './.git/*' -o -path './dist/*' \) -prune -o -type f -print | wc -l
    else
        LAPTOP_EXEC_CMD_TIMEOUT="$_t" _run_in_project "$REMOTE_PATH" powershell -NoProfile -Command             "$skip=@('node_modules','.git','dist','build'); (Get-ChildItem -Recurse -File -EA SilentlyContinue | Where-Object { $p=$_.FullName; -not ($skip | Where-Object { $p -like ('*\'+$_+'\*') }) }).Count"
    fi
}


# Reject Cursor-mount / abs paths that agents paste into LE by mistake.
_reject_abs_or_mount_path() {
    local op="$1" p="$2"
    case "$p" in
        /home/*/mounts/*|~/mounts/*|/mnt/*)
            _die "$op: Linux mount path not valid on laptop ($p). NEXT: use repo-relative with -p PROJECT (e.g. laptop-exec read -p PROJECT README.md). For /mounts/ use Cursor Read/Grep, not LE."
            ;;
    esac
    if [[ "$p" == /* || "$p" == [A-Za-z]:* || "$p" == \\\\* ]]; then
        _die "$op: absolute path not supported ($p). NEXT: repo-relative only — laptop-exec <verb> -p PROJECT REL (never absolute/Windows paths)."
    fi
}

_cmd_read() {
    _parse_project_flag "$@"; _strip_leading_dd
    local tok cursorish=0 nfiles=0
    if [ "${#REMAINING[@]}" -eq 0 ]; then
        _die "read: missing <file>. $(_read_next)"
    fi
    for tok in "${REMAINING[@]}"; do
        case "$tok" in
            --offset|--limit|--offset=*|--limit=*|--)
                cursorish=1 ;;
            -*)
                cursorish=1 ;;
            *)
                if [[ "$tok" =~ ^[0-9]+$ ]]; then
                    cursorish=1
                else
                    nfiles=$((nfiles + 1))
                fi
                ;;
        esac
    done
    if [ "$cursorish" -eq 1 ]; then
        _die "read: Cursor-Read-style args not supported (${REMAINING[*]}). $(_read_next)"
    fi
    if [ "${#REMAINING[@]}" -ne 1 ] || [ "$nfiles" -ne 1 ]; then
        _die "read: got ${#REMAINING[@]} args (need exactly 1 file). $(_read_next)"
    fi
    local file="${REMAINING[0]}"; file="${file//\\//}"
    _reject_abs_or_mount_path read "$file"
    _require_session; _resolve_project
    if [ "$LAPTOP_OS" = "mac" ]; then _run_in_project "$REMOTE_PATH" cat "$file"
    else _run_in_project "$REMOTE_PATH" powershell -NoProfile -Command "[Console]::OutputEncoding=[Text.UTF8Encoding]::new(\$false); \$t=[IO.File]::ReadAllText((Resolve-Path -LiteralPath '${file//\'/''}').Path,[Text.UTF8Encoding]::new(\$false)); [Console]::Out.Write(\$t)"; fi
}

_cmd_write() {
    _parse_project_flag "$@"; _strip_leading_dd
    [ "${#REMAINING[@]}" -eq 1 ] || _die "usage: laptop-exec write [-p PROJECT] <file>  (stdin)"
    local file="${REMAINING[0]}" tmp; file="${file//\\//}"
    _reject_abs_or_mount_path write "$file"
    _require_session; _resolve_project
    tmp=$(mktemp); cat >"$tmp" || _die "write: no stdin"
    # MCP / Windows editors often inject CR; strip for shell/python so bash -n works.
    case "$file" in
        *.sh|*.bash|*.py|*.zsh)
            if grep -q $'\r' "$tmp" 2>/dev/null; then
                tr -d '\r' < "$tmp" > "${tmp}.nocr" && mv -f "${tmp}.nocr" "$tmp"
                echo "warn: write stripped CRLF from $file (prefer LF for .sh/.py)" >&2
            fi
            ;;
    esac
    _ensure_remote_parent_dir "$REMOTE_PATH" "$file"
    _laptop_scp_to "$tmp" "$REMOTE_PATH" "$file"
    rm -f "$tmp"
}

_cmd_run() {
    _parse_project_flag "$@"; _strip_leading_dd
    [ "${#REMAINING[@]}" -gt 0 ] || _die "usage: laptop-exec run [-p PROJECT] -- <cmd...>"
    _require_session; _resolve_project
    local _t="${LAPTOP_EXEC_RUN_TIMEOUT:-120}"
    if [ "$_t" = "0" ]; then _run_in_project "$REMOTE_PATH" "${REMAINING[@]}"
    else LAPTOP_EXEC_CMD_TIMEOUT="$_t" _run_in_project "$REMOTE_PATH" "${REMAINING[@]}"; fi
}

_cmd_git() {
    _parse_project_flag "$@"; _strip_leading_dd
    [ "${#REMAINING[@]}" -gt 0 ] || _die "usage: laptop-exec git [-p PROJECT] -- <args...>  ( -p BEFORE subcommand )"
    # Agents often put -p AFTER git args: `git status -p ID` → git unknown switch p.
    # Allow -p/--patch after log|show|diff (git patch); still DIE for misplaced LE -p/--project.
    local _i _tok _patch_ctx=0
    for ((_i = 0; _i < ${#REMAINING[@]}; _i++)); do
        _tok="${REMAINING[_i]}"
        case "$_tok" in
            log|show|diff) _patch_ctx=1 ;;
            --project)
                _die "git: -p/--project must come BEFORE the git subcommand (got: laptop-exec git ${REMAINING[*]}). NEXT: laptop-exec git -p PROJECT -- <subcommand> (LE -p before subcommand; git log|show|diff -p OK)"
                ;;
            -p)
                if [ "$_patch_ctx" -ne 1 ]; then
                    _die "git: -p/--project must come BEFORE the git subcommand (got: laptop-exec git ${REMAINING[*]}). NEXT: laptop-exec git -p PROJECT -- <subcommand> (LE -p before subcommand; git log|show|diff -p OK)"
                fi
                ;;
            --patch)
                if [ "$_patch_ctx" -ne 1 ]; then
                    _die "git: -p/--project must come BEFORE the git subcommand (got: laptop-exec git ${REMAINING[*]}). NEXT: laptop-exec git -p PROJECT -- <subcommand> (LE -p before subcommand; git log|show|diff -p OK)"
                fi
                ;;
        esac
    done
    _require_session; _resolve_project
    local _t="${LAPTOP_EXEC_GIT_TIMEOUT:-300}"
    if [ "$_t" = "0" ]; then _git_invoke "$REMOTE_PATH" "${REMAINING[@]}"
    else LAPTOP_EXEC_CMD_TIMEOUT="$_t" _git_invoke "$REMOTE_PATH" "${REMAINING[@]}"; fi
}

_rg_is_regex() {
    # Prefer glob checks: bash [[ =~ ]] character classes are easy to get wrong for | + ?
    local p="$1"
    [[ "$p" == *"["* || "$p" == *"]"* || "$p" == *"("* || "$p" == *")"*         || "$p" == *"|"* || "$p" == *"+"* || "$p" == *"?"* ]]
}

_ps_search_encoded() {
    local pattern="$1" regex="$2"
    python3 - "$pattern" "$regex" <<'PY'
import base64, sys
pat = sys.argv[1]
regex = sys.argv[2] == "1"
pat_esc = pat.replace("'", "''")
# Prune heavy dirs DURING walk (Get-ChildItem -Recurse descends into node_modules).
ps = r"""
$ErrorActionPreference='SilentlyContinue'
$skip = [System.Collections.Generic.HashSet[string]]::new(
  [string[]]@('node_modules','.git','dist','build','coverage','.next','vendor','.venv','__pycache__','bin','obj')
)
$files = [System.Collections.Generic.List[string]]::new()
function Walk([string]$dir) {
  try {
    foreach ($f in [System.IO.Directory]::EnumerateFiles($dir)) { [void]$files.Add($f) }
    foreach ($d in [System.IO.Directory]::EnumerateDirectories($dir)) {
      $name = [System.IO.Path]::GetFileName($d)
      if ($skip.Contains($name)) { continue }
      Walk $d
    }
  } catch {}
}
Walk (Get-Location).Path
"""
if regex:
    ps += (
        f"$files | Select-String -Pattern '{pat_esc}' | "
        "ForEach-Object { $_.Path + ':' + $_.LineNumber + ':' + $_.Line.Trim() }"
    )
else:
    ps += (
        f"$files | Select-String -SimpleMatch -Pattern '{pat_esc}' | "
        "ForEach-Object { $_.Path + ':' + $_.LineNumber + ':' + $_.Line.Trim() }"
    )
print(base64.b64encode(ps.encode("utf-16-le")).decode())
PY
}

_cmd_rg() {
    _parse_project_flag "$@"
    [ "${#REMAINING[@]}" -gt 0 ] || _die "usage: laptop-exec rg [-p PROJECT] <pattern> [pathspec...]"
    _require_session; _resolve_project

    # Agents often pass real-ripgrep flags (-i/-l/--glob). Those used to become the
    # "pattern" and fall through to a full-tree Select-String that held mux slots for hours.
    local pattern="" pathspecs=() a
    set -- "${REMAINING[@]}"
    while [ $# -gt 0 ]; do
        a="$1"
        case "$a" in
            --)
                # After -- : pattern (if unset) then pathspecs — allows patterns starting with -
                shift
                if [ -z "$pattern" ]; then
                    [ $# -gt 0 ] || _die "usage: laptop-exec rg [-p PROJECT] -- <pattern> [pathspec...]"
                    pattern="$1"; shift
                fi
                pathspecs+=("$@")
                break
                ;;
            -l|--files-with-matches|-i|--ignore-case|-n|--line-number|-v|--invert-match|\
            -w|--word-regexp|-H|--with-filename|-c|--count|-U|--multiline|--hidden|\
            --no-ignore|--json|-S|--smart-case|--heading|--no-heading|-o|--only-matching|\
            --files|-e|--regexp)
                _le_audit_log ERROR RG_FLAG_REJECTED "flag=$a" "project=${PROJECT_ID:-?}" \
                    "hint=No ${_RG_FORBIDDEN}; prefer Cursor Grep on /mounts/."
                _die "rg: flag '$a' not supported. $(_rg_next)"
                ;;
            -A|-B|-C|-g|--glob|--type|--type-add|--type-not|--type-not-add|-m|--max-count|\
            --after-context|--before-context|--context|--iglob|--pathspec|--path-filter)
                _le_audit_log ERROR RG_FLAG_REJECTED "flag=$a" "project=${PROJECT_ID:-?}" \
                    "hint=No ${_RG_FORBIDDEN}; use pathspecs or Cursor Grep."
                _die "rg: flag '$a' not supported. $(_rg_next)"
                ;;
            -*)
                _le_audit_log ERROR RG_FLAG_REJECTED "flag=$a" "project=${PROJECT_ID:-?}" "hint=Unknown rg flag."
                _die "rg: unknown flag '$a'. $(_rg_next)"
                ;;
            *)
                if [ -z "$pattern" ]; then
                    pattern="$a"
                else
                    pathspecs+=("$a")
                fi
                ;;
        esac
        shift
    done
    [ -n "$pattern" ] || _die "usage: laptop-exec rg [-p PROJECT] <pattern> [pathspec...]"

    local git_dir="" rc=0
    local _rg_timeout="${LAPTOP_EXEC_RG_TIMEOUT:-90}"
    _rg_exec() {
        LAPTOP_EXEC_CMD_TIMEOUT="$_rg_timeout" _run_in_project "$@"
    }

    if git_dir="$(_detect_git_dir_cached "$REMOTE_PATH" 2>/dev/null || true)" && [ -n "$git_dir" ]; then
        if _rg_is_regex "$pattern"; then
            if [ "${#pathspecs[@]}" -gt 0 ]; then
                _rg_exec "$REMOTE_PATH" git --git-dir="$git_dir" --work-tree=. grep -n -E -e "$pattern" -- "${pathspecs[@]}" && return 0
            else
                _rg_exec "$REMOTE_PATH" git --git-dir="$git_dir" --work-tree=. grep -n -E -e "$pattern" && return 0
            fi
        else
            if [ "${#pathspecs[@]}" -gt 0 ]; then
                _rg_exec "$REMOTE_PATH" git --git-dir="$git_dir" --work-tree=. grep -n -F -e "$pattern" -- "${pathspecs[@]}" && return 0
            else
                _rg_exec "$REMOTE_PATH" git --git-dir="$git_dir" --work-tree=. grep -n -F -e "$pattern" && return 0
            fi
        fi
        rc=$?
        [ "$rc" -eq 1 ] && return 1
        [ "$rc" -eq 124 ] && return 124
        [ "$rc" -eq 255 ] && _die "rg: SSH/mux failed (exit 255) — session slots full or tunnel issue; wait and retry"
        # Git work tree exists: do NOT fall through to full-tree Select-String.
        _die "rg: git grep failed (exit $rc). Fix pattern/pathspec; do not retry with ${_RG_FORBIDDEN}. $(_rg_next)"
    fi
    if [ "$LAPTOP_OS" = "mac" ]; then
        if command -v rg >/dev/null 2>&1; then
            if [ "${#pathspecs[@]}" -gt 0 ]; then
                _rg_exec "$REMOTE_PATH" rg "$pattern" "${pathspecs[@]}"; return
            fi
            _rg_exec "$REMOTE_PATH" rg "$pattern"; return
        fi
        if [ "${#pathspecs[@]}" -gt 0 ]; then
            _rg_exec "$REMOTE_PATH" grep -R -n -E "$pattern" "${pathspecs[@]}"; return
        fi
        _rg_exec "$REMOTE_PATH" grep -R -n -E "$pattern" .; return
    fi
    local enc=""
    if _rg_is_regex "$pattern"; then enc="$(_ps_search_encoded "$pattern" 1)"
    else enc="$(_ps_search_encoded "$pattern" 0)"; fi
    if [ "${#pathspecs[@]}" -gt 0 ]; then
        echo "laptop-exec: warning: pathspecs ignored on Windows no-git Select-String fallback." >&2
    fi
    _rg_exec "$REMOTE_PATH" powershell -NoProfile -EncodedCommand "$enc"
}

_cmd_test() {
    local pass=0 fail=0
    _check() {
        local name="$1"; shift; local out rc
        out=$("$@" 2>&1) || true; rc=$?
        if [ "$rc" -ne 0 ]; then echo "FAIL  $name (exit $rc)"; fail=$((fail+1)); return; fi
        if grep -qiE '^(fatal:|FAIL |cannot find the path|not recognized|syntax of the command)' <<<"$out"; then
            echo "FAIL  $name"; fail=$((fail+1)); return
        fi
        if [ -z "$out" ] && [ "$name" = "rg" ]; then echo "FAIL  $name (empty)"; fail=$((fail+1)); return; fi
        echo "PASS  $name"; pass=$((pass+1))
    }
    echo "laptop-exec self-test"
    _check status laptop-exec status
    _check health laptop-exec health
    _check list laptop-exec list
    _check resolve laptop-exec resolve "$HOME/mounts/${ACTIVE_MOUNT:-ai-gap-summay}"
    _check resolve-w laptop-exec resolve -w "$HOME/mounts/claude-code-server"
    _check mount-status laptop-exec mount-status
    _check "git status" laptop-exec git -- status
    _check "read CLAUDE.md" laptop-exec read CLAUDE.md
    _check "read nested" laptop-exec read scripts/server/laptop-exec.sh
    _check "write roundtrip" bash -c 'printf test-%s .$$ | laptop-exec write .laptop-exec-write-test.tmp && laptop-exec read .laptop-exec-write-test.tmp | grep -q test-'
    laptop-exec run -- powershell -NoProfile -Command "Remove-Item -Force -EA SilentlyContinue .laptop-exec-write-test.tmp" >/dev/null 2>&1 || true
    _check rg laptop-exec rg -p claude-code-server laptop-exec
    _check "rg git-accuracy" bash -c 'laptop-exec rg -p claude-code-server "ControlPersist" scripts/server/laptop-exec.sh | grep -q ControlPersist'
    _check "rg reject -i" bash -c 'out=$(laptop-exec rg -p claude-code-server -i foo 2>&1); rc=$?; [ "$rc" -ne 0 ] && echo "$out" | grep -qi "not supported"'
    _check "rg reject --glob" bash -c 'out=$(laptop-exec rg -p claude-code-server --glob "*.ts" foo 2>&1); rc=$?; [ "$rc" -ne 0 ] && echo "$out" | grep -qi "not supported"'
    _check "rg reject --type" bash -c 'out=$(laptop-exec rg -p claude-code-server --type cs foo 2>&1); rc=$?; [ "$rc" -ne 0 ] && echo "$out" | grep -qi "not supported\|Cursor Grep"'
    _check "read reject --offset" bash -c 'out=$(laptop-exec read -p claude-code-server CLAUDE.md --offset 1 --limit 5 2>&1); rc=$?; [ "$rc" -ne 0 ] && echo "$out" | grep -qi "Cursor Read\|Cursor-Read"'
    _check "read reject multi-file" bash -c 'out=$(laptop-exec read -p claude-code-server CLAUDE.md README.md 2>&1); rc=$?; [ "$rc" -ne 0 ] && echo "$out" | grep -qi "exactly 1 file\|Cursor Read"'
    _check "rg dash pattern" bash -c 'laptop-exec rg -p claude-code-server -- "-o ControlMaster" scripts/server/laptop-exec.sh | grep -q ControlMaster'
    _check "rg no-fallthrough" bash -c 'out=$(laptop-exec rg -p claude-code-server "[unterminated" scripts/server/ 2>&1); echo "$out" | grep -qi "git grep failed"'
    _check dotnet laptop-exec run -- dotnet --version
    _check "multiplex warm read" bash -c 'laptop-exec read CLAUDE.md >/dev/null && laptop-exec read CLAUDE.md >/dev/null'
    _check "read reject abs mounts" bash -c 'out=$(laptop-exec read /home/smart/mounts/claude-code-server/CLAUDE.md 2>&1); rc=$?; [ "$rc" -ne 0 ] && echo "$out" | grep -qi "mount path\|relative\|NEXT"'
    _check "git -p after args DIE" bash -c 'out=$(laptop-exec git status -p claude-code-server 2>&1); rc=$?; [ "$rc" -ne 0 ] && echo "$out" | grep -qi "BEFORE\|NEXT"'
    _check "unknown verb NEXT" bash -c 'out=$(laptop-exec rpath 2>&1); rc=$?; [ "$rc" -ne 0 ] && echo "$out" | grep -qi "invent\|unknown command"'
    echo "----"; echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
}

_usage() {
    cat <<'EOF'
laptop-exec - SSH-first (fast multiplex SSH + accurate git-grep search)

Commands:
  status / health / list [--full]
  resolve [PATH]              use -w PATH when cwd is not under ~/mounts/
  mount-status / path / count / read / write / run / git / rg / test

Project selection (first match):
  1. -p PROJECT   (before OR after subcommand: laptop-exec -p ID read REL  OR  laptop-exec read -p ID REL)
  2. -w PATH  (workspace under ~/mounts/ID/...)
  3. LAPTOP_EXEC_WORKSPACE / CURSOR workspace env / cwd

Speed: shared ControlMaster + 8 session slots (capped for OpenSSH MaxSessions) + flock bring-up
Search: git grep (tracked) -> PowerShell Select-String (excl. node_modules/.git/...)
  Healthy mount: prefer Cursor Read/Grep on /mounts — LE read/rg is failover only.
  rg flags -i/-l/-n/-A/-B/-C/-m/-g/--glob/--type/--max-count REJECTED. Prefer Cursor Grep.
  read: ONE file only (no --offset/--limit / multi-file / line nums — use Cursor Read).
  Dash patterns: rg -- -foo path
  Timeouts: rg 90s, run 120s, git 300s, scp 120s (set LAPTOP_EXEC_*_TIMEOUT=0 to disable)
EOF
}

main() {
    # Capture raw argv BEFORE any _die (early flag parse used to leave argv=error msg).
    _LE_LAST_ARGV=$(_le_audit_trunc "$*" 350)
    # Accept global -p/-w BEFORE subcommand (agents often write: laptop-exec -p ID read REL)
    local global_args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            -p|--project|-w|--workspace)
                [ $# -ge 2 ] || _die "missing value for $1"
                global_args+=("$1" "$2"); shift 2 ;;
            -h|--help|help)
                _usage; return 0 ;;
            *) break ;;
        esac
    done
    local cmd="${1:-}"; [ -n "$cmd" ] || { _usage; exit 1; }; shift
    # Prepend global flags so existing per-command parsers still work
    if [ "${#global_args[@]}" -gt 0 ]; then
        set -- "${global_args[@]}" "$@"
    fi
    local _t0 _ms _rc=0 _argv
    _t0=$(date +%s%3N 2>/dev/null || date +%s)
    _argv=$(_le_audit_trunc "$cmd $*" 350)
    _LE_LAST_ARGV="$_argv"
    # Resolve project early for log context when -p present in args
    case " $* " in
        *" -p "*|*" --project "*) ;;
    esac
    _LE_ACTIVE_CMD="$cmd"
    _LE_CMD_ENDED=0
    trap '_le_on_signal' TERM INT HUP
    _le_audit_log INFO CMD_BEGIN "cmd=${cmd}" "argv=${_argv}"         "project=${PROJECT_ID:-${ACTIVE_MOUNT:-?}}" "$(_le_audit_session_fields)"         "slots_busy=$(_le_audit_slots_busy)/8" "parent_cmd=$(_le_audit_trunc "${SSH_ORIGINAL_COMMAND:-${CURSOR_TRACE_ID:-n/a}}" 80)"
    set +e
    case "$cmd" in
        status) _cmd_status "$@" ;;
        health) _cmd_health "$@" ;;
        list)
            if [ "${1:-}" = "--full" ]; then shift; LIST_FAST=0 _cmd_list "$@"; else LIST_FAST=1 _cmd_list "$@"; fi ;;
        resolve) _parse_project_flag "$@"; _cmd_resolve "${REMAINING[@]}" ;;
        mount-status) _cmd_mount_status "$@" ;;
        path) _cmd_path "$@" ;;
        count) _cmd_count "$@" ;;
        read) _cmd_read "$@" ;;
        write) _cmd_write "$@" ;;
        run) _cmd_run "$@" ;;
        git) _cmd_git "$@" ;;
        rg) _cmd_rg "$@" ;;
        test) _cmd_test "$@" ;;
        -h|--help|help) _usage ;;
        *)
            # Soft-trim trailing whitespace (HARD footgun: unknown command 'status ')
            cmd_trim=$(printf '%s' "$cmd" | sed 's/[[:space:]]*$//')
            if [ "$cmd_trim" != "$cmd" ] && [ -n "$cmd_trim" ]; then
                cmd="$cmd_trim"
                case "$cmd" in
                    status) _cmd_status "$@" ;;
                    health) _cmd_health "$@" ;;
                    list)
                        if [ "${1:-}" = "--full" ]; then shift; LIST_FAST=0 _cmd_list "$@"; else LIST_FAST=1 _cmd_list "$@"; fi ;;
                    resolve) _parse_project_flag "$@"; _cmd_resolve "${REMAINING[@]}" ;;
                    mount-status) _cmd_mount_status "$@" ;;
                    path) _cmd_path "$@" ;;
                    count) _cmd_count "$@" ;;
                    read) _cmd_read "$@" ;;
                    write) _cmd_write "$@" ;;
                    run) _cmd_run "$@" ;;
                    git) _cmd_git "$@" ;;
                    rg) _cmd_rg "$@" ;;
                    test) _cmd_test "$@" ;;
                    -h|--help|help) _usage ;;
                    *) _die "unknown command '$cmd' (not a laptop-exec verb). NEXT: real verbs: status|health|list|read|write|rg|git|run|test|path|count|help — see --help. Do not invent rpath/pathspec/ls." ;;
                esac
            else
                _die "unknown command '$cmd' (not a laptop-exec verb). NEXT: real verbs: status|health|list|read|write|rg|git|run|test|path|count|help — see --help. Do not invent rpath/pathspec/ls."
            fi
            ;;
    esac
    _rc=$?
    set -e
    _ms=$(( $(date +%s%3N 2>/dev/null || date +%s) - _t0 ))
    if [ "${_LE_CMD_ENDED:-0}" -eq 0 ]; then
        _LE_CMD_ENDED=1
        if [ "$_rc" -eq 0 ]; then
            _le_audit_log INFO CMD_END "cmd=${cmd}" "exit=0" "ms=${_ms}"             "project=${PROJECT_ID:-${ACTIVE_MOUNT:-?}}" "$(_le_audit_session_fields)"             "slots_busy=$(_le_audit_slots_busy)/8"
        elif [ "$_rc" -eq 1 ] && [ "$cmd" = "rg" ]; then
            _le_audit_log INFO CMD_END "cmd=rg" "exit=1" "ms=${_ms}"             "project=${PROJECT_ID:-?}" "meaning=no_matches" "$(_le_audit_session_fields)"
        elif [ "$_rc" -eq 124 ]; then
            # Guarantee CMD_END on timeout (124) even when CMD_TIMEOUT already logged in _laptop_ssh.
            _le_audit_log WARN CMD_END "cmd=${cmd}" "exit=124" "ms=${_ms}"             "project=${PROJECT_ID:-?}" "meaning=timeout" "$(_le_audit_session_fields)"             "slots_busy=$(_le_audit_slots_busy)/8"
        elif [ "$_rc" -eq 255 ]; then
            _le_audit_log ERROR CMD_END "cmd=${cmd}" "exit=255" "ms=${_ms}"             "project=${PROJECT_ID:-?}" "$(_le_audit_session_fields)"             "slots_busy=$(_le_audit_slots_busy)/8" "hint=SSH/mux failure or SLOT_FULL — check prior SLOT_*/MUX_* lines."
        else
            _le_audit_log WARN CMD_END "cmd=${cmd}" "exit=${_rc}" "ms=${_ms}"             "project=${PROJECT_ID:-?}" "$(_le_audit_session_fields)"             "slots_busy=$(_le_audit_slots_busy)/8"
        fi
    fi
    trap - TERM INT HUP
    return "$_rc"
}
main "$@"




