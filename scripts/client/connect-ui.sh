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
        [ -n "${ACTIVE_MOUNT_ID:-}" ] && [ "$mid" = "$ACTIVE_MOUNT_ID" ] && active_tag=' (active)'
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
# Optional session log (no-op when CONNECT_LOG_PATH unset).
connect_log() {
    local msg="$1" level="${2:-INFO}"
    [ -n "${CONNECT_LOG_PATH:-}" ] || return 0
    mkdir -p "$(dirname "$CONNECT_LOG_PATH")" 2>/dev/null || true
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg" >> "$CONNECT_LOG_PATH" 2>/dev/null || true
}

init_connect_log() {
    local script_dir="$1" version="$2"
    CONNECT_LOG_PATH="${CONNECT_LOG_PATH:-$HOME/.config/claude-connect/logs/connect-$(date +%Y%m%d).log}"
    connect_log "======== session start v$version user=$USER pid=$$ ========"
    connect_log "script_dir: $script_dir connect_version: $version" 'DEBUG'
}


