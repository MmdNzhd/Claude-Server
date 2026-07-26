#!/usr/bin/env bash
# cursor-server-reaper.sh - kill idle old Cursor Remote server-main trees (per user)
#
# Evidence (2026-07-26): multiple server-main/extensionHost builds stayed up for days
# with estab_conns=0 despite --enable-remote-auto-shutdown. Only the build with a live
# client must be kept.
#
# Safety gates (do not guess):
# - Never kill server-main with established TCP clients (ss estab > 0).
# - Never kill trees younger than MIN_AGE_SECONDS.
# - Protect every build hash that currently has estab > 0.
# - Default is dry-run unless --apply.
#
# Usage:
#   cursor-server-reaper [--apply] [--user NAME] [--min-age SECS] [--prune-bins]
# Cron (root): hourly, --apply for all users with ~/.cursor-server
set -uo pipefail

DRY_RUN=1
ONLY_USER=""
MIN_AGE_SECONDS=3600
PRUNE_BINS=0
LOG=/var/log/cursor-server-reaper.log

_log() {
    local line
    line="$(printf '[%s] %s' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*")"
    if [ -w "$(dirname "$LOG")" ] 2>/dev/null || [ -w "$LOG" ] 2>/dev/null; then
        printf '%s\n' "$line" >> "$LOG" 2>/dev/null || true
    fi
    logger -t cursor-server-reaper "$*" 2>/dev/null || true
    printf '%s\n' "$line"
}

_estab_for_pid() {
    local pid="$1" n
    n=$(ss -tnp 2>/dev/null | grep -c "pid=${pid}," || true)
    printf '%s' "${n:-0}"
}

_build_of_cmd() {
    # .../linux-x64/<hash>/...
    printf '%s' "$1" | sed -n 's|.*/linux-x64/\([^/]*\)/.*|\1|p' | head -1
}

_kill_tree() {
    local root="$1" c
    [ -n "$root" ] || return 0
    while read -r c; do
        c=$(echo "$c" | tr -d ' ')
        [ -n "$c" ] || continue
        _kill_tree "$c"
    done < <(ps -o pid= --ppid "$root" 2>/dev/null || true)
    if [ "$DRY_RUN" -eq 1 ]; then
        _log "DRY_RUN would_kill pid=$root"
    else
        kill -TERM "$root" 2>/dev/null || true
        sleep 0.2
        kill -KILL "$root" 2>/dev/null || true
        _log "killed pid=$root"
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --apply) DRY_RUN=0; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --user) ONLY_USER="${2:-}"; shift 2 ;;
        --min-age) MIN_AGE_SECONDS="${2:-3600}"; shift 2 ;;
        --prune-bins) PRUNE_BINS=1; shift ;;
        -h|--help)
            echo "Usage: cursor-server-reaper [--apply] [--user NAME] [--min-age SECS] [--prune-bins]"
            exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

[ -f "$LOG" ] || { touch "$LOG" 2>/dev/null; chmod 600 "$LOG" 2>/dev/null || true; }

_reap_user() {
    local user="$1" home killed=0
    home=$(getent passwd "$user" | cut -d: -f6)
    [ -n "$home" ] && [ -d "$home/.cursor-server" ] || return 0

    local -A protected_builds=()
    local -a kill_pids=()
    local pid etime cmd build estab

    # Pass 1: mark protected builds (any server-main with clients)
    while read -r pid etime cmd; do
        [ -n "${pid:-}" ] || continue
        case "$cmd" in
            *server-main.js*) ;;
            *) continue ;;
        esac
        build="$(_build_of_cmd "$cmd")"
        [ -n "$build" ] || continue
        estab="$(_estab_for_pid "$pid")"
        estab=${estab:-0}
        if [ "$estab" -gt 0 ] 2>/dev/null; then
            protected_builds["$build"]=1
            _log "protect user=$user build=$build pid=$pid estab=$estab age_s=$etime"
        fi
    done < <(ps -u "$user" -o pid=,etimes=,cmd= 2>/dev/null || true)

    # Pass 2: idle old server-main not in protected builds
    while read -r pid etime cmd; do
        [ -n "${pid:-}" ] || continue
        case "$cmd" in
            *server-main.js*) ;;
            *) continue ;;
        esac
        build="$(_build_of_cmd "$cmd")"
        [ -n "$build" ] || continue
        [ "${etime:-0}" -ge "$MIN_AGE_SECONDS" ] || continue
        estab="$(_estab_for_pid "$pid")"
        estab=${estab:-0}
        [ "$estab" -eq 0 ] 2>/dev/null || continue
        if [ -n "${protected_builds[$build]:-}" ]; then
            _log "skip user=$user build=$build pid=$pid reason=build_protected_by_sibling"
            continue
        fi
        _log "reap_candidate user=$user build=$build pid=$pid age_s=$etime estab=0"
        kill_pids+=("$pid")
    done < <(ps -u "$user" -o pid=,etimes=,cmd= 2>/dev/null || true)

    if [ "${#kill_pids[@]}" -gt 0 ]; then
        for pid in "${kill_pids[@]}"; do
            [ -n "$pid" ] || continue
            _kill_tree "$pid"
            killed=$((killed + 1))
        done
    fi

    if [ "$PRUNE_BINS" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
        local binroot="$home/.cursor-server/bin/linux-x64" b
        [ -d "$binroot" ] || return 0
        for b in "$binroot"/*; do
            [ -d "$b" ] || continue
            build=$(basename "$b")
            if [ -n "${protected_builds[$build]:-}" ]; then
                continue
            fi
            if ps -u "$user" -o cmd= 2>/dev/null | grep -q "/linux-x64/${build}/"; then
                continue
            fi
            _log "prune_bin user=$user build=$build"
            rm -rf "$b" 2>/dev/null || true
        done
    elif [ "$PRUNE_BINS" -eq 1 ] && [ "$DRY_RUN" -eq 1 ]; then
        _log "DRY_RUN prune-bins skipped (pass --apply)"
    fi

    [ "$killed" -gt 0 ] && _log "user=$user reap_done candidates=$killed dry_run=$DRY_RUN"
    return 0
}

if [ -n "$ONLY_USER" ]; then
    _reap_user "$ONLY_USER"
else
    if [ "$(id -u)" -eq 0 ]; then
        for home in /home/*; do
            [ -d "$home/.cursor-server" ] || continue
            _reap_user "$(basename "$home")"
        done
    else
        _reap_user "$(id -un)"
    fi
fi

exit 0
