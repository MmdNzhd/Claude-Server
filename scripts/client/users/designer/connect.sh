#!/bin/bash
# connect.sh - Designer Connect launcher for Mac/Linux.
# Usage:  bash connect.sh          (normal)
#         bash connect.sh --setup  (reconfigure laptop path)

set -uo pipefail

SERVER_IP="192.168.210.240"
ALIAS="claude-server"
REMOTE_USER="designer"
CFG_DIR="$HOME/.config/claude-connect-designer"
CFG="$CFG_DIR/connect.conf"
CM='$HOME/.local/bin/claude-mount'
NOVNC_PORT=27015
MOUNT_ID="laptop"


# Minimal day-log (designer has no connect-ui.sh). Greppable FAIL for multi-agent diagnosis.
_designer_log() {
    local msg="$1" level="${2:-INFO}"
    local day="$HOME/.config/claude-connect/logs"
    local f="$day/connect-$(date +%Y%m%d).log"
    local sid="${CLAUDE_CONNECT_RUN_ID:--}"
    local ts
    mkdir -p "$day" 2>/dev/null || true
    ts="$(python3 -c 'import time; t=time.time(); print(time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)) + ".%03d" % int((t%1)*1000))' 2>/dev/null || date '+%Y-%m-%d %H:%M:%S.000')"
    printf '[%s] [%s] [%s] %s\n' "$ts" "$level" "$sid" "$msg" >> "$f" 2>/dev/null || true
}

die() {
    _designer_log "ERROR: $*" ERROR
    _designer_log "FAIL DIE: $*" ERROR
    echo ""; echo "  [X] $*"; echo ""; exit 1
}
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

tunnel_up() {
    sshx "timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$PORT' 2>/dev/null && echo UP" 2>/dev/null | grep -q UP
}

port_open()  { nc -zw3 "$1" "$2" 2>/dev/null; }
novnc_open() { nc -zw2 127.0.0.1 "$NOVNC_PORT" 2>/dev/null; }


# Share Global Connect lock with main connect (one UI per machine).
enter_connect_single_instance() {
    local lockdir="${HOME}/.config/claude-connect"
    local lockfile="${lockdir}/connect.lock"
    mkdir -p "$lockdir" 2>/dev/null || true
    exec 9>"$lockfile" || return 1
    if ! flock -n 9; then
        _designer_log "SINGLE_INSTANCE: blocked pid=$$" ERROR
        printf '\n  [X] Another Claude Connect is already running.\n\n' >&2
        return 1
    fi
    CONNECT_LOCK_HELD=1
    _designer_log "SINGLE_INSTANCE: acquired pid=$$" INFO
    return 0
}
exit_connect_single_instance() {
    if [ "${CONNECT_LOCK_HELD:-0}" = 1 ]; then
        flock -u 9 2>/dev/null || true
        exec 9>&- 2>/dev/null || true
        CONNECT_LOCK_HELD=0
    fi
}
if [ "$(id -u)" -eq 0 ]; then
    die "Do not run with sudo. Run as your normal user: bash connect.sh"
fi

if ! enter_connect_single_instance; then
    exit 1
fi

check_writable() {
    local path="$1" label="$2"
    [ -e "$path" ] || return 0
    [ -w "$path" ] && return 0
    local owner
    owner="$(stat -f '%Su' "$path" 2>/dev/null || echo 'unknown')"
    die "$label is not writable (owned by $owner). Fix with:
      sudo chown -R $(whoami) \"$HOME/.ssh\" \"$CFG_DIR\""
}

# Three-layer macOS SSH detection (pgrep -x sshd unreliable with on-demand launchd)
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

check_writable "$HOME/.ssh" ".ssh directory"
check_writable "$HOME/.ssh/config" "SSH config"
check_writable "$CFG_DIR" "config directory"
check_writable "$CFG" "connect config"

clear
echo ""
printf '    \033[1;37mDesigner Connect\033[0m\n'
printf '    \033[0;90m%s  |  %s\033[0m\n' "$ALIAS" "$SERVER_IP"
echo ""

if [ "${1:-}" = "--setup" ] || [ ! -f "$CFG" ]; then
    printf '  \033[0;36mFirst-time setup\033[0m\n\n'
    read -rp "    Folder on your laptop to share (e.g. /Users/sara/designs): " LAPTOP_PATH
    LAPTOP_PATH="$(printf '%s' "$LAPTOP_PATH" | tr '\\' '/')"
    [ -n "$LAPTOP_PATH" ] || die "Laptop path is required."
    printf "LAPTOP_USER=%s\nLAPTOP_PATH='%s'\n" "$(whoami)" "$(printf '%s' "$LAPTOP_PATH" | sed "s/'/'\\\\''/g")" > "$CFG"
    echo ""
fi
. "$CFG"
[ -n "${LAPTOP_USER:-}" ] || die "Config missing LAPTOP_USER. Re-run with --setup to reconfigure."
[ -n "${LAPTOP_PATH:-}" ] || die "Config missing LAPTOP_PATH. Re-run with --setup to reconfigure."

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
' "$HOME/.ssh/config" > "$HOME/.ssh/config.tmp" 2>/dev/null && mv "$HOME/.ssh/config.tmp" "$HOME/.ssh/config"
chmod 600 "$HOME/.ssh/config"
cat >> "$HOME/.ssh/config" <<EOF

Host $ALIAS
    HostName $SERVER_IP
    User $REMOTE_USER
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
EOF
step_ok "$REMOTE_USER"

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
    printf '    \033[0;33mEnter designer password (one time only):\033[0m\n'
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
        echo ""; exit 1
    fi
    step_ok "$REMOTE_USER@$SERVER_IP"
fi

step "Tunnel port + server key"
_init="$(sshx "id -u && (test -f ~/.ssh/claude_laptop || ssh-keygen -t ed25519 -N '' -f ~/.ssh/claude_laptop -q) && cat ~/.ssh/claude_laptop.pub" 2>/dev/null)"
_uid="$(printf '%s\n' "$_init" | tr -d '\r' | grep -E '^[0-9]+$' | head -1 | tr -dc '0-9')"
PUB_B="$(printf '%s\n' "$_init" | tr -d '\r' | grep '^ssh-' | head -1)"
PORT=$(( 20000 + ${_uid:-0} ))
if [ "$PORT" -le 20000 ];   then step_fail "could not get UID from server"; exit 1; fi
if [ "$PORT" -gt 65535 ];   then step_fail "server UID too large (port $PORT > 65535)"; exit 1; fi
if [ -z "$PUB_B" ];         then step_fail "could not read server key"; exit 1; fi
step_ok "port $PORT"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_GIT_MODE_SH="$SCRIPT_DIR/git-mode.sh"
[ -f "$_GIT_MODE_SH" ] || _GIT_MODE_SH="$SCRIPT_DIR/../git-mode.sh"
[ -f "$_GIT_MODE_SH" ] || _GIT_MODE_SH="$SCRIPT_DIR/../../git-mode.sh"
# shellcheck source=../git-mode.sh
[ -f "$_GIT_MODE_SH" ] || die "git-mode.sh not found - re-copy the full designer package"
. "$_GIT_MODE_SH"

# Operator: one Connect UI per PC. Win designer shares connect-ui mutex; close main connect before Mac designer.

step "Server key"
touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
grep -vF "$PUB_B" "$HOME/.ssh/authorized_keys" > "$HOME/.ssh/authorized_keys.tmp" 2>/dev/null && mv "$HOME/.ssh/authorized_keys.tmp" "$HOME/.ssh/authorized_keys" || true
echo "from=\"127.0.0.1,::1\" $PUB_B" >> "$HOME/.ssh/authorized_keys"
step_ok

step "Configuring server"
awk -v a="$ALIAS" '
    /^[[:space:]]*Host[[:space:]]+/ { skip=0; for(i=2;i<=NF;i++) if($i==a) skip=1 }
    !skip
' "$HOME/.ssh/config" > "$HOME/.ssh/config.tmp" 2>/dev/null && mv "$HOME/.ssh/config.tmp" "$HOME/.ssh/config"
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
push_server_connect_conf
step_ok "laptop=$LAPTOP_USER port=$PORT git=$(get_git_mode)"

server_dir="$(resolve_server_script_dir "$SCRIPT_DIR" 2>/dev/null || true)"
SRC=""
GIT_SRC=""
if [ -n "$server_dir" ]; then
    [ -f "$server_dir/claude-mount.sh" ] && SRC="$server_dir/claude-mount.sh"
    [ -f "$server_dir/claude-git-setup.sh" ] && GIT_SRC="$server_dir/claude-git-setup.sh"
fi
if [ -n "$SRC" ] || [ -n "$GIT_SRC" ]; then
    sshx "mkdir -p ~/.local/bin" 2>/dev/null || true
    [ -f "$SRC" ] && scp -o BatchMode=yes -o ConnectTimeout=30 -q "$SRC" "$ALIAS:~/.local/bin/claude-mount" 2>/dev/null || true
    [ -f "$GIT_SRC" ] && scp -o BatchMode=yes -o ConnectTimeout=30 -q "$GIT_SRC" "$ALIAS:~/.local/bin/claude-git-setup" 2>/dev/null || true
    _chmod=""
    [ -f "$SRC" ] && _chmod="chmod +x ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=\$HOME/.local/bin:\$PATH\n' >> ~/.bashrc"
    [ -f "$GIT_SRC" ] && _chmod="${_chmod:+"$_chmod; "}chmod +x ~/.local/bin/claude-git-setup"
    [ -n "$_chmod" ] && sshx "$_chmod" 2>/dev/null || true
fi

echo ""
printf '    \033[0;32mReady\033[0m\n'
echo ""

MOUNT_LPATH="/home/$REMOTE_USER/mounts/$MOUNT_ID"
existing="$(sshx "$CM list 2>/dev/null" 2>/dev/null | grep -E "^${MOUNT_ID}\\|" || true)"
clean_path="$(printf '%s' "$LAPTOP_PATH" | tr "'" '-')"
if [ -z "$existing" ]; then
    step "Configuring laptop mount"
    sshx "$CM add '$MOUNT_ID' 'Laptop' '$clean_path' '$MOUNT_LPATH'" 2>/dev/null || true
    step_ok "$MOUNT_LPATH"
elif [ "${1:-}" = "--setup" ]; then
    step "Updating laptop mount path"
    sshx "$CM edit '$MOUNT_ID' 'Laptop' '$clean_path' '$MOUNT_LPATH'" 2>/dev/null || true
    step_ok "$clean_path"
else
    step "Laptop mount"
    step_ok "already configured"
fi

# Session lifecycle: already_down prevents double-cleanup in EXIT/SIGTERM traps
already_down=0
bg_pid=""
_novnc_opened=0

cleanup_session() {
    [ "$already_down" -eq 1 ] && return 0
    already_down=1
    printf '\n    Disconnecting...\n'
    timeout 8 ssh -n -o BatchMode=yes -o ConnectTimeout=5 "$ALIAS" "$CM down '$MOUNT_ID'" 2>/dev/null || true
    ACTIVE_MOUNT_ID=""
    push_server_connect_conf --clear
    [ -n "$bg_pid" ] && kill "$bg_pid" 2>/dev/null || true
}
trap cleanup_session EXIT
trap 'cleanup_session; exit 143' SIGTERM
trap 'cleanup_session; exit 129' SIGHUP

while true; do
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
            already_down=1; break
        fi
    fi

    step "Starting SSH tunnel"
    ssh -N \
        -o ExitOnForwardFailure=no \
        -o ServerAliveInterval=20 \
        -o ServerAliveCountMax=5 \
        -R "$PORT:localhost:22" \
        -L "127.0.0.1:${NOVNC_PORT}:127.0.0.1:${NOVNC_PORT}" \
        "$ALIAS" 2>/dev/null &
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
            _k=""
            read -r -t 30 -n 1 _k </dev/tty 2>/dev/null || read -r -t 5 -n 1 _k 2>/dev/null || { _rk="q"; break; }
            _k="$(printf '%s' "$_k" | tr '[:upper:]' '[:lower:]')"
            case "$_k" in
                r) _rk="r" ;;
                q) _rk="q" ;;
                *)
                    _ord="$(printf '%s' "$_k" | od -An -tuC | tr -s ' ' | awk '{print $1; exit}')"
                    if [ -n "$_ord" ] && [ "$_ord" -gt 127 ]; then
                        continue
                    fi
                    ;;
            esac
        done
        [ "$_rk" = "r" ] && { echo ""; continue; }
        ACTIVE_MOUNT_ID=""
        push_server_connect_conf --clear
        kill "$bg_pid" 2>/dev/null || true
        already_down=1; break
    fi

    sshx "$CM recover" 2>/dev/null || true
    if ! _git_mode_tunnel_ok; then
        warn "Tunnel dropped during recover - reconnecting..."
        continue
    fi

    ACTIVE_MOUNT_ID="$MOUNT_ID"
    push_server_connect_conf

    step "Mounting files"
    mount_start=$SECONDS
    mount_out="$(sshx "$CM up '$MOUNT_ID' 2>&1")"
    mount_exit=$?
    mount_t=$(( SECONDS - mount_start ))
    mount_ok=0
    if [ $mount_exit -eq 0 ] && ! echo "$mount_out" | grep -q 'error:\|FAILED\|No tunnel\|not configured'; then
        mount_ok=1
    fi
    show_mount_git_warn "$mount_out"

    # Auto-fix: connection reset or key rejected -> fix and retry once
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
            echo "from=\"127.0.0.1,::1\" $new_pub" >> "$HOME/.ssh/authorized_keys"
            step "Mounting files"
            mount_start=$SECONDS
            mount_out="$(sshx "$CM up '$MOUNT_ID' 2>&1")"
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
            warn "Fix the laptop path: re-run with --setup"
        elif echo "$mount_out" | grep -qi "not running\|refused"; then
            warn "Enable SSH: System Settings -> Sharing -> Remote Login"
        fi
        echo ""
        printf '    R = retry   Q = quit\n'
        _rk=""
        while [ "$_rk" != "r" ] && [ "$_rk" != "q" ]; do
            _k=""
            read -r -t 30 -n 1 _k </dev/tty 2>/dev/null || read -r -t 5 -n 1 _k 2>/dev/null || { _rk="q"; break; }
            _k="$(printf '%s' "$_k" | tr '[:upper:]' '[:lower:]')"
            case "$_k" in
                r) _rk="r" ;;
                q) _rk="q" ;;
                *)
                    _ord="$(printf '%s' "$_k" | od -An -tuC | tr -s ' ' | awk '{print $1; exit}')"
                    if [ -n "$_ord" ] && [ "$_ord" -gt 127 ]; then
                        continue
                    fi
                    ;;
            esac
        done
        [ "$_rk" = "r" ] && { echo ""; continue; }
        ACTIVE_MOUNT_ID=""
        push_server_connect_conf --clear
        kill "$bg_pid" 2>/dev/null || true
        already_down=1; break
    fi

    step_ok "${mount_t}s"
    ACTIVE_PROJECT_ID="$MOUNT_ID"
    clean_out="$(printf '%s' "$mount_out" | sed 's/^already mounted: //')"
    if [ -n "$clean_out" ] && ! echo "$clean_out" | grep -q '^warn:'; then
        printf '      -> \033[0;90m%s\033[0m\n' "$clean_out"
    fi

    if [ "$_novnc_opened" -eq 0 ]; then
        step "Opening noVNC"
        if novnc_open; then
            open "http://localhost:${NOVNC_PORT}/vnc.html" 2>/dev/null || true
            step_ok "http://localhost:${NOVNC_PORT}/vnc.html"
            _novnc_opened=1
        else
            step_fail "noVNC port ${NOVNC_PORT} not reachable on localhost"
            warn "VNC stack may not be running. Ask admin: ssh smart@$SERVER_IP sudo designer-start start"
            warn "Fallback (LAN only): http://${SERVER_IP}:${NOVNC_PORT}/vnc.html"
        fi
    fi

    echo ""
    printf '    ============================================\n'
    printf '    Session active -- keep this window open\n'
    printf '    Files mounted at: %s\n' "$MOUNT_LPATH"
    printf '    G = git mode   R = reconnect   Q or Enter = disconnect\n'
    printf '    ============================================\n'
    echo ""

    # Flush buffered keypresses before entering wait loop
    while read -r -t 0 </dev/tty 2>/dev/null; do read -r -n 1 </dev/tty 2>/dev/null || true; done

    _action=""
    _got_key=0
    while _tunnel_alive "$bg_pid"; do
        if read -r -t 1 -n 1 _key </dev/tty 2>/dev/null; then
            _key_lower="$(printf '%s' "$_key" | tr '[:upper:]' '[:lower:]')"
            _resolved=""
            case "$_key_lower" in
                r) _resolved="r" ;;
                g) _resolved="g" ;;
                q|$'\n'|$'\r') _resolved="q" ;;
            esac
            if [ -z "$_resolved" ]; then
                # Non-ASCII printable KeyChar (e.g. Arabic/Persian letter on Q under FA layout): ignore and keep waiting.
                _ord="$(printf '%s' "$_key" | od -An -tuC | tr -s ' ' | awk '{print $1; exit}')"
                if [ -n "$_ord" ] && [ "$_ord" -gt 127 ]; then
                    continue
                fi
                continue
            fi
            _action="$_resolved"
            _got_key=1; break
        fi
    done
    if [ "$_got_key" -eq 0 ] && ! _tunnel_alive "$bg_pid"; then
        tunnel_drop_session_action
    fi
    [ -z "${_action:-}" ] && continue

    if [ "$_action" = "g" ]; then
        configure_git_mode
        continue
    fi

    echo ""
    printf '    Disconnecting...\n'
    ssh -n -o BatchMode=yes -o ConnectTimeout=5 "$ALIAS" "$CM down '$MOUNT_ID'" 2>/dev/null || true
    ACTIVE_MOUNT_ID=""
    push_server_connect_conf --clear
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

# Post-disconnect menu (ASCII commands only; ignore non-ASCII layout glyphs).
echo ""
printf '    \033[0;36mDisconnected. What would you like to do?\033[0m\n'
printf '    \033[0;90mC = connect again   X = exit\033[0m\n'
echo ""
_post=""
while [ "$_post" != "c" ] && [ "$_post" != "x" ]; do
    _k=""
    if read -r -t 1 -n 1 _k </dev/tty 2>/dev/null; then
        _k="$(printf '%s' "$_k" | tr '[:upper:]' '[:lower:]')"
        case "$_k" in
            c)
                printf '    Reconnecting...\n'
                sleep 1
                echo ""
                exec bash "$0" "$@"
                ;;
            x)
                printf '    Exiting...\n'
                _post="x"
                ;;
            *)
                _ord="$(printf '%s' "$_k" | od -An -tuC | tr -s ' ' | awk '{print $1; exit}')"
                if [ -n "$_ord" ] && [ "$_ord" -gt 127 ]; then
                    continue
                fi
                ;;
        esac
    fi
done
echo ""
