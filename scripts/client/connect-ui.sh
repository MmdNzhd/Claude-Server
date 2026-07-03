# connect-ui.sh — terminal UI helpers (sourced by connect.sh)

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
    case "${1:-hide}" in
        server|slow) printf 'SLOW' ;;
        *) printf 'FAST' ;;
    esac
}

ui_git_mode_banner() {
    local mode="$1" label desc
    label="$(ui_git_mode_label "$mode")"
    if [ "$label" = "FAST" ]; then desc='hide .git on laptop'
    else desc='full git over SSHFS'; fi
    printf '    \033[0;90mGit mode: %s (%s) — press g to change\033[0m\n\n' "$label" "$desc"
}

ui_project_table() {
    local raw="$1" last_id="${2:-}" tier w path_max i=1
    w="$(ui_terminal_width)"
    tier="$(ui_layout_tier "$w")"
    case "$tier" in
        wide) path_max=50 ;;
        normal) path_max=36 ;;
        narrow) path_max=24 ;;
        *) path_max=0 ;;
    esac
    printf '    \033[1;37mProjects\033[0m\n\n'
    if [ -z "$raw" ]; then
        printf '    \033[0;90m(no projects configured)\033[0m\n\n'
        return
    fi
    local mid mlabel mrpath mlpath active_tag path_show
    while IFS='|' read -r mid mlabel mrpath mlpath; do
        [ -z "$mid" ] && continue
        active_tag=""
        [ -n "${ACTIVE_MOUNT_ID:-}" ] && [ "$mid" = "$ACTIVE_MOUNT_ID" ] && active_tag=' (active)'
        if [ "$path_max" -gt 0 ]; then
            path_show="$(ui_trunc_path "$mrpath" "$path_max")"
            if [ -n "$active_tag" ]; then
                printf '    \033[1;37m%2d  %-14s  %s\033[0;32m%s\033[0m\n' "$i" "$mlabel" "$path_show" "$active_tag"
            else
                printf '    \033[0;90m%2d  %-14s  %s\033[0m\n' "$i" "$mlabel" "$path_show"
            fi
        else
            printf '    \033[0;90m%d  %s%s\033[0m\n' "$i" "$mlabel" "$active_tag"
        fi
        i=$(( i + 1 ))
    done <<< "$raw"
    echo ""
    if [ -n "$last_id" ]; then
        local row lbl
        row="$(printf '%s\n' "$raw" | grep "^${last_id}|" | head -1 || true)"
        if [ -n "$row" ]; then
            lbl="$(printf '%s' "$row" | cut -d'|' -f2)"
            printf '    \033[0;90m(Enter = %s)\033[0m\n' "$lbl"
        fi
    fi
    printf '    \033[0;90ma add   e edit   d delete   c config   g git   q quit\033[0m\n\n'
}

ui_session_box() {
    echo ""
    printf '    ============================================\n'
    printf '    \033[0;36mSession active -- keep this window open\033[0m\n'
    printf '    \033[0;90mG = git mode   R = reconnect   Q or Enter = disconnect (closes editor)\033[0m\n'
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
