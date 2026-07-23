# connect-ui.sh - terminal UI helpers (sourced by connect.sh)

ui_terminal_width() {
    local c
    c="$(tput cols 2>/dev/null || true)"
    if [ -n "$c" ] && [ "$c" -ge 40 ] 2>/dev/null; then
        printf '%s' "$c"
    else
        printf '80'
    fi
}

ui_layout_tier() {
    local w="${1:-$(ui_terminal_width)}"
    if [ "$w" -ge 100 ]; then printf 'wide'
    elif [ "$w" -ge 72 ]; then printf 'normal'
    elif [ "$w" -ge 60 ]; then printf 'narrow'
    else printf 'tiny'
    fi
}

ui_trunc_path() {
    local p="$1" max="${2:-40}" len
    [ -z "$p" ] && return 0
    len="${#p}"
    if [ "$len" -le "$max" ]; then printf '%s' "$p"; return 0
    fi
    printf '%s...%s' "${p:0:12}" "${p:$((len - max + 15))}"
}

ui_connect_header() {
    local alias="$1" ip="$2" ver="$3" w tier inner
    w="$(ui_terminal_width)"
    tier="$(ui_layout_tier "$w")"
    echo ""
    if [ "$tier" = "tiny" ]; then
        printf '    \033[0;36m--- Claude Connect ---\033[0m\n'
        printf '    \033[0;90m%s  |  %s  |  v%s\033[0m\n' "$alias" "$ip" "$ver"
    else
        inner=44
        [ "$w" -lt 48 ] && inner=$(( w - 4 ))
        printf '    \033[0;36m+%*s+\033[0m\n' "$inner" | tr ' ' '='
        printf '    \033[0;36m| Claude Connect %*s|\033[0m\n' $(( inner - 16 )) ''
        printf '    \033[0;36m+%*s+\033[0m\n' "$inner" | tr ' ' '='
        printf '    \033[0;90m%s  |  %s  |  v%s\033[0m\n' "$alias" "$ip" "$ver"
    fi
    echo ""
}

ui_git_mode_label() {
    case "${1:-off}" in
        server|slow) printf 'SLOW' ;;
        hide|fast) printf 'HIDE' ;;
        *) printf 'OFF' ;;
    esac
}

ui_git_mode_banner() {
    local mode="$1" label desc
    label="$(ui_git_mode_label "$mode")"
    case "$mode" in
        server) desc='full git over SSHFS' ;;
        hide)   desc='hide .git on laptop' ;;
        *)      desc='no .git rename; laptop-exec git' ;;
    esac
    printf '    \033[0;90mGit mode: %s (%s) - press g to change\033[0m\n\n' "$label" "$desc"
}

ui_trunc_label() {
    local t="$1" max="$2"
    [ -z "$t" ] && return 0
    if [ "$max" -le 0 ]; then printf '%s' "$t"; return 0; fi
    if [ "${#t}" -le "$max" ]; then printf '%s' "$t"; return 0; fi
    if [ "$max" -le 3 ]; then printf '...'; return 0; fi
    printf '%s...' "${t:0:$((max - 3))}"
}

ui_project_name_col() {
    local raw="$1" w="$2" path_max="$3" max_label=0 len fixed avail want
    while IFS='|' read -r mid mlabel _ _; do
        [ -z "$mid" ] && continue
        len="${#mlabel}"
        [ "$len" -gt "$max_label" ] && max_label=$len
    done <<< "$raw"
    [ "$max_label" -lt 10 ] && max_label=10
    fixed=$(( 4 + 2 + 2 + 2 + path_max ))
    avail=$(( w - fixed ))
    if [ "$avail" -lt 10 ]; then printf '0'; return 0; fi
    want=$(( max_label + 9 ))
    if [ "$want" -gt "$avail" ]; then printf '%s' "$avail"; else printf '%s' "$want"; fi
}

ui_project_table() {
    local raw="$1" tier w path_max name_col i=1 os="${GIT_MODE_LAPTOP_OS:-mac}"
    w="$(ui_terminal_width)"
    tier="$(ui_layout_tier "$w")"
    case "$tier" in
        wide) path_max=50 ;;
        normal) path_max=36 ;;
        narrow) path_max=24 ;;
        *) path_max=0 ;;
    esac
    name_col=0
    if [ "$path_max" -gt 0 ]; then
        name_col="$(ui_project_name_col "$raw" "$w" "$path_max")"
        if [ "$name_col" -eq 0 ]; then
            tier=tiny
            path_max=0
        fi
    fi
    printf '    \033[1;37mProjects\033[0m\n\n'
    if [ -z "$raw" ]; then
        printf '    \033[0;90m(no projects configured)\033[0m\n\n'
        return
    fi
    local mid mlabel mrpath mlpath active_tag os_tag path_show
    while IFS='|' read -r mid mlabel mrpath mlpath; do
        [ -z "$mid" ] && continue
        if declare -f laptop_rpath_compatible >/dev/null 2>&1; then
            laptop_rpath_compatible "$mrpath" "$os" || continue
        fi
        active_tag=""
        os_tag=""
        [ -n "${ACTIVE_MOUNT_ID:-}" ] && [ "$mid" = "$ACTIVE_MOUNT_ID" ] && active_tag=' (mounted)'
        if declare -f laptop_rpath_exists >/dev/null 2>&1 && ! laptop_rpath_exists "$mrpath"; then
            os_tag=' [missing]'
        fi
        if [ "$path_max" -gt 0 ]; then
            path_show="$(ui_trunc_path "$mrpath" "$path_max")$os_tag"
            if [ -n "$active_tag" ]; then
                name_show="$(ui_trunc_label "$mlabel" $(( name_col - 9 )) )"
                padded="$(printf '%-*s' $(( name_col - 9 )) "$name_show")"
                printf '    \033[1;37m%2d  %s\033[0;32m%s\033[0m  %s\n' "$i" "$padded" "$active_tag" "$path_show"
            else
                name_show="$(ui_trunc_label "$mlabel" "$name_col")"
                printf '    \033[0;90m%2d  %-*s  %s\033[0m\n' "$i" "$name_col" "$name_show" "$path_show"
            fi
        else
            printf '    \033[0;90m%d  %s%s%s\033[0m\n' "$i" "$mlabel" "$active_tag" "$os_tag"
            if [ -n "$mrpath" ]; then
                printf '         %s\n' "$(ui_trunc_path "$mrpath" 56)$os_tag"
            fi
        fi
        i=$(( i + 1 ))
    done <<< "$raw"
    echo ""
    printf '    \033[0;90ma add   e edit   d delete   c config   g git   q quit\033[0m\n\n'
}

ui_session_box() {
    echo ""
    printf '    ============================================\n'
    printf '    \033[0;36mSession active -- keep this window open\033[0m\n'
    printf '    \033[0;90mG = git mode   O = reopen editor   R = reconnect   Q or Enter = disconnect (closes editor)\033[0m\n'
    while [ "$#" -gt 0 ]; do
        printf '    \033[0;33m%s\033[0m\n' "$1"
        shift
    done
    printf '    ============================================\n'
    echo ""
}

ui_session_status_line() {
    local project="$1" git_label="$2" tunnel_ok="${3:-1}" editor_open="${4:-0}" editor_name="${5:-Cursor}"
    local tunnel ed
    [ "$tunnel_ok" -eq 1 ] && tunnel=up || tunnel=down
    [ "$editor_open" -eq 1 ] && ed="$editor_name" || ed=closed
    printf '    \033[0;36m[%s | git:%s | tunnel:%s | %s]\033[0m\n' "$project" "$git_label" "$tunnel" "$ed"
}

ui_set_title() {
    printf '\033]0;%s\007' "${1:-Claude Connect}"
}

ui_show_toast() {
    local msg="$1"
    [ -z "$msg" ] && return 0
    osascript -e "display notification \"$msg\" with title \"Claude Connect\"" 2>/dev/null || true
}

ui_pick_folder() {
    local pick
    pick="$(osascript -e 'POSIX path of (choose folder with prompt "Select project folder")' 2>/dev/null)" || true
    if [ -n "$pick" ]; then
        printf '%s' "$pick" | sed 's:/*$::'
        return 0
    fi
    return 1
}

ui_bootstrap_hint() {
    local cfg_dir="$1"
    if [ -f "$cfg_dir/bootstrap.done" ]; then
        printf '    \033[0;90mReconnect ~15s\033[0m\n'
    else
        printf '    \033[0;90mFirst setup may take ~1 min\033[0m\n'
    fi
}

ui_mark_bootstrap_done() {
    local cfg_dir="$1"
    date -u +%Y-%m-%dT%H:%M:%SZ > "$cfg_dir/bootstrap.done" 2>/dev/null || true
}
# Durable local day logs under ~/.config/claude-connect/logs/ plus sync to server.
CONNECT_LOG_SYNC_NEEDED=0
CONNECT_LOG_WARN_UNTIL=0
CONNECT_LOG_DRAINER_PID=""
CONNECT_LOG_ASYNC_STALL_SINCE=0


connect_prompt() {
    local prompt="$1" tag="${2:-INPUT}" var
    read -rp "$prompt" var
    connect_log "INPUT: tag=$tag prompt=$(printf '%s' "$prompt" | tr '\n' ' ') answer=$var"
    printf '%s' "$var"
}

connect_decision() {
    local what="$1" value="$2" level="${3:-INFO}"
    connect_log "DECISION: ${what}=${value}" "$level"
}

_connect_log_async_drainer_loop() {
    # Bounded background drain (parity with Windows Ensure-ConnectLogAsyncTimer, no Start-Job/subshell leaks).
    local guard=0
    while [ "$guard" -lt 20 ]; do
        guard=$((guard + 1))
        if declare -F _connect_log_unsynced_bytes >/dev/null 2>&1; then
            unsynced="$(_connect_log_unsynced_bytes)"
            if [ "${unsynced:-0}" -gt 262144 ] 2>/dev/null; then
                if [ "${CONNECT_LOG_ASYNC_STALL_SINCE:-0}" -eq 0 ] 2>/dev/null; then
                    CONNECT_LOG_ASYNC_STALL_SINCE="$(date +%s)"
                elif [ "$(($(date +%s) - CONNECT_LOG_ASYNC_STALL_SINCE))" -ge 120 ] 2>/dev/null; then
                    sync_connect_log_to_server force || true
                    CONNECT_LOG_ASYNC_STALL_SINCE=0
                    sleep 1.5
                    continue
                fi
            else
                CONNECT_LOG_ASYNC_STALL_SINCE=0
            fi
        fi
        sync_connect_log_to_server || true
        sleep 1.5
    done
}

_ensure_connect_log_async_drainer() {
    if [ -n "${CONNECT_LOG_DRAINER_PID:-}" ] && kill -0 "${CONNECT_LOG_DRAINER_PID}" 2>/dev/null; then
        return 0
    fi
    _connect_log_async_drainer_loop &
    CONNECT_LOG_DRAINER_PID=$!
    disown "${CONNECT_LOG_DRAINER_PID}" 2>/dev/null || true
}

request_connect_log_sync() {
    # $1=force -> barrier (stop drainer, coalesce, then Force sync). Else: coalesce + background drain.
    local force="${1:-}"
    if [ "$force" = "force" ]; then
        complete_connect_log_async_drain force
        return 0
    fi
    local already_needed="${CONNECT_LOG_SYNC_NEEDED:-0}"
    CONNECT_LOG_SYNC_NEEDED=1
    if declare -F _connect_log_unsynced_bytes >/dev/null 2>&1; then
        unsynced="$(_connect_log_unsynced_bytes)"
        if [ "${unsynced:-0}" -gt 262144 ] 2>/dev/null; then
            if [ "${CONNECT_LOG_ASYNC_STALL_SINCE:-0}" -eq 0 ] 2>/dev/null; then
                CONNECT_LOG_ASYNC_STALL_SINCE="$(date +%s)"
            fi
        else
            CONNECT_LOG_ASYNC_STALL_SINCE=0
        fi
    fi
    if [ "$already_needed" != "1" ] && declare -F connect_log >/dev/null 2>&1; then
        connect_log "LOG_SYNC_ASYNC scheduled=1" 'DEBUG'
    fi
    _ensure_connect_log_async_drainer
}

complete_connect_log_async_drain() {
    # $1=force -> after draining Needed/WARN coalesce, also run a final Force sync.
    local force="${1:-}"
    if [ -n "${CONNECT_LOG_DRAINER_PID:-}" ]; then
        kill "${CONNECT_LOG_DRAINER_PID}" 2>/dev/null || true
        wait "${CONNECT_LOG_DRAINER_PID}" 2>/dev/null || true
        CONNECT_LOG_DRAINER_PID=""
    fi
    if [ "${CONNECT_LOG_SYNC_NEEDED:-0}" = "1" ] || [ "${CONNECT_LOG_WARN_UNTIL:-0}" -gt 0 ] 2>/dev/null; then
        sync_connect_log_to_server || true
    fi
    CONNECT_LOG_SYNC_NEEDED=0
    CONNECT_LOG_WARN_UNTIL=0
    if [ "$force" = "force" ]; then
        sync_connect_log_to_server force || true
    fi
}

connect_log_ts() {
    # Milliseconds for parity with Windows Write-ConnectLog (.fff).
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import time; t=time.time(); print(time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)) + ".%03d" % int((t%1)*1000))' 2>/dev/null && return 0
    fi
    date '+%Y-%m-%d %H:%M:%S.000'
}


write_connect_scorecard() {
    # #19: always-on INFO day-log; UI only when CLAUDE_CONNECT_SCORECARD_UI=1
    local phase="${1:-boot}"
    local ver="${CONNECT_VERSION:-unknown}"
    local am="${ACTIVE_MOUNT_ID:-${go_id:-none}}"
    local ed='closed'
    [ "${_editor_opened:-0}" = "1" ] && ed='open'
    local banner='n/a'
    [ "${TUNNEL_BANNER_CACHE_UP:-0}" = "1" ] && banner='ok'
    local line="SCORECARD ${phase} auth_ms=n/a banner=${banner} mount_ms=n/a am=${am} editor=${ed} slot=0 ver=${ver}"
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "$line" 'INFO'
    fi
    if [ "${CLAUDE_CONNECT_SCORECARD_UI:-0}" = "1" ]; then
        printf '  %s\n' "$line" >&2
    fi
}

connect_log() {
    local msg="$1" level="${2:-INFO}"
    [ -n "${CONNECT_LOG_PATH:-}" ] || return 0
    # Midnight rollover: flush previous day before abandoning (bug 37).
    local day_path="$HOME/.config/claude-connect/logs/connect-$(date +%Y%m%d).log"
    if [ "$CONNECT_LOG_PATH" != "$day_path" ]; then
        sync_connect_log_to_server force || true
        CONNECT_LOG_PATH="$day_path"
        CONNECT_LOG_SYNC_OFF=0
        CONNECT_LOG_LINES_SINCE_SYNC=0
        mkdir -p "$(dirname "$CONNECT_LOG_PATH")" 2>/dev/null || true
        local wm="${CONNECT_LOG_PATH}.sync-offset"
        if [ -f "$wm" ]; then
            CONNECT_LOG_SYNC_OFF="$(tr -dc '0-9' < "$wm")"
        fi
        : "${CONNECT_LOG_SYNC_OFF:=0}"
        touch "$CONNECT_LOG_PATH" 2>/dev/null || true
        chmod 600 "$CONNECT_LOG_PATH" 2>/dev/null || true
    fi
    printf '[%s] [%s] [%s] %s\n' "$(connect_log_ts)" "$level" "${CONNECT_SESSION_ID:--}" "$msg" >> "$CONNECT_LOG_PATH" 2>/dev/null || true
    # Local always complete. Sync carefully (parity with Windows connect-ui.ps1):
    # - TRACE/DEBUG stay local-only during hot loops except TUNNEL_* TRACE (bug 36)
    # - WARN/ERROR flush now; INFO every 25 lines
    if [ "$level" = "TRACE" ] || [ "$level" = "DEBUG" ]; then
        if [ "$level" = "TRACE" ] && printf '%s' "$msg" | grep -q 'TUNNEL_'; then
            CONNECT_LOG_LINES_SINCE_SYNC=$(( ${CONNECT_LOG_LINES_SINCE_SYNC:-0} + 1 ))
            if printf '%s' "$msg" | grep -Eq 'soft_fail|TUNNEL_DROP|TUNNEL_EXIT' || [ "${CONNECT_LOG_LINES_SINCE_SYNC:-0}" -ge 25 ]; then
                if declare -F request_connect_log_sync >/dev/null 2>&1; then
                    request_connect_log_sync || true
                else
                    sync_connect_log_to_server || true
                fi
            fi
        fi
        return 0
    fi
    CONNECT_LOG_LINES_SINCE_SYNC=$(( ${CONNECT_LOG_LINES_SINCE_SYNC:-0} + 1 ))
    if [ "$level" = "ERROR" ]; then
        # Force: do not stick behind TRACE-only path or nonblocking flock miss.
        if declare -F complete_connect_log_async_drain >/dev/null 2>&1; then
            complete_connect_log_async_drain force || true
        else
            sync_connect_log_to_server force || true
        fi
    elif [ "$level" = "WARN" ]; then
        # Coalesce: warn-only bursts get a 5s grace window instead of an immediate Force sync.
        CONNECT_LOG_WARN_UNTIL=$(( $(date +%s) + 5 ))
        CONNECT_LOG_SYNC_NEEDED=1
        if declare -F request_connect_log_sync >/dev/null 2>&1; then
            request_connect_log_sync || true
        else
            sync_connect_log_to_server force || true
        fi
    elif [ "${CONNECT_LOG_LINES_SINCE_SYNC:-0}" -ge 25 ]; then
        if declare -F request_connect_log_sync >/dev/null 2>&1; then
            request_connect_log_sync || true
        else
            sync_connect_log_to_server || true
        fi
    fi
}


invoke_connect_silent_update_check() {
    declare -F connect_log >/dev/null 2>&1 || return 0

    if declare -F tunnel_up >/dev/null 2>&1; then
        if ! tunnel_up; then
            connect_log "UPDATE_SILENT skip reason=tunnel_down" 'DEBUG'
            return 0
        fi
    fi

    local cfg_dir="$HOME/.config/claude-connect"
    local state_file="$cfg_dir/.last-update-check"
    local now last_check age_sec age_min script_dir update_sh exit_code result pending level

    now="$(date +%s)"
    last_check=0
    if [ -f "$state_file" ]; then
        last_check="$(tr -dc '0-9' < "$state_file" | head -c 20)"
        [ -n "$last_check" ] || last_check=0
    fi

    age_sec=$(( now - last_check ))
    age_min=$(( age_sec / 60 ))
    if [ "$last_check" -gt 0 ] && [ "$age_sec" -lt 1800 ]; then
        connect_log "UPDATE_SILENT skip reason=throttle age_min=$age_min" 'DEBUG'
        return 0
    fi

    script_dir="${CONNECT_SCRIPT_DIR:-${SCRIPT_DIR:-}}"
    if [ -z "$script_dir" ]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi

    update_sh="$script_dir/connect-update.sh"
    if [ ! -f "$update_sh" ] && [ -f "$script_dir/mac/connect-update.sh" ]; then
        update_sh="$script_dir/mac/connect-update.sh"
    fi
    if [ ! -f "$update_sh" ] && [ -f "$(dirname "$script_dir")/mac/connect-update.sh" ]; then
        update_sh="$(dirname "$script_dir")/mac/connect-update.sh"
    fi
    exit_code=1
    result='fail'
    pending=0
    level='ERROR'

    if [ ! -f "$update_sh" ]; then
        connect_log "UPDATE_SILENT age_min=$age_min result=fail exit=1 pending_restart=0 reason=no_script path=$update_sh" 'ERROR'
        return 0
    fi

    set +e
    CLAUDE_CONNECT_UPDATE_QUIET=1 bash "$update_sh"
    exit_code=$?
    case "$exit_code" in
        0) result='ok'; level='INFO' ;;
        1) result='fail'; level='ERROR' ;;
        2)
            result='applied'
            pending=1
            level='WARN'
            CONNECT_UPDATE_PENDING_RESTART=1
            export CONNECT_UPDATE_PENDING_RESTART
            ;;
        *) result='fail'; level='ERROR' ;;
    esac

    if [ "$exit_code" -eq 2 ]; then
        connect_log "UPDATE_SILENT pending_restart=1 age_min=$age_min result=$result exit=$exit_code note=restart_connect_after_session" "$level"
    else
        connect_log "UPDATE_SILENT age_min=$age_min result=$result exit=$exit_code pending_restart=$pending" "$level"
    fi

    if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 2 ]; then
        mkdir -p "$cfg_dir" 2>/dev/null || true
        if ! printf '%s' "$now" > "$state_file" 2>/dev/null; then
            connect_log "UPDATE_SILENT stamp_fail" 'ERROR'
        fi
    fi
}


_connect_log_sync_fail() {
    local detail="${1:-sync_fail}"
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "LOG_SYNC_FAIL detail=${detail} (local kept; retry later)" 'WARN'
    fi
}

test_connect_remote_log_needs_rebuild() {
    local local_size="$1" remote_size="$2" offset="$3"
    [ -z "$remote_size" ] && remote_size=0
    [ -z "$local_size" ] && local_size=0
    [ -z "$offset" ] && offset=0
    # Stage 9: never replace remote with smaller local (forbid shrink).
    if [ "$local_size" -lt "$remote_size" ] 2>/dev/null; then return 1; fi
    return 1
}

_connect_log_unsynced_bytes() {
    local lp="${CONNECT_LOG_PATH:-}" off=0 sz=0
    [ -n "$lp" ] && [ -f "$lp" ] || { printf '0'; return 0; }
    if [ -f "${lp}.sync-offset" ]; then
        off="$(tr -dc '0-9' < "${lp}.sync-offset")"
    fi
    : "${off:=0}"
    sz="$(wc -c < "$lp" | tr -dc '0-9')"
    : "${sz:=0}"
    if [ "$off" -gt "$sz" ] 2>/dev/null; then printf '%s' "$sz"; return 0; fi
    printf '%s' $((sz - off))
}

_server_logs_cleanup_cmd() {
    printf '%s' 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; find "$HOME/.claude/logs" -type f -mtime +1 -delete 2>/dev/null; true'
}

sync_connect_log_to_server() {
    # Append unsynced local bytes to ~/.claude/logs/connect-YYYYMMDD.log on server.
    # $1=force -> wait briefly for lock (exit/ERROR flush).
    local force="${1:-}"
    local day remote_tmp remote_day off take size actual lockfile cat_ok guard
    [ -n "${CONNECT_LOG_PATH:-}" ] && [ -f "${CONNECT_LOG_PATH}" ] || return 0
    [ -n "${ALIAS:-}" ] || return 0
    command -v ssh >/dev/null 2>&1 || return 0
    command -v scp >/dev/null 2>&1 || return 0

    # Bug 72: serialize overlapping syncs via flock on .sync-lock
    lockfile="${CONNECT_LOG_PATH}.sync-lock"
    exec 8>"$lockfile" || return 0
    if [ "$force" = "force" ]; then
        flock -w 5 8 || return 0
    else
        flock -n 8 || { CONNECT_LOG_SYNC_NEEDED=1; return 0; }
    fi

    # Re-read watermark under lock (avoid offset-reset races).
    if [ -f "${CONNECT_LOG_PATH}.sync-offset" ]; then
        CONNECT_LOG_SYNC_OFF="$(tr -dc '0-9' < "${CONNECT_LOG_PATH}.sync-offset")"
    fi
    : "${CONNECT_LOG_SYNC_OFF:=0}"
    off="${CONNECT_LOG_SYNC_OFF:-0}"

    # Derive day from local file name when possible (midnight-safe).
    case "$(basename "$CONNECT_LOG_PATH")" in
        connect-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].log)
            day="$(basename "$CONNECT_LOG_PATH" | cut -d- -f2 | cut -d. -f1)"
            ;;
        *)
            day="$(date +%Y%m%d)"
            ;;
    esac
    remote_day=".claude/logs/connect-${day}.log"
    remote_tmp=".claude/logs/.connect-buf-$$.tmp"

    size="$(wc -c < "$CONNECT_LOG_PATH" | tr -dc '0-9')"
    : "${size:=0}"
    if [ "$off" -gt "$size" ] 2>/dev/null; then off=0; fi
    if [ "$off" -ge "$size" ] 2>/dev/null; then
        flock -u 8 2>/dev/null || true
        return 0
    fi
    take=$((size - off))
    if [ "$take" -gt 524288 ]; then take=524288; fi

    # Bug 38: never use $(tail) - cmdsubst strips trailing newlines and over-advances watermark.
    # Byte-exact extract via dd into chunk file.
    rm -f "${CONNECT_LOG_PATH}.chunk"
    if ! dd if="$CONNECT_LOG_PATH" of="${CONNECT_LOG_PATH}.chunk" bs=1 skip="$off" count="$take" 2>/dev/null; then
        rm -f "${CONNECT_LOG_PATH}.chunk"
        flock -u 8 2>/dev/null || true
        return 0
    fi
    actual="$(wc -c < "${CONNECT_LOG_PATH}.chunk" | tr -dc '0-9')"
    : "${actual:=0}"
    if [ "$actual" -le 0 ]; then
        rm -f "${CONNECT_LOG_PATH}.chunk"
        flock -u 8 2>/dev/null || true
        return 0
    fi
    take="$actual"

    remote_before=0
    if declare -F sshx >/dev/null 2>&1; then
        remote_before="$(sshx "stat -c%s \"\$HOME/${remote_day}\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
    else
        remote_before="$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" "stat -c%s \"\$HOME/${remote_day}\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
    fi
    : "${remote_before:=0}"
    if [ "$size" -lt "$remote_before" ] 2>/dev/null; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "LOG_SYNC_SKIP reason=forbid_shrink local=$size remote_was=$remote_before off=$off (append/merge only)" 'INFO'
        fi
    fi
    if declare -F test_connect_remote_log_needs_rebuild >/dev/null 2>&1 && test_connect_remote_log_needs_rebuild "$size" "$remote_before" "$off"; then
        rm -f "${CONNECT_LOG_PATH}.sync-pending" "${CONNECT_LOG_PATH}.chunk" 2>/dev/null || true
        if declare -F sshx >/dev/null 2>&1; then
            sshx "$(_server_logs_cleanup_cmd)" >/dev/null 2>&1 || true
        fi
        if scp -o BatchMode=yes -o ConnectTimeout=20 -q "$CONNECT_LOG_PATH" "${ALIAS}:${remote_tmp}" 2>/dev/null; then
            rep_ok=0
            if declare -F sshx >/dev/null 2>&1; then
                if sshx "cat \"\$HOME/${remote_tmp}\" > \"\$HOME/${remote_day}\"; ec=\$?; rm -f \"\$HOME/${remote_tmp}\"; chmod 600 \"\$HOME/${remote_day}\" 2>/dev/null; exit \$ec" >/dev/null 2>&1; then
                    rep_ok=1
                fi
            else
                if ssh -o BatchMode=yes -o ConnectTimeout=12 "$ALIAS" "cat \"\$HOME/${remote_tmp}\" > \"\$HOME/${remote_day}\"; ec=\$?; rm -f \"\$HOME/${remote_tmp}\"; chmod 600 \"\$HOME/${remote_day}\" 2>/dev/null; exit \$ec" >/dev/null 2>&1; then
                    rep_ok=1
                fi
            fi
            if [ "$rep_ok" = 1 ]; then
                CONNECT_LOG_SYNC_OFF="$size"
                printf '%s' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset" 2>/dev/null || true
                CONNECT_LOG_LINES_SINCE_SYNC=0
                CONNECT_LOG_SYNC_NEEDED=0
                CONNECT_LOG_ASYNC_STALL_SINCE=0
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "LOG_SYNC_REBUILD local=$size remote_was=$remote_before off=$off (replaced remote day log)" 'INFO'
                fi
                flock -u 8 2>/dev/null || true
                return 0
            fi
        fi
    fi

    # --- LOG_SYNC_RECONCILE (parity with Windows): pending + size verify + tail hash ---
    pending_file="${CONNECT_LOG_PATH}.sync-pending"
    remote_before=0
    if [ -f "$pending_file" ]; then
        IFS='|' read -r pend_off pend_take pend_r0 < "$pending_file" || true
        if [ "$pend_off" = "$off" ] && [ "$pend_take" = "$take" ]; then
            r_now=0
            if declare -F sshx >/dev/null 2>&1; then
                r_now="$(sshx "stat -c%s \"\$HOME/${remote_day}\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
            else
                r_now="$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" "stat -c%s \"\$HOME/${remote_day}\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
            fi
            : "${r_now:=0}"
            need=$((pend_r0 + pend_take))
            if [ "$r_now" -ge "$need" ] 2>/dev/null; then
                CONNECT_LOG_SYNC_OFF=$((off + take))
                printf '%s' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset" 2>/dev/null || true
                rm -f "$pending_file" "${CONNECT_LOG_PATH}.chunk"
                flock -u 8 2>/dev/null || true
                return 0
            fi
        fi
    fi
    local_hash="$(sha256sum "${CONNECT_LOG_PATH}.chunk" 2>/dev/null | awk '{print $1}')"
    if [ -n "$local_hash" ]; then
        if declare -F sshx >/dev/null 2>&1; then
            remote_hash="$(sshx "f=\"\$HOME/${remote_day}\"; [ -f \"\$f\" ] || { echo none; exit 0; }; sz=\$(stat -c%s \"\$f\" 2>/dev/null || echo 0); [ \"\$sz\" -ge ${take} ] || { echo short; exit 0; }; tail -c ${take} \"\$f\" | sha256sum | awk '{print \$1}'" 2>/dev/null | tr -dc 'a-f0-9')"
        else
            remote_hash="$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$ALIAS" "f=\"\$HOME/${remote_day}\"; [ -f \"\$f\" ] || { echo none; exit 0; }; sz=\$(stat -c%s \"\$f\" 2>/dev/null || echo 0); [ \"\$sz\" -ge ${take} ] || { echo short; exit 0; }; tail -c ${take} \"\$f\" | sha256sum | awk '{print \$1}'" 2>/dev/null | tr -dc 'a-f0-9')"
        fi
        if [ -n "$remote_hash" ] && [ "$remote_hash" = "$local_hash" ]; then
            CONNECT_LOG_SYNC_OFF=$((off + take))
            printf '%s' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset" 2>/dev/null || true
            rm -f "$pending_file" "${CONNECT_LOG_PATH}.chunk"
            flock -u 8 2>/dev/null || true
            return 0
        fi
    fi
    if declare -F sshx >/dev/null 2>&1; then
        remote_before="$(sshx "stat -c%s \"\$HOME/${remote_day}\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
    else
        remote_before="$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" "stat -c%s \"\$HOME/${remote_day}\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
    fi
    : "${remote_before:=0}"
    printf '%s|%s|%s' "$off" "$take" "$remote_before" > "$pending_file" 2>/dev/null || true

    if declare -F sshx >/dev/null 2>&1; then
        sshx "$(_server_logs_cleanup_cmd)" >/dev/null 2>&1 || true
    fi

    if scp -o BatchMode=yes -o ConnectTimeout=12 -q "${CONNECT_LOG_PATH}.chunk" "${ALIAS}:${remote_tmp}" 2>/dev/null; then
        # Bug 11/12: no trailing true; only advance watermark if remote cat append succeeds.
        cat_ok=0
        if declare -F sshx >/dev/null 2>&1; then
            if sshx "cat \"\$HOME/${remote_tmp}\" >> \"\$HOME/${remote_day}\"; ec=\$?; rm -f \"\$HOME/${remote_tmp}\"; chmod 600 \"\$HOME/${remote_day}\" 2>/dev/null; exit \$ec" >/dev/null 2>&1; then
                cat_ok=1
            fi
        else
            if ssh -o BatchMode=yes -o ConnectTimeout=8 "$ALIAS" "cat \"\$HOME/${remote_tmp}\" >> \"\$HOME/${remote_day}\"; ec=\$?; rm -f \"\$HOME/${remote_tmp}\"; chmod 600 \"\$HOME/${remote_day}\" 2>/dev/null; exit \$ec" >/dev/null 2>&1; then
                cat_ok=1
            fi
        fi
        if [ "$cat_ok" != 1 ]; then
            # Timeout/false-negative: confirm append via remote size growth.
            if declare -F sshx >/dev/null 2>&1; then
                remote_after="$(sshx "stat -c%s \"\$HOME/${remote_day}\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
            else
                remote_after="$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" "stat -c%s \"\$HOME/${remote_day}\" 2>/dev/null || echo 0" 2>/dev/null | tr -dc '0-9')"
            fi
            : "${remote_after:=0}"
            need=$((remote_before + take))
            if [ "$remote_after" -ge "$need" ] 2>/dev/null; then
                cat_ok=1
            fi
        fi
        if [ "$cat_ok" = 1 ]; then
            CONNECT_LOG_SYNC_OFF=$((off + take))
            printf '%s' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset" 2>/dev/null || true
            rm -f "$pending_file" 2>/dev/null || true
            CONNECT_LOG_LINES_SINCE_SYNC=0
            # Force drain remaining chunks on exit/ERROR flush.
            if [ "$force" = "force" ] && [ "$CONNECT_LOG_SYNC_OFF" -lt "$size" ]; then
                guard=0
                while [ "$CONNECT_LOG_SYNC_OFF" -lt "$size" ] && [ "$guard" -lt 64 ]; do
                    guard=$((guard + 1))
                    off="$CONNECT_LOG_SYNC_OFF"
                    take=$((size - off))
                    if [ "$take" -gt 524288 ]; then take=524288; fi
                    if ! dd if="$CONNECT_LOG_PATH" of="${CONNECT_LOG_PATH}.chunk" bs=1 skip="$off" count="$take" 2>/dev/null; then
                        break
                    fi
                    actual="$(wc -c < "${CONNECT_LOG_PATH}.chunk" | tr -dc '0-9')"
                    : "${actual:=0}"
                    [ "$actual" -gt 0 ] || break
                    take="$actual"
                    scp -o BatchMode=yes -o ConnectTimeout=12 -q "${CONNECT_LOG_PATH}.chunk" "${ALIAS}:${remote_tmp}" 2>/dev/null || break
                    if declare -F sshx >/dev/null 2>&1; then
                        sshx "cat \"\$HOME/${remote_tmp}\" >> \"\$HOME/${remote_day}\"; ec=\$?; rm -f \"\$HOME/${remote_tmp}\"; chmod 600 \"\$HOME/${remote_day}\" 2>/dev/null; exit \$ec" >/dev/null 2>&1 || break
                    else
                        ssh -o BatchMode=yes -o ConnectTimeout=8 "$ALIAS" "cat \"\$HOME/${remote_tmp}\" >> \"\$HOME/${remote_day}\"; ec=\$?; rm -f \"\$HOME/${remote_tmp}\"; chmod 600 \"\$HOME/${remote_day}\" 2>/dev/null; exit \$ec" >/dev/null 2>&1 || break
                    fi
                    CONNECT_LOG_SYNC_OFF=$((off + take))
                    printf '%s' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset" 2>/dev/null || true
                done
            fi
        fi
    else
        _connect_log_sync_fail "scp_chunk_fail"
        rm -f "${CONNECT_LOG_PATH}.chunk"
        flock -u 8 2>/dev/null || true
        return 0
    fi
    rm -f "${CONNECT_LOG_PATH}.chunk"
    flock -u 8 2>/dev/null || true
    return 0
}

flush_connect_log_to_server() {
    if [ -n "${CONNECT_LOG_PATH:-}" ] && [ -f "${CONNECT_LOG_PATH}" ]; then
        # Direct append to avoid recursion through connect_log sync path mid-flush.
        printf '[%s] [INFO] [%s] %s\n' "$(connect_log_ts)" "${CONNECT_SESSION_ID:--}" '======== session end ========' >> "$CONNECT_LOG_PATH" 2>/dev/null || true
    fi
    if declare -F complete_connect_log_async_drain >/dev/null 2>&1; then
        complete_connect_log_async_drain force || true
    else
        sync_connect_log_to_server force || true
    fi
    # Keep durable local day log (do not delete).
    rm -f "${CONNECT_LOG_PATH}.chunk" 2>/dev/null || true
    CONNECT_LOG_PATH=""
    CONNECT_LOG_SYNC_OFF=0
}



enter_connect_single_instance() {
    # One connect UI per machine via flock on lock file.
    # connect.sh may already hold fd 9 (early flock before update).
    if [ "${CONNECT_LOCK_HELD:-0}" = 1 ]; then
        connect_log "SINGLE_INSTANCE: acquired pid=$$ via=early_flock" 'INFO'
        return 0
    fi
    local lockdir="${HOME}/.config/claude-connect"
    local lockfile="${lockdir}/connect.lock"
    mkdir -p "$lockdir" 2>/dev/null || true
    exec 9>"$lockfile" || return 1
    if ! flock -n 9; then
        connect_log "SINGLE_INSTANCE: blocked pid=$$" 'ERROR'
        printf '\n  [X] Another Claude Connect is already running.\n\n' >&2
        return 1
    fi
    CONNECT_LOCK_HELD=1
    connect_log "SINGLE_INSTANCE: acquired pid=$$" 'INFO'
    return 0
}

exit_connect_single_instance() {
    if [ "${CONNECT_LOCK_HELD:-0}" = 1 ]; then
        flock -u 9 2>/dev/null || true
        exec 9>&- 2>/dev/null || true
        CONNECT_LOCK_HELD=0
    fi
}

connect_session_id() {
    if [ -n "${CLAUDE_CONNECT_RUN_ID:-}" ] && [ "${#CLAUDE_CONNECT_RUN_ID}" -ge 8 ]; then
        printf '%s' "$CLAUDE_CONNECT_RUN_ID"
        return 0
    fi
    if [ -n "${CONNECT_SESSION_ID:-}" ] && [ "${#CONNECT_SESSION_ID}" -ge 8 ]; then
        printf '%s' "$CONNECT_SESSION_ID"
        return 0
    fi
    python3 -c 'import uuid;print(uuid.uuid4().hex[:12])' 2>/dev/null || printf '%s%04d' "$(date +%s)" "$$"
}

init_connect_log() {
    local script_dir="$1" version="$2" day log_dir wm project
    # Zero-loss offline-first: durable local day file + watermark sync-offset + server flush.
    # Retention: purge local logs older than 1 day (parity with server cron / Windows Clear-ConnectLocalLogsOlderThan).
    day="$(date +%Y%m%d)"
    log_dir="$HOME/.config/claude-connect/logs"
    mkdir -p "$log_dir" 2>/dev/null || true
    find "$log_dir" -type f -mtime +1 ! -name 'sessions.index' -delete 2>/dev/null || true
    CONNECT_LOG_PATH="$log_dir/connect-${day}.log"
    if [ -n "${CLAUDE_CONNECT_RUN_ID:-}" ] && [ "${#CLAUDE_CONNECT_RUN_ID}" -ge 8 ]; then
        CONNECT_SESSION_ID="$CLAUDE_CONNECT_RUN_ID"
    elif [ -n "${CONNECT_SESSION_ID:-}" ] && [ "${#CONNECT_SESSION_ID}" -ge 8 ]; then
        CLAUDE_CONNECT_RUN_ID="$CONNECT_SESSION_ID"
    else
        CONNECT_SESSION_ID="$(connect_session_id)"
        CLAUDE_CONNECT_RUN_ID="$CONNECT_SESSION_ID"
    fi
    export CLAUDE_CONNECT_RUN_ID
    export CONNECT_SESSION_ID
    wm="${CONNECT_LOG_PATH}.sync-offset"
    CONNECT_LOG_SYNC_OFF=0
    if [ -f "$wm" ]; then
        CONNECT_LOG_SYNC_OFF="$(tr -dc '0-9' < "$wm")"
    fi
    : "${CONNECT_LOG_SYNC_OFF:=0}"
    touch "$CONNECT_LOG_PATH" 2>/dev/null || true
    chmod 600 "$CONNECT_LOG_PATH" 2>/dev/null || true
    CONNECT_LOG_LINES_SINCE_SYNC=0
    CONNECT_LOG_SYNC_NEEDED=0
    CONNECT_LOG_WARN_UNTIL=0
    CONNECT_LOG_DRAINER_PID=""
    CONNECT_LOG_ASYNC_STALL_SINCE=0
    project="${ACTIVE_MOUNT_ID:-${ACTIVE_MOUNT:-}}"
    [ -n "$project" ] || project='-'
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$CONNECT_SESSION_ID" "$$" "${USER:-?}" \
        "$(hostname 2>/dev/null || echo ?)" "$version" "$project" \
        >> "$log_dir/sessions.index" 2>/dev/null || true
    connect_log "======== session start v$version user=$USER pid=$$ session=$CONNECT_SESSION_ID ========"
    connect_log "log sink: local:$CONNECT_LOG_PATH watermark=$CONNECT_LOG_SYNC_OFF + server:~/.claude/logs/ (local+server purge mtime+1)" 'INFO'
    connect_log "script_dir: $script_dir connect_version: $version" 'DEBUG'
    connect_log "SESSION_FILTER: grep \"[$CONNECT_SESSION_ID]\" $CONNECT_LOG_PATH (index: $log_dir/sessions.index)" 'INFO'
}
log_session_context() {
    # Full snapshot so server logs explain who/what/where without local files.
    local phase="${1:-unknown}"
    local gm am editor_pref realname mounts_n conf_snip
    [ -n "${CONNECT_LOG_PATH:-}" ] || return 0
    gm="?"
    if declare -F get_git_mode >/dev/null 2>&1; then gm="$(get_git_mode 2>/dev/null || echo '?')"; fi
    am="${ACTIVE_MOUNT_ID:-${ACTIVE_MOUNT:-}}"
    editor_pref="?"
    if [ -n "${CFG_DIR:-}" ] && declare -F get_editor_pref >/dev/null 2>&1; then
        editor_pref="$(get_editor_pref "$CFG_DIR" 2>/dev/null || echo '?')"
    fi
    realname=""
    if declare -F mac_login_realname >/dev/null 2>&1; then
        realname="$(mac_login_realname 2>/dev/null || true)"
    fi
    mounts_n="?"
    if declare -F load_mounts >/dev/null 2>&1; then
        mounts_n="$(load_mounts 2>/dev/null | grep -c . || echo 0)"
    fi
    connect_log "======== CONTEXT phase=$phase ========"
    connect_log "host=$(hostname 2>/dev/null || echo ?) uname=$(uname -s 2>/dev/null || echo ?)/$(uname -m 2>/dev/null || echo ?) whoami=$(whoami 2>/dev/null || echo ?) uid=$(id -u 2>/dev/null || echo ?)"
    connect_log "REMOTE_USER=${REMOTE_USER:-?} LAPTOP_USER=${LAPTOP_USER:-?} LAPTOP_REALNAME=${realname:-?} SERVER_IP=${SERVER_IP:-?} ALIAS=${ALIAS:-?} PORT=${PORT:-?} PORT_BASE=${CONNECT_PORT_BASE:-20000}"
    connect_log "CONNECT_VERSION=${CONNECT_VERSION:-?} GIT_MODE=$gm ACTIVE_MOUNT=${am:-none} LAPTOP_OS=${GIT_MODE_LAPTOP_OS:-mac} EDITOR_CMD=${EDITOR_CMD:-?} EDITOR_PREF=$editor_pref"
    connect_log "flags editor_opened=${_editor_opened:-0} already_down=${already_down:-0} laptop_ssh_verified=${LAPTOP_SSH_VERIFIED:-?} recovery_gen=${RECOVERY_GENERATION:-0} session_iter=${SESSION_LOOP_ITER:-0}"
    connect_log "paths CFG=${CFG:-?} CFG_DIR=${CFG_DIR:-?} SCRIPT_DIR=${SCRIPT_DIR:-?} HOME=$HOME"
    connect_log "mounts_configured=$mounts_n go_id=${go_id:-?} go_path=${go_path:-?}"
    if [ -n "${CFG:-}" ] && [ -f "$CFG" ]; then
        conf_snip="$(tr '\n' ' ' < "$CFG" 2>/dev/null | head -c 400)"
        connect_log "local_cfg: $conf_snip" 'DEBUG'
    fi
    if [ "$phase" = "session_end" ]; then
        if declare -F complete_connect_log_async_drain >/dev/null 2>&1; then
            complete_connect_log_async_drain force || true
        else
            sync_connect_log_to_server force || true
        fi
    elif declare -F request_connect_log_sync >/dev/null 2>&1; then
        request_connect_log_sync || true
    elif declare -F sync_connect_log_to_server >/dev/null 2>&1; then
        sync_connect_log_to_server || true
    fi
}

# macOS proxy parity stub (Windows implements Get-WindowsSystemProxy in connect-ui.ps1).
# Future: read networksetup/scutil for HTTP/HTTPS proxy and export HTTP_PROXY for update downloads.
get_mac_system_proxy() {
    echo "enabled=0 source=none"
}

apply_connect_proxy_environment() {
    : "${SERVER_IP:=}"
    connect_log "PROXY: enabled=0 source=mac_stub" "DEBUG"
}
