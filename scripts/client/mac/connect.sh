#!/bin/bash
# connect.sh - Claude Code launcher for Mac/Linux.
# Usage:  bash connect.sh          (normal)
#         bash connect.sh --setup  (reconfigure)

set -uo pipefail

_update_script="$(cd "$(dirname "$0")" && pwd)/connect-update.sh"
if [ -f "$_update_script" ]; then
    bash "$_update_script"
    _urc=$?
    if [ "$_urc" -eq 2 ]; then
        exec bash "$0" "$@"
    fi
fi

CONNECT_VERSION='20260715.17'
CONNECT_PORT_BASE=20000

SERVER_IP="192.168.210.240"
ALIAS="claude-server"
CFG_DIR="$HOME/.config/claude-connect"
CFG="$CFG_DIR/connect.conf"
CM='$HOME/.local/bin/claude-mount'

die()       { echo ""; echo "  [X] $*"; echo ""; exit 1; }
warn()      { printf '  [!] %s\n' "$*"; if declare -F connect_log >/dev/null 2>&1; then connect_log "WARN: $*" 'WARN'; fi; }
step() {
    local s="    $*"
    CURRENT_STEP_NAME="$*"
    CURRENT_STEP_START=$SECONDS
    if declare -F connect_log >/dev/null 2>&1; then connect_log "STEP begin: $*"; fi
    printf '%s' "$s"
    local i; for ((i=${#s}; i<46; i++)); do printf '.'; done
}
step_ok()   {
    local ms=0 detail="${1:-ok}"
    [ -n "${CURRENT_STEP_START:-}" ] && ms=$(( SECONDS - CURRENT_STEP_START ))
    if declare -F connect_log >/dev/null 2>&1 && [ -n "${CURRENT_STEP_NAME:-}" ]; then
        connect_log "STEP end: $CURRENT_STEP_NAME ok ms=$ms detail=$detail"
    fi
    if [ -n "${1:-}" ]; then printf ' %s\n' "$*"; else printf ' ok\n'; fi
}
step_fail() {
    local ms=0 detail="${1:-failed}"
    [ -n "${CURRENT_STEP_START:-}" ] && ms=$(( SECONDS - CURRENT_STEP_START ))
    if declare -F connect_log >/dev/null 2>&1 && [ -n "${CURRENT_STEP_NAME:-}" ]; then
        connect_log "STEP end: $CURRENT_STEP_NAME failed ms=$ms detail=$detail" 'WARN'
    fi
    printf ' failed\n'; [ -n "${1:-}" ] && printf '      -> %s\n' "$*"
}

sshx() {
    local orig_cmd="$*" remote_cmd="$*" ec=0 ms=0 trunc_cmd out esc
    if ! printf '%s' "$remote_cmd" | grep -qE '^[[:space:]]*timeout[[:space:]]'; then
        esc="${remote_cmd//\'/\'\\\'\'}"
        remote_cmd="timeout 45 bash -lc '$esc'"
    fi
    if [ "${#orig_cmd}" -gt 200 ]; then trunc_cmd="${orig_cmd:0:200}..."; else trunc_cmd="$orig_cmd"; fi
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "SSH_BEGIN cmd=$trunc_cmd"
    fi
    local sw_start="$SECONDS"
    out="$(ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 \
        -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$ALIAS" "$remote_cmd" 2>&1)" || ec=$?
    ms=$(( (SECONDS - sw_start) * 1000 ))
    if [ "$ec" -eq 124 ]; then
        if declare -F connect_log >/dev/null 2>&1; then
            connect_log "SSH_TIMEOUT exit=124 cmd=$trunc_cmd - retrying once" 'ERROR'
        fi
        sw_start="$SECONDS"
        out="$(ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 \
            -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$ALIAS" "$remote_cmd" 2>&1)" || ec=$?
        ms=$(( (SECONDS - sw_start) * 1000 ))
    fi
    local trunc_out
    trunc_out="$(printf '%s' "$out" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -z "$trunc_out" ] && trunc_out='(empty)'
    [ "${#trunc_out}" -gt 300 ] && trunc_out="${trunc_out:0:300}..."
    if declare -F connect_log >/dev/null 2>&1; then
        connect_log "SSH_END exit=$ec ms=$ms out=$trunc_out"
    fi
    printf '%s' "$out"
    return "$ec"
}

_tunnel_alive() { kill -0 "$1" 2>/dev/null && ps -p "$1" -o state= 2>/dev/null | grep -qv 'Z'; }

# tunnel_up lives in git-mode.sh (port open + SSH banner must match this laptop OS)

# Mac-compatible port check (nc is available on macOS, timeout is not)
port_open() { nc -zw3 "$1" "$2" 2>/dev/null; }

# A: Prevent accidental sudo execution (breaks file ownership)
if [ "$(id -u)" -eq 0 ]; then
    die "Do not run with sudo. Run as your normal user: bash connect.sh"
fi

# B: Check that critical paths are writable before we touch them
check_writable() {
    local path="$1" label="$2"
    [ -e "$path" ] || return 0
    [ -w "$path" ] && return 0
    local owner
    owner="$(stat -f '%Su' "$path" 2>/dev/null || echo 'unknown')"
    die "$label is not writable (owned by $owner). Fix with:
      sudo chown -R $(whoami) \"$HOME/.ssh\" \"$CFG_DIR\""
}

mkdir -p "$CFG_DIR"

# B: Verify write access after directories exist
check_writable "$HOME/.ssh" ".ssh directory"
check_writable "$HOME/.ssh/config" "SSH config"
check_writable "$CFG_DIR" "config directory"
check_writable "$CFG" "connect config"

# config
if [ "${1:-}" = "--setup" ] || [ ! -f "$CFG" ]; then
    printf '  \033[0;36mFirst-time setup\033[0m\n\n'
    read -rp "    Server username: " REMOTE_USER
    printf 'REMOTE_USER=%s\nLAPTOP_USER=%s\n' "$REMOTE_USER" "$(whoami)" > "$CFG"
    echo ""
fi
. "$CFG"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECT_SCRIPT_DIR="$SCRIPT_DIR"
_GIT_MODE_SH="$SCRIPT_DIR/git-mode.sh"
[ -f "$_GIT_MODE_SH" ] || _GIT_MODE_SH="$SCRIPT_DIR/../git-mode.sh"
[ -f "$_GIT_MODE_SH" ] || _GIT_MODE_SH="$SCRIPT_DIR/../../git-mode.sh"
# shellcheck source=../git-mode.sh
[ -f "$_GIT_MODE_SH" ] || die "git-mode.sh not found - re-copy the full mac package"
. "$_GIT_MODE_SH"
export GIT_MODE_LAPTOP_OS=mac
laptop_ssh_prepare_dir

_UI_SH="$SCRIPT_DIR/connect-ui.sh"
[ -f "$_UI_SH" ] || _UI_SH="$SCRIPT_DIR/../connect-ui.sh"
[ -f "$_UI_SH" ] || die "connect-ui.sh not found - re-copy the full mac package"
# shellcheck source=../connect-ui.sh
. "$_UI_SH"

_EDITOR_SH="$SCRIPT_DIR/editor-launch.sh"
[ -f "$_EDITOR_SH" ] || _EDITOR_SH="$SCRIPT_DIR/../editor-launch.sh"
[ -f "$_EDITOR_SH" ] || die "editor-launch.sh not found - re-copy the full mac package"
# shellcheck source=../editor-launch.sh
. "$_EDITOR_SH"

clear
init_connect_log "$SCRIPT_DIR" "$CONNECT_VERSION"
ui_connect_header "$ALIAS" "$SERVER_IP" "$CONNECT_VERSION"
ui_bootstrap_hint "$CFG_DIR"
ui_set_title "Claude Connect"
echo ""

step "Laptop SSH Server"
if laptop_ssh_ready; then
    step_ok
    else
        step_fail "Remote Login is OFF - enabling..."
        if enable_remote_login || cycle_remote_login; then
            step_ok "enabled"
        else
            step_fail "could not enable Remote Login automatically"
            exit 1
        fi
    fi

step "Laptop SSH key"
[ -f "$HOME/.ssh/id_ed25519" ] || ssh-keygen -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519" -q
if [ -f "$HOME/.ssh/id_ed25519" ]; then
    chmod 600 "$HOME/.ssh/id_ed25519" 2>/dev/null || true
    step_ok
else
    step_fail "could not create key"; exit 1
fi

step "Server config"
touch "$HOME/.ssh/config"; chmod 600 "$HOME/.ssh/config"
awk -v a="$ALIAS" '
    /^[[:space:]]*Host[[:space:]]+/ { skip=0; for(i=2;i<=NF;i++) if($i==a) skip=1 }
    !skip
' "$HOME/.ssh/config" > "$HOME/.ssh/config.tmp.${ALIAS}" 2>/dev/null && mv "$HOME/.ssh/config.tmp.${ALIAS}" "$HOME/.ssh/config"
chmod 600 "$HOME/.ssh/config"
cat >> "$HOME/.ssh/config" <<EOF

Host $ALIAS
    HostName $SERVER_IP
    User $REMOTE_USER
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
EOF
sanitize_ssh_alias_config
step_ok "$REMOTE_USER"

# connect - retry until reachable, 5s between attempts
connected=""
needs_key=""
for attempt in $(seq 1 10); do
    printf '    \033[0;36mConnecting %d/10\033[0m' "$attempt"
    for ((i=18; i<46-12; i++)); do printf '.'; done
    sw_start=$SECONDS
    if ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=15 "$ALIAS" true 2>/dev/null; then
        printf ' \033[0;32m%s@%s\033[0m\n' "$REMOTE_USER" "$SERVER_IP"
        connected=1; break
    fi
    elapsed=$(( SECONDS - sw_start ))
    if port_open "$SERVER_IP" 22; then
        printf ' \033[0;33mauth failed (%ds) - no key, installing now\033[0m\n' "$elapsed"
        needs_key=1; break
    fi
    printf ' \033[0;90mno response (%ds)\033[0m\n' "$elapsed"
    if [ "$attempt" -lt 10 ]; then
        printf '    \033[0;90mWaiting 5s (VPN on? Server up?)...\033[0m\n'
        sleep 5
    fi
done

if [ -z "$connected" ] && [ -z "$needs_key" ]; then
    echo ""
    warn "Cannot reach $SERVER_IP after 10 attempts"
    warn "VPN connected? Server running?"
    echo ""; exit 1
fi

if [ -n "$needs_key" ]; then
    echo ""
    printf '    \033[0;33mEnter server password (one time only):\033[0m\n'
    if command -v ssh-copy-id >/dev/null 2>&1; then
        ssh-copy-id -o StrictHostKeyChecking=accept-new -i "$HOME/.ssh/id_ed25519.pub" "$REMOTE_USER@$SERVER_IP"
    else
        ssh -o StrictHostKeyChecking=accept-new "$REMOTE_USER@$SERVER_IP" \
            "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" \
            < "$HOME/.ssh/id_ed25519.pub"
    fi
    step "Verifying connection"
    if ! ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=15 "$ALIAS" true 2>/dev/null; then
        step_fail "still cannot connect"
        warn "Cannot connect - user=$REMOTE_USER  host=$SERVER_IP"
        echo ""
        printf '    \033[0;90mCurrent username: %s\033[0m\n' "$REMOTE_USER"
        read -rp "    Username changed? Enter new username (or Enter to exit): " fix
        if [ -n "$fix" ]; then
            printf 'REMOTE_USER=%s\nLAPTOP_USER=%s\n' "$fix" "$(whoami)" > "$CFG"
            awk -v a="$ALIAS" '
                /^[[:space:]]*Host[[:space:]]+/ { skip=0; for(i=2;i<=NF;i++) if($i==a) skip=1 }
                !skip
            ' "$HOME/.ssh/config" > "$HOME/.ssh/config.tmp.${ALIAS}" 2>/dev/null && mv "$HOME/.ssh/config.tmp.${ALIAS}" "$HOME/.ssh/config"
            chmod 600 "$HOME/.ssh/config"
            echo ""
            printf '    \033[0;32mSaved. Re-run connect.sh.\033[0m\n'
        fi
        echo ""; exit 1
    fi
    step_ok "$REMOTE_USER@$SERVER_IP"
fi

_script_dir="$(cd "$(dirname "$0")" && pwd)"
step "Server setup"
if ! initialize_server_session "$_script_dir"; then
    step_fail "could not configure server (port/key)"
    exit 1
fi
step_ok "port $PORT git=$(get_git_mode)"

ensure_laptop_ssh_key "$PUB_B" 2>/dev/null || true
LAPTOP_SSH_VERIFIED=0

echo ""
printf '    \033[0;32mReady\033[0m\n'
echo ""
ui_mark_bootstrap_done "$CFG_DIR"

# helpers (dot-source connect-ui.sh, git-mode.sh)
load_mounts() {
    sshx "$CM list 2>/dev/null" 2>/dev/null || true
}

show_mounts() {
    ACTIVE_MOUNT_ID="$(get_active_mount_id)"
    ui_git_mode_banner "$(get_git_mode)"
    ui_project_table "$1"
}

do_add() {
    _added_path=""
    _added_id=""
    echo ""
    printf '    \033[1;37mAdd project\033[0m\n\n'
    if _pick="$(ui_pick_folder 2>/dev/null)"; then
        new_rpath="$_pick"
        printf '    Selected: %s\n' "$new_rpath"
    else
        read -rp "    Folder on your laptop (e.g. /Users/ali/Smart): " new_rpath
    fi
    new_rpath="$(printf '%s' "$new_rpath" | tr '\\' '/')"
    [ -n "$new_rpath" ] || { warn "Path is required."; return 1; }
    local bn new_id new_lbl inp new_lpath out
    bn="$(basename "$new_rpath")"
    new_id="$(printf '%s' "$bn" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g;s/--*/-/g;s/^-//;s/-$//')"
    if [ -n "$new_id" ]; then
        new_lbl="$(printf '%s' "$new_id" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print}')"
    else
        new_lbl=""
    fi
    read -rp "    Name [$new_lbl]: " inp; [ -n "$inp" ] && new_lbl="$inp"
    [ -n "$new_id" ] || new_id="$(printf '%s' "$new_lbl" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g;s/--*/-/g;s/^-//;s/-$//')"
    [ -n "$new_id" ] || { warn "Could not derive a project name."; return 1; }
    if printf '%s\n' "$mounts_raw" | cut -d'|' -f1 | grep -qx "$new_id"; then
        warn "Project '$new_id' already exists. Enter a different name."; return 1
    fi
    # Strip single quotes to prevent remote shell breakage
    new_lbl="$(printf '%s' "$new_lbl" | tr "'" '-')"
    new_rpath="$(printf '%s' "$new_rpath" | tr "'" '-')"
    new_lpath="/home/$REMOTE_USER/mounts/$new_id"
    echo ""
    if ! out="$(sshx "$CM add '$new_id' '$new_lbl' '$new_rpath' '$new_lpath'" 2>&1)"; then
        warn "$out"; return 1
    fi
    _added_path="$new_lpath"
    _added_id="$new_id"
}

exit_requested=0

# menuLoop: project menu -> session -> post-disconnect (M/C/X) -> repeat or exit
while [ "$exit_requested" -eq 0 ]; do
    step "Loading projects"
    mounts_raw="$(load_mounts)"
    mounts_visible="$(filter_mounts_for_laptop "$mounts_raw")"
    hidden_count="$(count_skipped_mounts_for_laptop "$mounts_raw")"
    step_ok "$(mount_list_step_label "$mounts_raw")"

    go_path=""
    go_id=""

    while [ -z "$go_path" ] && [ "$exit_requested" -eq 0 ]; do
        if [ -z "$mounts_raw" ]; then
            do_add
            [ -n "$_added_path" ] || die "Could not add project."
            go_path="$_added_path"; go_id="$_added_id"
            break
        fi

        if [ -z "$mounts_visible" ] && [ "$hidden_count" -gt 0 ]; then
            if [ "${GIT_MODE_LAPTOP_OS:-mac}" = "mac" ]; then
                printf '    \033[0;90mNo Mac projects (%s Windows-only on server).\033[0m\n\n' "$hidden_count"
            else
                printf '    \033[0;90mNo PC projects (%s Mac-only on server).\033[0m\n\n' "$hidden_count"
            fi
        fi

        show_mounts "$mounts_visible"
        read -rp "    > " choice
        choice="$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        echo ""

        if [ -z "$choice" ]; then
            continue
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            row="$(printf '%s\n' "$mounts_visible" | sed -n "${choice}p")"
            if [ -z "$row" ]; then warn "Not found."; continue; fi
            IFS='|' read -r mid mlabel mrpath mlpath <<< "$row"
            if ! warn_invalid_project_rpath "$mrpath" "$choice"; then
                continue
            fi
            go_path="$mlpath"; go_id="$mid"
        else
            case "$choice" in
                a)
                    do_add
                    if [ -n "$_added_path" ]; then
                        go_path="$_added_path"; go_id="$_added_id"
                    else
                        mounts_raw="$(load_mounts)"
                        mounts_visible="$(filter_mounts_for_laptop "$mounts_raw")"
                        hidden_count="$(count_skipped_mounts_for_laptop "$mounts_raw")"
                    fi
                    ;;
                e)
                    read -rp "    Edit number: " en
                    row="$(printf '%s\n' "$mounts_visible" | sed -n "${en}p")"
                    if [ -z "$row" ]; then warn "Not found."; continue; fi
                    IFS='|' read -r cur_id cur_label cur_rpath cur_lpath <<< "$row"
                    echo ""
                    read -rp "    Display name [$cur_label]: " inp; new_label="${inp:-$cur_label}"
                    read -rp "    Laptop folder [$cur_rpath]: " inp; new_rpath="${inp:-$cur_rpath}"
                    printf '    Server path (read-only): %s\n' "$cur_lpath"
                    new_lpath="$cur_lpath"
                    new_label="$(printf '%s' "$new_label" | tr "'" '-')"
                    new_rpath="$(printf '%s' "$new_rpath" | tr "'" '-')"
                    new_lpath="$(printf '%s' "$new_lpath" | tr "'" '-')"
                    edit_out="$(sshx "$CM edit '$cur_id' '$new_label' '$new_rpath' '$new_lpath'" 2>&1)" || warn "$edit_out"
                    mounts_raw="$(load_mounts)"
                    mounts_visible="$(filter_mounts_for_laptop "$mounts_raw")"
                    hidden_count="$(count_skipped_mounts_for_laptop "$mounts_raw")"
                    ;;
                d)
                    read -rp "    Delete number: " dn
                    row="$(printf '%s\n' "$mounts_visible" | sed -n "${dn}p")"
                    if [ -z "$row" ]; then warn "Not found."; continue; fi
                    IFS='|' read -r del_id del_label _ _ <<< "$row"
                    read -rp "    Delete '$del_label'? [y/N]: " confirm
                    confirm="$(printf '%s' "$confirm" | tr '[:upper:]' '[:lower:]')"
                    if [ "$confirm" = "y" ]; then
                        rm_out="$(sshx "$CM rm '$del_id'" 2>&1)" || warn "$rm_out"
                    fi
                    mounts_raw="$(load_mounts)"
                    mounts_visible="$(filter_mounts_for_laptop "$mounts_raw")"
                    hidden_count="$(count_skipped_mounts_for_laptop "$mounts_raw")"
                    ;;
                c)
                    echo ""
                    printf '    \033[1;37mConfiguration\033[0m\n\n'
                    printf '    \033[0;90mUsername : %s\033[0m\n' "$REMOTE_USER"
                    printf '    \033[0;90mGit mode : %s\033[0m\n' "$(ui_git_mode_label "$(get_git_mode)")"
                    printf '    \033[0;90mIDE      : %s\033[0m\n' "$(get_editor_pref "$CFG_DIR")"
                    echo ""
                    printf '    \033[0;90m1  Change server username\033[0m\n'
                    printf '    \033[0;90m2  Change IDE preference\033[0m\n'
                    printf '    \033[0;90m3  Change git mode\033[0m\n\n'
                    read -rp '    > ' cfg_choice
                    case "$cfg_choice" in
                        1)
                            read -rp "    New server username (Enter to cancel): " new_user
                            if [ -n "$new_user" ] && [ "$new_user" != "$REMOTE_USER" ]; then
                                printf 'REMOTE_USER=%s\nLAPTOP_USER=%s\n' "$new_user" "$(whoami)" > "$CFG"
                                awk -v a="$ALIAS" '
                                    /^[[:space:]]*Host[[:space:]]+/ { skip=0; for(i=2;i<=NF;i++) if($i==a) skip=1 }
                                    !skip
                                ' "$HOME/.ssh/config" > "$HOME/.ssh/config.tmp.${ALIAS}" 2>/dev/null && mv "$HOME/.ssh/config.tmp.${ALIAS}" "$HOME/.ssh/config"
                                chmod 600 "$HOME/.ssh/config"
                                echo ""
                                printf '    \033[0;32mSaved. Re-run connect.sh.\033[0m\n'
                                echo ""; exit 0
                            fi
                            ;;
                        2) configure_editor_pref "$CFG_DIR" ;;
                        3) configure_git_mode ;;
                        *) printf '    \033[0;90mCancelled.\033[0m\n\n' ;;
                    esac
                    ;;
                g) configure_git_mode ;;
                q) exit_requested=1; break ;;
                *) warn "Enter a number or a/e/d/c/g/q." ;;
            esac
        fi
    done

    [ "$exit_requested" -eq 1 ] && break
    [ -z "$go_path" ] && continue

    if ! resolve_editor_choice "$CFG_DIR"; then
        warn "No editor found. Install Cursor or VS Code (+ Remote-SSH extension), then re-run."
        echo ""; exit 1
    fi

    _editor_opened=0
    RECOVERY_GENERATION=0
    POST_TUNNEL_RECOVERY=0
    SESSION_LOOP_ITER=0
    CURSOR_AUTH_NEEDS_BOOTSTRAP=0
    main_continue=1

    while [ "$main_continue" -eq 1 ]; do
        already_down=0
        bg_pid=""

        cleanup_session() {
            if [ "$already_down" -eq 0 ]; then
                already_down=1
                printf '\n    Disconnecting...\n'
                clear_session_mount "$go_id" "$EDITOR_CMD" "$ALIAS" "$go_path"
                printf '    Laptop folder restored.\n'
            fi
            stop_session_tunnel_cleanup 1
        }
        trap cleanup_session EXIT
        trap 'cleanup_session; exit 143' SIGTERM
        trap 'cleanup_session; exit 129' SIGHUP

        session_done=0
        while [ "$session_done" -eq 0 ]; do
            already_down=0
            SESSION_LOOP_ITER=$(( SESSION_LOOP_ITER + 1 ))
            if declare -F connect_log >/dev/null 2>&1; then
                connect_log "SESSION_LOOP begin iter=$SESSION_LOOP_ITER recovery_gen=${RECOVERY_GENERATION:-0} post_recovery=${POST_TUNNEL_RECOVERY:-0} force_auth=${CURSOR_AUTH_FORCE:-0}"
            fi

            step "Checking SSH service"
            if laptop_ssh_ready; then
                step_ok
            else
                step_fail "sshd not running - enabling..."
                if enable_remote_login; then
                    step_ok "enabled"
                else
                    printf '    Could not enable Remote Login. Go to: System Settings -> Sharing -> Remote Login\n'
                    session_done=1
                    break
                fi
            fi

            if ! ensure_session_tunnel; then
                step "Starting SSH tunnel"
                step_fail "did not come up"
                echo ""
                warn "Tunnel did not come up on port $PORT"
                if ! port_open "$SERVER_IP" 22; then
                    warn "Server unreachable - VPN disconnected?"
                else
                    warn "Check Mac firewall - SSH must allow inbound connections"
                fi
                echo ""
                printf '    R = retry   Q = quit\n'
                _rk=""
                while [ "$_rk" != "r" ] && [ "$_rk" != "q" ]; do
                    read -r -t 30 -n 1 _rk </dev/tty 2>/dev/null || read -r -t 5 -n 1 _rk 2>/dev/null || { _rk="q"; break; }
                    _rk="$(printf '%s' "$_rk" | tr '[:upper:]' '[:lower:]')"
                done
                [ "$_rk" = "r" ] && { echo ""; continue; }
                ACTIVE_MOUNT_ID=""
                push_server_connect_conf
                [ -n "$bg_pid" ] && kill "$bg_pid" 2>/dev/null || true
                already_down=1
                session_done=1
                break
            fi
            if [ "${TUNNEL_REUSED:-0}" = "1" ]; then
                step "SSH tunnel"
                step_ok "reusing pid $bg_pid"
            fi

            _mount_src="$(find_claude_mount_src "$SCRIPT_DIR" 2>/dev/null || true)"
            prepare_server_session_parallel "$go_id" "$_mount_src"

            recover_mounts_if_needed "$go_id" "$(( TUNNEL_REUSED ^ 1 ))"

            if ! _tunnel_alive "$bg_pid"; then
                printf '      -> tunnel dropped during recover, restarting...\n'
                LAPTOP_SSH_VERIFIED=0
                continue
            fi

            step "Verifying laptop SSH key"
            _laptop_ssh_rc=0
            ensure_laptop_reverse_ssh_cached "$PUB_B" || _laptop_ssh_rc=$?
            if [ "$_laptop_ssh_rc" -eq 0 ]; then
                step_ok
            elif [ "$_laptop_ssh_rc" -eq 1 ]; then
                step_fail "tunnel auth failed, retrying..."
                LAPTOP_SSH_VERIFIED=0
                echo ""
                continue
            else
                step_fail "server cannot authenticate to this Mac"
                echo ""
                printf '    R = retry   Q = quit\n'
                _rk=""
                while [ "$_rk" != "r" ] && [ "$_rk" != "q" ]; do
                    read -r -t 30 -n 1 _rk </dev/tty 2>/dev/null || read -r -t 5 -n 1 _rk 2>/dev/null || { _rk="q"; break; }
                    _rk="$(printf '%s' "$_rk" | tr '[:upper:]' '[:lower:]')"
                done
                [ "$_rk" = "r" ] && { echo ""; continue; }
                ACTIVE_MOUNT_ID=""
                push_server_connect_conf
                kill "$bg_pid" 2>/dev/null || true
                already_down=1
                session_done=1
                break
            fi

            step "Mounting files"
            mount_start=$SECONDS
            mount_out="$(invoke_mount_project "$go_id" "$SCRIPT_DIR")"
            mount_exit=$?
            mount_t=$(( SECONDS - mount_start ))
            mount_ok=0
            if [ $mount_exit -eq 0 ] && ! echo "$mount_out" | grep -q 'error:\|FAILED\|No tunnel\|not configured'; then
                mount_ok=1
            fi

            if [ $mount_ok -eq 0 ] && echo "$mount_out" | grep -qi 'key auth failed\|connection reset\|reset by peer\|publickey\|Permission denied'; then
                printf ' retrying...\n'
                if echo "$mount_out" | grep -qi 'connection reset\|reset by peer'; then
                    warn "Connection reset - killing stale mounts, fixing firewall, restarting sshd"
                    sshx 'pkill -u "$USER" sshfs 2>/dev/null; true' 2>/dev/null || true
                    invoke_laptop_admin_ops "" 1 || true
                else
                    warn "Key rejected - reinstalling server key"
                fi
                if ensure_laptop_reverse_ssh "$PUB_B"; then
                    if ! _tunnel_alive "$bg_pid"; then
                        printf '      -> tunnel dropped after sshd restart, restarting...\n'
                        continue
                    fi
                    step "Mounting files"
                    mount_start=$SECONDS
                    mount_out="$(invoke_mount_project "$go_id" "$SCRIPT_DIR")"
                    mount_exit=$?
                    mount_t=$(( SECONDS - mount_start ))
                    if [ $mount_exit -eq 0 ] && ! echo "$mount_out" | grep -q 'error:\|FAILED\|No tunnel\|not configured'; then
                        mount_ok=1
                    fi
                fi
            fi

            if [ $mount_ok -eq 0 ]; then
                step_fail "$mount_out"
                if declare -F complete_post_tunnel_recovery >/dev/null 2>&1; then
                    complete_post_tunnel_recovery 0 'mount_failed'
                fi
                if echo "$mount_out" | grep -qi "path not found\|no such file"; then
                    warn "Fix the project path: press e then edit the project"
                elif echo "$mount_out" | grep -qi "not running\|refused"; then
                    warn "Enable SSH: System Settings -> Sharing -> Remote Login"
                elif echo "$mount_out" | grep -qi "key auth failed\|publickey\|rejected the key"; then
                    warn "Retrying Remote Login self-heal..."
                    ensure_laptop_ssh_key "$PUB_B" || true
                fi
                echo ""
                printf '    R = retry   Q = quit\n'
                _rk=""
                while [ "$_rk" != "r" ] && [ "$_rk" != "q" ]; do
                    read -r -t 30 -n 1 _rk </dev/tty 2>/dev/null || read -r -t 5 -n 1 _rk 2>/dev/null || { _rk="q"; break; }
                    _rk="$(printf '%s' "$_rk" | tr '[:upper:]' '[:lower:]')"
                done
                [ "$_rk" = "r" ] && { echo ""; continue; }
                ACTIVE_MOUNT_ID=""
                push_server_connect_conf
                kill "$bg_pid" 2>/dev/null || true
                already_down=1
                session_done=1
                break
            fi

            step_ok "${mount_t}s"
            show_mount_git_warn "$mount_out"
            clean_out="$(printf '%s' "$mount_out" | sed 's/^already mounted: //')"
            if [ -n "$clean_out" ] && ! echo "$clean_out" | grep -q '^warn:'; then
                printf '      -> \033[0;90m%s\033[0m\n' "$clean_out"
            fi
            ACTIVE_PROJECT_ID="$go_id"
            CURSOR_AUTH_NEEDS_BOOTSTRAP=0
            _last_auth_detail='n/a'
            if [ "$EDITOR_CMD" = "cursor" ] && declare -F ensure_mac_cursor_prerequisites >/dev/null 2>&1; then
                ensure_mac_cursor_prerequisites || true
            fi

            if [ "$EDITOR_CMD" = "cursor" ] && declare -F sync_cursor_golden_auth_status >/dev/null 2>&1; then
                _cursor_gs="$(get_cursor_remote_profile_dir)/User/globalStorage/state.vscdb"
                _auth_needs_refresh=0
                if declare -F cursor_auth_needs_refresh >/dev/null 2>&1; then
                    cursor_auth_needs_refresh "$_cursor_gs" && _auth_needs_refresh=1
                fi
                if declare -F test_personal_cursor_dominant >/dev/null 2>&1 && test_personal_cursor_dominant; then
                    warn 'Personal Cursor is open - close it or use [Claude Server] profile windows'
                    declare -F connect_log >/dev/null 2>&1 && connect_log 'AUTH_WARN personal_cursor_dominant' 'WARN'
                fi
                _skip_auth=0
                if [ "${CURSOR_AUTH_FORCE:-0}" != "1" ] && [ "${POST_TUNNEL_RECOVERY:-0}" != "1" ] && [ "$_auth_needs_refresh" -eq 0 ]; then
                    if [ "$_editor_opened" -eq 1 ] && [ -f "$_cursor_gs" ] && local_cursor_auth_complete "$_cursor_gs"; then
                        _skip_auth=1
                    fi
                fi
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log "AUTH_DECISION skip=$_skip_auth force=${CURSOR_AUTH_FORCE:-0} post_recovery=${POST_TUNNEL_RECOVERY:-0} editor_opened=$_editor_opened needs_refresh=$_auth_needs_refresh"
                fi
                if [ "$_skip_auth" -eq 0 ]; then
                    step "Syncing Cursor auth"
                    sync_cursor_golden_auth_status
                    case "$CURSOR_AUTH_SYNC_RESULT" in
                        ok) step_ok; _last_auth_detail='ok'; date -u +%Y-%m-%dT%H:%M:%SZ > "$CFG_DIR/cursor-auth.ok" 2>/dev/null || true ;;
                        tokens_only)
                            step_ok "tokens only"
                            _last_auth_detail='tokens only'
                            warn 'Partial auth on laptop - reconnect; server auth is managed on server only'
                            ;;
                        skipped) step_ok "skipped"; _last_auth_detail='skipped' ;;
                        *) step_fail "could not merge server auth"
                            _last_auth_detail='merge failed'
                            warn 'Server auth OK - laptop could not save locally (sqlite3 required or reconnect)' ;;
                    esac
                    repair_cursor_composer_workspace_bindings "$ALIAS" "$go_path" || true
                elif [ "$_editor_opened" -eq 1 ]; then
                    step "Syncing Cursor auth"
                    step_ok "skipped (editor open)"
                    _last_auth_detail='skipped editor open'
                fi
            fi

            if [ "${POST_TUNNEL_RECOVERY:-0}" = "1" ]; then
                warn 'Recovery complete - press O if Cursor is not on the project folder'
                declare -F connect_log >/dev/null 2>&1 && connect_log 'RECOVERY: user_warn press_o_if_cursor_not_on_folder'
            fi

            _on_folder=0
            _did_launch=0
            if [ "$_editor_opened" -eq 1 ] && declare -F remote_editor_on_correct_folder >/dev/null 2>&1; then
                remote_editor_on_correct_folder "$EDITOR_CMD" "$ALIAS" "$go_path" && _on_folder=1
            fi

            if [ "$_editor_opened" -eq 0 ]; then
                step "Opening $EDITOR_NAME"
                if declare -F launch_remote_editor >/dev/null 2>&1; then
                    if launch_remote_editor "$EDITOR_CMD" "$ALIAS" "$go_path" "$_on_folder"; then
                        step_ok "$go_path"
                        _did_launch=1
                        if [ "$EDITOR_CMD" = "cursor" ]; then
                            printf '      -> \033[0;90mServer profile [Claude Server] - personal Cursor is separate\033[0m\n'
                            printf '      -> \033[0;90mAgent history: clock icon in sidebar (not empty new tab)\033[0m\n'
                        else
                            printf '      -> \033[0;90mServer profile [Claude Server Code] - personal VS Code is separate\033[0m\n'
                        fi
                    else
                        step_fail "$EDITOR_NAME not found (install Cursor or VS Code + Remote-SSH)"
                    fi
                elif command -v "$EDITOR_CMD" >/dev/null 2>&1; then
                    launch_remote_editor "$EDITOR_CMD" "$ALIAS" "$go_path" 0 || true
                    step_ok "$go_path"
                    _did_launch=1
                else
                    step_fail "$EDITOR_NAME not found (install Cursor or VS Code + Remote-SSH)"
                fi
                echo ""
                printf "    \033[0;90mRun 'claude' in the %s terminal.\033[0m\n" "$EDITOR_NAME"
            fi

            if declare -F remote_editor_on_correct_folder >/dev/null 2>&1; then
                if remote_editor_on_correct_folder "$EDITOR_CMD" "$ALIAS" "$go_path"; then
                    _editor_opened=1
                elif [ "$_did_launch" -eq 1 ] || remote_editor_window_open "$EDITOR_CMD" "$ALIAS" "$go_path"; then
                    warn 'Cursor is on Agent/home - reopening project folder...'
                    declare -F connect_log >/dev/null 2>&1 && connect_log 'SESSION: cursor not on target folder - relaunching' 'WARN'
                    launch_remote_editor "$EDITOR_CMD" "$ALIAS" "$go_path" 0 || true
                    sleep 1
                    remote_editor_on_correct_folder "$EDITOR_CMD" "$ALIAS" "$go_path" && _editor_opened=1
                else
                    _editor_opened=0
                fi
            elif [ "$_did_launch" -eq 1 ]; then
                _editor_opened=1
            fi

            if declare -F complete_post_tunnel_recovery >/dev/null 2>&1; then
                complete_post_tunnel_recovery 1 "$_last_auth_detail"
            fi
            _session_extras=()
            if [ "$EDITOR_CMD" = "cursor" ]; then
                _session_extras+=('Before Q: File > Exit Cursor so Agent chat history saves')
                case "${_last_auth_detail:-}" in
                    ok|tokens_only)
                        _session_extras+=('Chat: Developer -> Reload Window if messages fail')
                        ;;
                esac
            else
                _session_extras+=('Before Q: File > Exit VS Code to save unsaved work')
            fi
            if [ "${#_session_extras[@]}" -gt 0 ]; then
                ui_session_box "${_session_extras[@]}"
            else
                ui_session_box
            fi
            ui_set_title "Claude Connect | $go_id | $(ui_git_mode_label "$(get_git_mode)")"

            while read -r -t 0 </dev/tty 2>/dev/null; do read -r -n 1 </dev/tty 2>/dev/null || true; done

            _action="q"
            _got_key=0
            _status_at=0
            while _tunnel_alive "$bg_pid"; do
                if declare -F sync_session_tunnel_forward >/dev/null 2>&1; then
                    sync_session_tunnel_forward "$bg_pid" || break
                fi
                if [ "$_editor_opened" -eq 1 ] && declare -F remote_editor_running >/dev/null 2>&1; then
                    if remote_editor_running "$EDITOR_CMD" "$ALIAS" "$go_path"; then
                        _editor_opened=1
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
                    _key_lower="$(printf '%s' "$_key" | tr '[:upper:]' '[:lower:]')"
                    [ -z "$_key_lower" ] && _key_lower="q"
                    [ "$_key_lower" = "r" ] && _action="r"
                    [ "$_key_lower" = "g" ] && _action="g"
                    [ "$_key_lower" = "o" ] && _action="o"
                    _got_key=1; break
                fi
            done
            if [ "$_got_key" -eq 0 ] && ! _tunnel_alive "$bg_pid"; then
                ui_show_toast "Tunnel dropped - reconnecting..."
                tunnel_drop_session_action
            fi

            if [ "$_action" = "g" ]; then
                configure_git_mode
                continue
            fi

            if [ "$_action" = "o" ]; then
                if [ "$_editor_opened" -eq 0 ]; then
                    echo ""
                    step "Reopening $EDITOR_NAME"
                    if command -v "$EDITOR_CMD" >/dev/null 2>&1; then
                        launch_remote_editor "$EDITOR_CMD" "$ALIAS" "$go_path"
                        step_ok "$go_path"
                        _editor_opened=1
                    else
                        step_fail "$EDITOR_NAME not found"
                    fi
                    echo ""
                fi
                continue
            fi

            if [ "$_action" = "r" ]; then
                if [ "$_got_key" -eq 1 ]; then
                    if declare -F begin_connect_recovery >/dev/null 2>&1; then
                        begin_connect_recovery manual "$go_id" "$_editor_opened"
                    fi
                    _editor_opened=0
                    LAPTOP_SSH_VERIFIED=0
                    already_down=0
                    echo ""
                    printf '    Reconnecting...\n'
                    echo ""
                    continue
                fi
                if declare -F begin_connect_recovery >/dev/null 2>&1; then
                    begin_connect_recovery auto "$go_id" "$_editor_opened"
                fi
                _editor_opened=0
                export CURSOR_AUTH_FORCE=1
                printf '    Connection dropped - recovering...\n'
                if declare -F connect_log >/dev/null 2>&1; then
                    connect_log 'TUNNEL: recovering session (down mount, restart tunnel)' 'WARN'
                fi
                clear_session_mount "$go_id" "" "$ALIAS" "$go_path" 1
                stop_session_tunnel_cleanup 1
                already_down=1
                LAPTOP_SSH_VERIFIED=0
                echo ""
                continue
            fi

            printf '    Disconnecting...\n'
            clear_session_mount "$go_id" "$EDITOR_CMD" "$ALIAS" "$go_path"
            stop_session_tunnel_cleanup 1
            already_down=1
            printf '    Laptop folder restored.\n'

            session_done=1
        done

        stop_session_tunnel_cleanup 1

        trap - EXIT SIGTERM SIGHUP

        while read -r -t 0 </dev/tty 2>/dev/null; do read -r -n 1 </dev/tty 2>/dev/null || true; done

        _post="$(read_post_disconnect_key m 10)"
        case "$_post" in
            m)
                printf '    Back to project menu...\n'
                _editor_opened=0
                main_continue=0
                sleep 1
                echo ""
                ;;
            c)
                printf '    Reconnecting...\n'
                _editor_opened=0
                sleep 1
                echo ""
                ;;
            *)
                printf '    Exiting...\n'
                exit_requested=1
                main_continue=0
                ;;
        esac
    done
done

echo ""





