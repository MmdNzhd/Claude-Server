#!/bin/bash
# connect.sh - Claude Code launcher for Mac/Linux.
# Usage:  bash connect.sh          (normal)
#         bash connect.sh --setup  (reconfigure)

set -uo pipefail

CONNECT_VERSION='20260703.12'
CONNECT_PORT_BASE=20000

SERVER_IP="192.168.210.240"
ALIAS="claude-server"
CFG_DIR="$HOME/.config/claude-connect"
CFG="$CFG_DIR/connect.conf"
CM='$HOME/.local/bin/claude-mount'

die()       { echo ""; echo "  [X] $*"; echo ""; exit 1; }
warn()      { printf '  [!] %s\n' "$*"; }
step() {
    local s="    $*"
    printf '%s' "$s"
    local i; for ((i=${#s}; i<46; i++)); do printf '.'; done
}
step_ok()   { if [ -n "${1:-}" ]; then printf ' %s\n' "$*"; else printf ' ok\n'; fi; }
step_fail() { printf ' failed\n'; [ -n "${1:-}" ] && printf '      -> %s\n' "$*"; }

sshx() { ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 "$ALIAS" "$@"; }

_tunnel_alive() { kill -0 "$1" 2>/dev/null && ps -p "$1" -o state= 2>/dev/null | grep -qv 'Z'; }

# Short timeout version for tunnel check
tunnel_up() {
    sshx "timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$PORT' 2>/dev/null && echo UP" 2>/dev/null | grep -q UP
}

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

# C: Three-layer macOS SSH detection (nc -> launchctl -> systemsetup)
# pgrep -x sshd is unreliable on macOS with on-demand launchd SSH
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

enable_remote_login() {
    remote_login_on && return 0
    local out
    out="$(sudo systemsetup -setremotelogin on 2>&1)" || true
    printf '%s\n' "$out" | grep -qi 'On' || remote_login_on || return 1
    # Wait up to 10s for sshd to be accepting connections after enable
    local _i
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        nc -zw1 127.0.0.1 22 2>/dev/null && return 0
        sleep 1
    done
    return 1
}

mkdir -p "$CFG_DIR" "$HOME/.ssh"

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
_GIT_MODE_SH="$SCRIPT_DIR/git-mode.sh"
[ -f "$_GIT_MODE_SH" ] || _GIT_MODE_SH="$SCRIPT_DIR/../git-mode.sh"
[ -f "$_GIT_MODE_SH" ] || _GIT_MODE_SH="$SCRIPT_DIR/../../git-mode.sh"
# shellcheck source=../git-mode.sh
[ -f "$_GIT_MODE_SH" ] || die "git-mode.sh not found - re-copy the full mac package"
. "$_GIT_MODE_SH"

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
ui_connect_header "$ALIAS" "$SERVER_IP" "$CONNECT_VERSION"
ui_bootstrap_hint "$CFG_DIR"
ui_set_title "Claude Connect"
echo ""

step "Laptop SSH Server"
if laptop_ssh_ready; then
    step_ok
else
    step_fail "Remote Login is OFF - enabling..."
    if enable_remote_login; then
        step_ok "enabled"
    else
        step_fail "could not enable. Go to: System Settings -> Sharing -> Remote Login"
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
step_ok "$REMOTE_USER"

# connect — retry until reachable, 5s between attempts
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

echo ""
printf '    \033[0;32mReady\033[0m\n'
echo ""
ui_mark_bootstrap_done "$CFG_DIR"

# helpers — use 'list' not 'status' (status is slow/hangs on stale mounts)
load_mounts() {
    sshx "$CM list 2>/dev/null" 2>/dev/null || true
}

show_mounts() {
    ACTIVE_MOUNT_ID="$(get_active_mount_id)"
    ui_git_mode_banner "$(get_git_mode)"
    ui_project_table "$1" "$(get_last_project_id)"
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
    mount_count="$(printf '%s\n' "$mounts_raw" | grep -c '|' 2>/dev/null || echo 0)"
    step_ok "$mount_count project(s)"

    go_path=""
    go_id=""

    while [ -z "$go_path" ] && [ "$exit_requested" -eq 0 ]; do
        if [ -z "$mounts_raw" ]; then
            do_add
            [ -n "$_added_path" ] || die "Could not add project."
            go_path="$_added_path"; go_id="$_added_id"
            break
        fi

        show_mounts "$mounts_raw"
        read -rp "    > " choice
        choice="$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')"
        echo ""

        if [ -z "$choice" ]; then
            _last="$(get_last_project_id)"
            if [ -n "$_last" ]; then
                row="$(printf '%s\n' "$mounts_raw" | grep "^${_last}|" | head -1 || true)"
                if [ -n "$row" ]; then
                    IFS='|' read -r mid mlabel mrpath mlpath <<< "$row"
                    go_path="$mlpath"; go_id="$mid"
                    break
                fi
            fi
            continue
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            row="$(printf '%s\n' "$mounts_raw" | sed -n "${choice}p")"
            if [ -z "$row" ]; then warn "Not found."; continue; fi
            IFS='|' read -r mid mlabel mrpath mlpath <<< "$row"
            go_path="$mlpath"; go_id="$mid"
        else
            case "$choice" in
                a)
                    do_add
                    if [ -n "$_added_path" ]; then
                        go_path="$_added_path"; go_id="$_added_id"
                    else
                        mounts_raw="$(load_mounts)"
                    fi
                    ;;
                e)
                    read -rp "    Edit number: " en
                    row="$(printf '%s\n' "$mounts_raw" | sed -n "${en}p")"
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
                    ;;
                d)
                    read -rp "    Delete number: " dn
                    row="$(printf '%s\n' "$mounts_raw" | sed -n "${dn}p")"
                    if [ -z "$row" ]; then warn "Not found."; continue; fi
                    IFS='|' read -r del_id del_label _ _ <<< "$row"
                    read -rp "    Delete '$del_label'? [y/N]: " confirm
                    confirm="$(printf '%s' "$confirm" | tr '[:upper:]' '[:lower:]')"
                    if [ "$confirm" = "y" ]; then
                        rm_out="$(sshx "$CM rm '$del_id'" 2>&1)" || warn "$rm_out"
                    fi
                    mounts_raw="$(load_mounts)"
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
    CURSOR_AUTH_NEEDS_BOOTSTRAP=0
    main_continue=1

    while [ "$main_continue" -eq 1 ]; do
        already_down=0
        bg_pid=""

        cleanup_session() {
            [ "$already_down" -eq 1 ] && return 0
            already_down=1
            printf '\n    Disconnecting...\n'
            clear_session_mount "$go_id" "$EDITOR_CMD" "$ALIAS" "$go_path"
            printf '    Laptop folder restored.\n'
            [ -n "$bg_pid" ] && kill "$bg_pid" 2>/dev/null || true
        }
        trap cleanup_session EXIT
        trap 'cleanup_session; exit 143' SIGTERM
        trap 'cleanup_session; exit 129' SIGHUP

        session_done=0
        while [ "$session_done" -eq 0 ]; do
            [ -n "$bg_pid" ] && kill "$bg_pid" 2>/dev/null || true
            bg_pid=""
            already_down=0

            pkill -f "ssh.*-R ${PORT}:localhost:22" 2>/dev/null || true

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

            step "Starting SSH tunnel"
            ssh -N -o ExitOnForwardFailure=no -o ServerAliveInterval=20 -o ServerAliveCountMax=5 \
                -R "$PORT:localhost:22" "$ALIAS" 2>/dev/null &
            bg_pid=$!
            step_ok "pid $bg_pid"

            up=""
            for i in $(seq 1 8); do
                sleep 2
                printf '    Tunnel check %d/8...' "$i"
                if ! kill -0 "$bg_pid" 2>/dev/null; then
                    printf ' SSH process died\n'
                    break
                fi
                if tunnel_up; then
                    printf ' port %d is open\n' "$PORT"
                    up=1; break
                fi
                printf ' port %d not open yet\n' "$PORT"
            done

            if [ -z "$up" ]; then
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
                kill "$bg_pid" 2>/dev/null || true
                already_down=1
                session_done=1
                break
            fi

            printf '      -> single project mode: unmounting others...\n'
            ACTIVE_MOUNT_ID="$go_id"
            push_server_connect_conf
            unmount_other_projects "$go_id"

            sshx "$CM recover" 2>/dev/null || true

            if ! _tunnel_alive "$bg_pid"; then
                printf '      -> tunnel dropped during recover, restarting...\n'
                continue
            fi

            step "Mounting files"
            mount_start=$SECONDS
            mount_out="$(sshx "$CM up '$go_id' 2>&1")"
            mount_exit=$?
            mount_t=$(( SECONDS - mount_start ))
            mount_ok=0
            if [ $mount_exit -eq 0 ] && ! echo "$mount_out" | grep -q 'error:\|FAILED\|No tunnel\|not configured'; then
                mount_ok=1
            fi

            if [ $mount_ok -eq 0 ] && echo "$mount_out" | grep -qi 'key auth failed\|connection reset\|reset by peer\|publickey\|Permission denied'; then
                printf ' retrying...\n'
                if echo "$mount_out" | grep -qi 'connection reset\|reset by peer'; then
                    warn "Connection reset - killing stale mounts and restarting sshd"
                    sshx 'pkill -u "$USER" sshfs 2>/dev/null; true' 2>/dev/null || true
                    sudo launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true
                    for _i in 1 2 3 4 5 6 7 8 9 10; do
                        nc -zw1 127.0.0.1 22 2>/dev/null && break
                        sleep 1
                    done
                else
                    warn "Key rejected - reinstalling server key"
                fi
                new_pub="$(sshx "cat ~/.ssh/claude_laptop.pub" 2>/dev/null)"
                if [ -n "$new_pub" ]; then
                    touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
                    grep -vF "$new_pub" "$HOME/.ssh/authorized_keys" > "$HOME/.ssh/authorized_keys.tmp" 2>/dev/null && mv "$HOME/.ssh/authorized_keys.tmp" "$HOME/.ssh/authorized_keys" || true
                    chmod 600 "$HOME/.ssh/authorized_keys"
                    echo "from=\"127.0.0.1,::1\" $new_pub" >> "$HOME/.ssh/authorized_keys"
                    if ! _tunnel_alive "$bg_pid"; then
                        printf '      -> tunnel dropped after sshd restart, restarting...\n'
                        continue
                    fi
                    step "Mounting files"
                    mount_start=$SECONDS
                    mount_out="$(sshx "$CM up '$go_id' 2>&1")"
                    mount_exit=$?
                    mount_t=$(( SECONDS - mount_start ))
                    if [ $mount_exit -eq 0 ] && ! echo "$mount_out" | grep -q 'error:\|FAILED\|No tunnel\|not configured'; then
                        mount_ok=1
                    fi
                fi
            fi

            if [ $mount_ok -eq 0 ]; then
                step_fail "$mount_out"
                if echo "$mount_out" | grep -qi "path not found\|no such file"; then
                    warn "Fix the project path: press e then edit the project"
                elif echo "$mount_out" | grep -qi "not running\|refused"; then
                    warn "Enable SSH: System Settings -> Sharing -> Remote Login"
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
            save_last_project_id "$go_id"

            CURSOR_AUTH_NEEDS_BOOTSTRAP=0
            if [ "$EDITOR_CMD" = "cursor" ] && declare -F sync_cursor_golden_auth_status >/dev/null 2>&1; then
                step "Syncing Cursor auth"
                sync_cursor_golden_auth_status
                case "$CURSOR_AUTH_SYNC_RESULT" in
                    ok) step_ok; date -u +%Y-%m-%dT%H:%M:%SZ > "$CFG_DIR/cursor-auth.ok" 2>/dev/null || true ;;
                    tokens_only)
                        step_ok "tokens only"
                        CURSOR_AUTH_NEEDS_BOOTSTRAP=1
                        warn 'Chat needs server account profile - sign in inside [Claude Server] only, then press P'
                        ;;
                    skipped) step_ok "skipped" ;;
                    *) step_fail "could not merge server auth"; CURSOR_AUTH_NEEDS_BOOTSTRAP=1 ;;
                esac
            fi

            if [ "$_editor_opened" -eq 0 ]; then
                step "Opening $EDITOR_NAME"
                if [ "$EDITOR_CMD" = "cursor" ]; then
                    init_cursor_server_profile
                    _cursor_profile="$(get_cursor_remote_profile_dir)"
                    if "$EDITOR_CMD" --user-data-dir "$_cursor_profile" --folder-uri "vscode-remote://ssh-remote+$ALIAS$go_path"; then
                        step_ok "$go_path"
                        _editor_opened=1
                        printf '      -> \033[0;90mServer profile [Claude Server] - personal Cursor is separate\033[0m\n'
                    else
                        _ec=$?
                        step_fail "$EDITOR_NAME failed to launch (exit $_ec)"
                    fi
                elif "$EDITOR_CMD" --folder-uri "vscode-remote://ssh-remote+$ALIAS$go_path"; then
                    step_ok "$go_path"
                    _editor_opened=1
                else
                    _ec=$?
                    step_fail "$EDITOR_NAME failed to launch (exit $_ec)"
                fi
                echo ""
                printf "    \033[0;90mRun 'claude' in the %s terminal.\033[0m\n" "$EDITOR_NAME"
            fi
            _session_extras=()
            [ "$CURSOR_AUTH_NEEDS_BOOTSTRAP" -eq 1 ] && _session_extras+=('P = push server login to golden (after sign-in in [Claude Server] only)')
            ui_session_box "${_session_extras[@]}"
            ui_set_title "Claude Connect | $go_id | $(ui_git_mode_label "$(get_git_mode)")"

            while read -r -t 0 </dev/tty 2>/dev/null; do read -r -n 1 </dev/tty 2>/dev/null || true; done

            _action="q"
            _got_key=0
            while _tunnel_alive "$bg_pid"; do
                if read -r -t 1 -n 1 _key </dev/tty 2>/dev/null; then
                    _key_lower="$(printf '%s' "$_key" | tr '[:upper:]' '[:lower:]')"
                    [ -z "$_key_lower" ] && _key_lower="q"
                    [ "$_key_lower" = "r" ] && _action="r"
                    [ "$_key_lower" = "g" ] && _action="g"
                    [ "$_key_lower" = "p" ] && [ "$CURSOR_AUTH_NEEDS_BOOTSTRAP" -eq 1 ] && _action="p"
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

            if [ "$_action" = "p" ]; then
                echo ""
                printf '    \033[0;36mPushing golden from [Claude Server] profile...\033[0m\n'
                _pmsg="$(push_cursor_golden_from_server_profile)"
                if [ $? -eq 0 ]; then
                    printf '    \033[0;32m%s\033[0m\n' "$_pmsg"
                    CURSOR_AUTH_NEEDS_BOOTSTRAP=0
                else
                    printf '    \033[0;33m%s\033[0m\n' "$_pmsg"
                fi
                echo ""
                continue
            fi

            echo ""
            printf '    Disconnecting...\n'
            if [ "$_action" = "r" ] && [ "$_got_key" -eq 0 ]; then
                clear_session_mount "$go_id" "" "$ALIAS" "$go_path" 1
            else
                clear_session_mount "$go_id" "$EDITOR_CMD" "$ALIAS" "$go_path"
            fi
            kill "$bg_pid" 2>/dev/null || true
            already_down=1
            printf '    Laptop folder restored.\n'

            if [ "$_action" = "r" ]; then
                [ "$_got_key" -eq 1 ] && _editor_opened=0
                already_down=0
                echo ""
                printf '    Reconnecting in 2s...\n'
                sleep 2
                echo ""
                continue
            fi

            session_done=1
        done

        if [ -n "$bg_pid" ] && _tunnel_alive "$bg_pid"; then
            :
        elif [ -n "$bg_pid" ] && [ "$already_down" -eq 0 ]; then
            kill "$bg_pid" 2>/dev/null || true
        fi

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
