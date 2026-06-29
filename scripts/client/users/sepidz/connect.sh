#!/bin/bash
# connect.sh - Claude Code launcher for Mac/Linux.
# Usage:  bash connect.sh          (normal)
#         bash connect.sh --setup  (reconfigure)

set -uo pipefail

SERVER_IP="192.168.250.70"
ALIAS="claude-server-sepidz"
CFG_DIR="$HOME/.config/claude-connect-sepidz"
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

# header
clear
echo ""
printf '    \033[1;37mClaude Code\033[0m\n'
printf '    \033[0;90m%s  |  %s\033[0m\n' "$ALIAS" "$SERVER_IP"
echo ""

# config
if [ "${1:-}" = "--setup" ] || [ ! -f "$CFG" ]; then
    printf '  \033[0;36mFirst-time setup\033[0m\n\n'
    read -rp "    Server username: " REMOTE_USER
    printf 'REMOTE_USER=%s\nLAPTOP_USER=%s\n' "$REMOTE_USER" "$(whoami)" > "$CFG"
    echo ""
fi
. "$CFG"

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
# Migration: remove stale "Host claude-server" block written by the old sepidz script
awk '/^[[:space:]]*Host[[:space:]]+/ { skip=0; for(i=2;i<=NF;i++) if($i=="claude-server") skip=1 } !skip' \
    "$HOME/.ssh/config" > "$HOME/.ssh/config.tmp.${ALIAS}" 2>/dev/null && mv "$HOME/.ssh/config.tmp.${ALIAS}" "$HOME/.ssh/config"
chmod 600 "$HOME/.ssh/config"
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

step "Tunnel port + server key"
_init="$(sshx "id -u && (test -f ~/.ssh/claude_laptop || ssh-keygen -t ed25519 -N '' -f ~/.ssh/claude_laptop -q) && cat ~/.ssh/claude_laptop.pub" 2>/dev/null)"
_uid="$(printf '%s\n' "$_init" | tr -d '\r' | grep -E '^[0-9]+$' | head -1 | tr -dc '0-9')"
PUB_B="$(printf '%s\n' "$_init" | tr -d '\r' | grep '^ssh-' | head -1)"
PORT=$(( 21000 + ${_uid:-0} ))
if [ "$PORT" -le 21000 ];   then step_fail "could not get UID from server"; exit 1; fi
if [ "$PORT" -gt 65535 ];   then step_fail "server UID too large (port $PORT > 65535)"; exit 1; fi
if [ -z "$PUB_B" ];        then step_fail "could not read server key";     exit 1; fi
step_ok "port $PORT"

step "Server key"
touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
# Remove any existing entry for this key (restricted or not), then re-add with from= restriction
grep -vF "$PUB_B" "$HOME/.ssh/authorized_keys" > "$HOME/.ssh/authorized_keys.tmp" 2>/dev/null && mv "$HOME/.ssh/authorized_keys.tmp" "$HOME/.ssh/authorized_keys" || true
chmod 600 "$HOME/.ssh/authorized_keys"
echo "from=\"127.0.0.1,::1\" $PUB_B" >> "$HOME/.ssh/authorized_keys"
step_ok

step "Configuring server"
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
    RemoteForward $PORT localhost:22
    ExitOnForwardFailure no
EOF
sshx "printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\n' '${LAPTOP_USER}' '$PORT' > ~/.claude-connect.conf && chmod 600 ~/.claude-connect.conf || true" 2>/dev/null || true
step_ok "laptop=$LAPTOP_USER port=$PORT"

# push claude-mount if available
SRC="$(cd "$(dirname "$0")" && pwd)/../../server/claude-mount.sh"
if [ -f "$SRC" ]; then
    sshx "mkdir -p ~/.local/bin" 2>/dev/null || true
    scp -o BatchMode=yes -o ConnectTimeout=30 -q "$SRC" "$ALIAS:~/.local/bin/claude-mount" 2>/dev/null || true
    sshx "chmod +x ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=\$HOME/.local/bin:\$PATH\n' >> ~/.bashrc" 2>/dev/null || true
fi

echo ""
printf '    \033[0;32mReady\033[0m\n'
echo ""

# helpers — use 'list' not 'status' (status is slow/hangs on stale mounts)
load_mounts() {
    sshx "$CM list 2>/dev/null" 2>/dev/null || true
}

show_mounts() {
    local raw="$1"
    printf '    \033[1;37mProjects\033[0m\n\n'
    if [ -z "$raw" ]; then
        printf '    \033[0;90m(no projects configured)\033[0m\n'
        echo ""
        printf '    \033[0;90ma add   e edit   d delete   c config   q quit\033[0m\n'
        echo ""
        return
    fi
    local i=1
    while IFS='|' read -r mid mlabel mrpath mlpath; do
        [ -z "$mid" ] && continue
        printf '    \033[0;90m%d  %s\033[0m\n' "$i" "$mlabel"
        i=$(( i + 1 ))
    done <<< "$raw"
    echo ""
    printf '    \033[0;90ma add   e edit   d delete   c config   q quit\033[0m\n'
    echo ""
}

do_add() {
    _added_path=""
    _added_id=""
    echo ""
    printf '    \033[1;37mAdd project\033[0m\n\n'
    read -rp "    Folder on your laptop (e.g. /Users/ali/Smart): " new_rpath
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

step "Loading projects"
mounts_raw="$(load_mounts)"
mount_count="$(printf '%s\n' "$mounts_raw" | grep -c '|' 2>/dev/null || echo 0)"
step_ok "$mount_count project(s)"

go_path=""
go_id=""

while [ -z "$go_path" ]; do
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
                read -rp "    Name  [$cur_label]: " inp; new_label="${inp:-$cur_label}"
                read -rp "    Path  [$cur_rpath]: " inp; new_rpath="${inp:-$cur_rpath}"
                read -rp "    Local [$cur_lpath]: " inp; new_lpath="${inp:-$cur_lpath}"
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
                printf '    \033[0;90mCurrent username: %s\033[0m\n' "$REMOTE_USER"
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
                else
                    printf '    \033[0;90mCancelled.\033[0m\n\n'
                fi
                ;;
            q) echo ""; exit 0 ;;
            *) warn "Enter a number or a/e/d/c/q." ;;
        esac
    fi
done

if [ -n "$go_path" ]; then
    # D: Editor detection — Cursor and/or VS Code, with saved preference
    EDITOR_PREF="$CFG_DIR/editor.conf"
    have_cursor=""; have_code=""
    command -v cursor >/dev/null 2>&1 && have_cursor=1
    command -v code   >/dev/null 2>&1 && have_code=1

    if [ -z "$have_cursor" ] && [ -z "$have_code" ]; then
        warn "No editor found. Install Cursor or VS Code (+ Remote-SSH extension), then re-run."
        echo ""; exit 1
    elif [ -n "$have_cursor" ] && [ -z "$have_code" ]; then
        EDITOR_CMD="cursor"; EDITOR_NAME="Cursor"
    elif [ -z "$have_cursor" ] && [ -n "$have_code" ]; then
        EDITOR_CMD="code"; EDITOR_NAME="VS Code"
    else
        saved=""
        [ -f "$EDITOR_PREF" ] && saved="$(cat "$EDITOR_PREF" 2>/dev/null)"
        case "$saved" in
            cursor|code) ;;
            *) [ -n "$saved" ] && warn "Saved editor preference '$saved' is invalid — resetting"
               saved="cursor" ;;
        esac
        echo ""
        printf '    \033[1;37mOpen with\033[0m\n\n'
        printf '    \033[0;90m1  Cursor\033[0m\n'
        printf '    \033[0;90m2  VS Code\033[0m\n\n'
        printf '    \033[0;90m(Enter = %s)\033[0m\n' "$saved"
        read -r ed_choice
        case "$(printf '%s' "$ed_choice" | tr '[:upper:]' '[:lower:]')" in
            1|cursor|c) EDITOR_CMD="cursor"; EDITOR_NAME="Cursor" ;;
            2|code|vscode|v) EDITOR_CMD="code"; EDITOR_NAME="VS Code" ;;
            "") [ "$saved" = "code" ] && { EDITOR_CMD="code"; EDITOR_NAME="VS Code"; } \
                                      || { EDITOR_CMD="cursor"; EDITOR_NAME="Cursor"; } ;;
            *) EDITOR_CMD="cursor"; EDITOR_NAME="Cursor" ;;
        esac
        printf '%s' "$EDITOR_CMD" > "$EDITOR_PREF" 2>/dev/null || true
    fi

    # E: Session lifecycle — cleanup on EXIT, auto-reconnect on tunnel drop
    already_down=0
    bg_pid=""
    _editor_opened=0

    cleanup_session() {
        [ "$already_down" -eq 1 ] && return 0
        already_down=1
        printf '\n    Disconnecting...\n'
        # timeout 8: bounds hang if remote claude-mount down gets stuck (ConnectTimeout=5 covers TCP only)
        timeout 8 ssh -n -o BatchMode=yes -o ConnectTimeout=5 "$ALIAS" "$CM down '$go_id'" 2>/dev/null || true
        [ -n "$bg_pid" ] && kill "$bg_pid" 2>/dev/null || true
    }
    trap cleanup_session EXIT
    trap 'cleanup_session; exit 143' SIGTERM

    while true; do
        # Kill any stale tunnel from previous iteration
        [ -n "$bg_pid" ] && kill "$bg_pid" 2>/dev/null || true
        bg_pid=""
        already_down=0

        pkill -f "ssh.*-R ${PORT}:localhost:22" 2>/dev/null || true
        # Free any stale server-side port binding from a previous crashed session.
        # fuser -k kills only the sshd child holding *:PORT — not the sshd master.
        # Guard with command -v: fuser is in psmisc and may not be installed everywhere.
        sshx "command -v fuser >/dev/null 2>&1 && fuser -k ${PORT}/tcp 2>/dev/null; true" 2>/dev/null || true

        step "Checking SSH service"
        if laptop_ssh_ready; then
            step_ok
        else
            step_fail "sshd not running - enabling..."
            if enable_remote_login; then
                step_ok "enabled"
            else
                printf '    Could not enable Remote Login. Go to: System Settings -> Sharing -> Remote Login\n'
                already_down=1; break
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
                # -t 5 on fallback: if no TTY at all, default to 'q' after timeout (avoids infinite spin)
                read -r -t 30 -n 1 _rk </dev/tty 2>/dev/null || read -r -t 5 -n 1 _rk 2>/dev/null || { _rk="q"; break; }
                _rk="$(printf '%s' "$_rk" | tr '[:upper:]' '[:lower:]')"
            done
            [ "$_rk" = "r" ] && { echo ""; continue; }
            kill "$bg_pid" 2>/dev/null || true
            already_down=1; break
        fi

        sshx "$CM recover" 2>/dev/null || true

        step "Mounting files"
        mount_start=$SECONDS
        mount_out="$(sshx "$CM up '$go_id' 2>&1")"
        mount_exit=$?
        mount_t=$(( SECONDS - mount_start ))
        mount_ok=0
        if [ $mount_exit -eq 0 ] && ! echo "$mount_out" | grep -q 'error:\|FAILED\|No tunnel\|not configured'; then
            mount_ok=1
        fi

        # Auto-fix: connection reset or key rejected -> fix and retry once
        if [ $mount_ok -eq 0 ] && echo "$mount_out" | grep -qi 'key auth failed\|connection reset\|reset by peer\|publickey\|Permission denied'; then
            printf ' retrying...\n'
            if echo "$mount_out" | grep -qi 'connection reset\|reset by peer'; then
                warn "Connection reset - killing stale mounts and restarting sshd"
                # Kill zombie sshfs processes on server — they flood MaxStartups and cause new connections to reset
                sshx 'pkill -u "$USER" sshfs 2>/dev/null; true' 2>/dev/null || true
                # Restart macOS sshd to clear MaxStartups counter and stale connection state
                sudo launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true
                # Wait for sshd to be ready (up to 10s)
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
                # -t 5 on fallback: if no TTY at all, default to 'q' after timeout (avoids infinite spin)
                read -r -t 30 -n 1 _rk </dev/tty 2>/dev/null || read -r -t 5 -n 1 _rk 2>/dev/null || { _rk="q"; break; }
                _rk="$(printf '%s' "$_rk" | tr '[:upper:]' '[:lower:]')"
            done
            [ "$_rk" = "r" ] && { echo ""; continue; }
            kill "$bg_pid" 2>/dev/null || true
            already_down=1; break
        fi

        step_ok "${mount_t}s"
        clean_out="$(printf '%s' "$mount_out" | sed 's/^already mounted: //')"
        [ -n "$clean_out" ] && printf '      -> \033[0;90m%s\033[0m\n' "$clean_out"

        if [ "$_editor_opened" -eq 0 ]; then
            step "Opening $EDITOR_NAME"
            if "$EDITOR_CMD" --folder-uri "vscode-remote://ssh-remote+$ALIAS$go_path"; then
                step_ok "$go_path"
                _editor_opened=1
            else
                _ec=$?
                step_fail "$EDITOR_NAME failed to launch (exit $_ec)"
            fi
            echo ""
            printf "    \033[0;90mRun 'claude' in the %s terminal.\033[0m\n" "$EDITOR_NAME"
        fi
        echo ""
        printf '    ============================================\n'
        printf '    Session active -- keep this window open\n'
        printf '    R = reconnect   Q or Enter = disconnect\n'
        printf '    ============================================\n'
        echo ""

        # Flush any buffered keypresses before entering the wait loop
        while read -r -t 0 </dev/tty 2>/dev/null; do read -r -n 1 </dev/tty 2>/dev/null || true; done

        # Wait for keypress or tunnel drop
        # kill -0 returns 0 for zombie processes (bash without job control doesn't auto-reap);
        # ps state check filters zombies so tunnel-drop auto-reconnect actually triggers.
        _tunnel_alive() { kill -0 "$1" 2>/dev/null && ps -p "$1" -o state= 2>/dev/null | grep -qv 'Z'; }

        _action="q"
        _got_key=0
        while _tunnel_alive "$bg_pid"; do
            if read -r -t 1 -n 1 _key </dev/tty 2>/dev/null; then
                _key_lower="$(printf '%s' "$_key" | tr '[:upper:]' '[:lower:]')"
                [ "$_key_lower" = "r" ] && _action="r"
                _got_key=1; break
            fi
        done
        if [ "$_got_key" -eq 0 ] && ! _tunnel_alive "$bg_pid"; then
            _action="r"
            printf '\n    Connection dropped - reconnecting...\n'
        fi

        # Explicit disconnect
        echo ""
        printf '    Disconnecting...\n'
        ssh -n -o BatchMode=yes -o ConnectTimeout=5 "$ALIAS" "$CM down '$go_id'" 2>/dev/null || true
        kill "$bg_pid" 2>/dev/null || true
        already_down=1

        [ "$_action" != "r" ] && break

        already_down=0
        echo ""
        printf '    Reconnecting in 2s...\n'
        sleep 2
        echo ""
    done

    trap - EXIT
fi
echo ""
