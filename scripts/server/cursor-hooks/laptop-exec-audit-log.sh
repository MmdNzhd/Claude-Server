#!/usr/bin/env bash
# laptop-exec-audit-log.sh - durable multi-agent diagnostics (shared by laptop-exec + hooks)
#
# POLICY (2026-07): LOG HEAVILY while the product is unstable - volume is fine if
# lines help diagnose user/agent failures. After things stabilize, dial down by:
#   export LAPTOP_EXEC_AUDIT_VERBOSE=0
# (keeps ERROR/WARN + important events; drops noisy INFO like CMD_BEGIN/shell allow).
# Later we can delete debug call sites; for now prefer too much over blindness.
#
# ALWAYS on the Linux SERVER (Cursor Remote SSH / agent host) - dual write:
#   1) ~/.claude/logs/laptop-exec-YYYYMMDD.log   (dedicated, dense)
#   2) ~/.claude/logs/connect-YYYYMMDD.log       (admin day-log; [multiagent] LAPTOP_EXEC)
# Purged with connect logs (mtime +1). Safe to source many times. No secrets.

# Default ON (verbose). Set to 0 only after multi-agent/connect is stable.
: "${LAPTOP_EXEC_AUDIT_VERBOSE:=1}"

_le_audit_log_dir() { printf '%s' "${HOME:-/tmp}/.claude/logs"; }

_le_audit_trunc() {
    local s="$1" max="${2:-400}"
    s=$(printf '%s' "$s" | tr '\n\r\t' '   ')
    if [ "${#s}" -gt "$max" ]; then
        printf '%s...(len=%s)' "${s:0:$max}" "${#s}"
    else
        printf '%s' "$s"
    fi
}

_le_audit_slots_busy() {
    local i n=0 fd cache="${HOME:-/tmp}/.cache/laptop-exec"
    for i in 0 1 2 3 4 5 6 7; do
        [ -e "$cache/slot-${i}.lock" ] || continue
        exec {fd}<>"$cache/slot-${i}.lock" 2>/dev/null || continue
        if ! flock -n "$fd" 2>/dev/null; then
            n=$((n + 1))
        else
            flock -u "$fd" 2>/dev/null || true
        fi
        eval "exec ${fd}>&-" 2>/dev/null || true
    done
    printf '%s' "$n"
}

_le_audit_session_fields() {
    local conf="${HOME:-}/.claude-connect.conf" k v port="" lu="" am="" gm=""
    [ -f "$conf" ] || { printf 'tunnel_port=? laptop_user=? active_mount=? git_mode=?'; return 0; }
    while IFS='=' read -r k v; do
        v="${v#\"}"; v="${v%\"}"
        case "$k" in
            TUNNEL_PORT) port="$v" ;;
            LAPTOP_USER) lu="$v" ;;
            ACTIVE_MOUNT|active_mount) am="$v" ;;
            GIT_MODE|git_mode) gm="$v" ;;
        esac
    done < "$conf" 2>/dev/null || true
    printf 'tunnel_port=%s laptop_user=%s active_mount=%s git_mode=%s' \
        "${port:-?}" "${lu:-?}" "${am:-?}" "${gm:-?}"
}

_le_audit_append_file() {
    local file="$1" line="$2"
    (
        flock 9 || true
        printf '%s\n' "$line" >> "$file" 2>/dev/null || true
    ) 9>"${file}.lock" 2>/dev/null || {
        printf '%s\n' "$line" >> "$file" 2>/dev/null || true
    }
}

# True if this level/event should be written when VERBOSE=0 (keep problem signal).
_le_audit_always_keep() {
    local level="$1" event="$2"
    case "$level" in
        ERROR|WARN) return 0 ;;
    esac
    case "$event" in
        HOOK_DENY|HOOK_TASK_SPAWN|WRAP_FAIL_OPEN|SLOT_FULL|SLOT_WAIT|MUX_RECREATE|SSH_RETRY|CMD_TIMEOUT|TUNNEL_DOWN|RG_FLAG_REJECTED|DIE|SESSION_START|CMD_END)
            return 0 ;;
    esac
    return 1
}

# usage: _le_audit_log LEVEL EVENT [key=val ...]
# Dual-writes on SERVER to laptop-exec-*.log AND connect-*.log.
_le_audit_log() {
    local level="${1:-INFO}" event="${2:-EVENT}"
    shift 2 || true
    local dir ts day line msg a connect_line host

    # When VERBOSE=0: drop noisy INFO (CMD_BEGIN, shell allow breadcrumbs, etc.).
    if [ "${LAPTOP_EXEC_AUDIT_VERBOSE:-1}" != "1" ] && ! _le_audit_always_keep "$level" "$event"; then
        return 0
    fi

    dir="$(_le_audit_log_dir)"
    mkdir -p "$dir" 2>/dev/null || return 0
    chmod 700 "$dir" 2>/dev/null || true
    ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '?')
    day=$(date '+%Y%m%d' 2>/dev/null || echo 'unknown')
    host=$(hostname -s 2>/dev/null || echo server)
    msg="event=${event}"
    for a in "$@"; do
        [ -n "$a" ] || continue
        a=$(_le_audit_trunc "$a" 500)
        msg="${msg} ${a}"
    done

    line=$(printf '[%s] [%s] [user=%s uid=%s pid=%s ppid=%s host=%s] %s' \
        "$ts" "$level" "${USER:-?}" "$(id -u 2>/dev/null || echo '?')" "$$" "${PPID:-?}" "$host" "$msg")
    _le_audit_append_file "${dir}/laptop-exec-${day}.log" "$line"

    connect_line=$(printf '[%s] [%s] [multiagent] LAPTOP_EXEC %s user=%s pid=%s host=%s' \
        "$ts" "$level" "$msg" "${USER:-?}" "$$" "$host")
    _le_audit_append_file "${dir}/connect-${day}.log" "$connect_line"
    return 0
}
