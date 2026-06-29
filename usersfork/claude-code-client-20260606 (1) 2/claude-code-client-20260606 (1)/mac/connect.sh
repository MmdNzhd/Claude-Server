#!/bin/bash
# connect.sh - Claude Code launcher for Mac/Linux.
# Usage:  bash connect.sh          (normal)
#         bash connect.sh --setup  (reconfigure)

set -uo pipefail

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

sshx() { ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 "$ALIAS" "$@"; }

# Short timeout version for tunnel check
tunnel_up() {
    sshx "timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$PORT' 2>/dev/null && echo UP" 2>/dev/null | grep -q UP
}

# Mac-compatible port check (nc is available on macOS, timeout is not)
port_open() { nc -zw3 "$1" "$2" 2>/dev/null; }

# macOS starts sshd on demand via launchd; pgrep/systemsetup -get alone are unreliable.
remote_login_on() {
    nc -zw1 127.0.0.1 22 2>/dev/null && return 0
    launchctl print system/com.openssh.sshd 2>/dev/null | grep -q 'service name = ssh' && return 0
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
    printf '%s\n' "$out" | grep -qi 'On' && return 0
    remote_login_on
}

check_writable() {
    local path="$1" label="$2"
    [ -e "$path" ] || return 0
    [ -w "$path" ] && return 0
    local owner
    owner="$(stat -f '%Su' "$path" 2>/dev/null || echo 'unknown')"
    die "$label is not writable (owned by $owner).

    Fix with:
      sudo chown -R $(whoami) \"$HOME/.ssh\" \"$CFG_DIR\""
}

if [ "$(id -u)" -eq 0 ]; then
    die "Do not run with sudo. Use: bash mac/connect.sh"
fi

mkdir -p "$CFG_DIR" "$HOME/.ssh"
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

# connect — retry until reachable, 5s between attempts
connected=""
needs_key=""
for attempt in $(seq 1 10); do
    printf '    \033[0;36mConnecting %d/10\033[0m' "$attempt"
    for ((i=18; i<46-12; i++)); do printf '.'; done
    sw_start=$SECONDS
    if ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=5 "$ALIAS" true 2>/dev/null; then
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
    if ! ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" true 2>/dev/null; then
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
            ' "$HOME/.ssh/config" > "$HOME/.ssh/config.tmp" 2>/dev/null && mv "$HOME/.ssh/config.tmp" "$HOME/.ssh/config"
            chmod 600 "$HOME/.ssh/config"
            echo ""
            printf '    \033[0;32mSaved. Re-run connect.sh.\033[0m\n'
        fi
        echo ""; exit 1
    fi
    step_ok "$REMOTE_USER@$SERVER_IP"
fi

step "Tunnel port"
_uid="$(sshx "id -u" 2>/dev/null | tr -dc '0-9')"
PORT=$(( 20000 + ${_uid:-0} ))
if [ "$PORT" -le 20000 ]; then step_fail "could not get UID from server"; exit 1; fi
step_ok "port $PORT"

step "Server key"
sshx "test -f ~/.ssh/claude_laptop || ssh-keygen -t ed25519 -N '' -f ~/.ssh/claude_laptop -q" 2>/dev/null || true
PUB_B="$(sshx "cat ~/.ssh/claude_laptop.pub")"
if [ -z "$PUB_B" ]; then step_fail "could not read server key"; exit 1; fi
touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
grep -qxF "$PUB_B" "$HOME/.ssh/authorized_keys" || echo "$PUB_B" >> "$HOME/.ssh/authorized_keys"
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
sshx "printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\n' '${LAPTOP_USER}' '$PORT' > ~/.claude-connect.conf" 2>/dev/null || true
step_ok "laptop=$LAPTOP_USER port=$PORT"

# push server scripts (claude-mount + claude-git-setup) if available
SERVER_DIR="$(cd "$(dirname "$0")" && pwd)/../../server"
sshx "mkdir -p ~/.local/bin" 2>/dev/null || true

SRC="$SERVER_DIR/claude-mount.sh"
if [ -f "$SRC" ]; then
    scp -o BatchMode=yes -o ConnectTimeout=10 -q "$SRC" "$ALIAS:~/.local/bin/claude-mount" 2>/dev/null || true
    sshx "chmod +x ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=\$HOME/.local/bin:\$PATH\n' >> ~/.bashrc" 2>/dev/null || true
fi

GIT_SRC="$SERVER_DIR/claude-git-setup.sh"
if [ -f "$GIT_SRC" ]; then
    scp -o BatchMode=yes -o ConnectTimeout=10 -q "$GIT_SRC" "$ALIAS:~/.local/bin/claude-git-setup" 2>/dev/null || true
    sshx "chmod +x ~/.local/bin/claude-git-setup" 2>/dev/null || true
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
                    ' "$HOME/.ssh/config" > "$HOME/.ssh/config.tmp" 2>/dev/null && mv "$HOME/.ssh/config.tmp" "$HOME/.ssh/config"
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
    # Pick editor: Cursor or VS Code. Auto-use whichever is installed; ask if both.
    EDITOR_PREF="$CFG_DIR/editor.conf"
    have_cursor=""; have_code=""
    command -v cursor >/dev/null 2>&1 && have_cursor=1
    command -v code   >/dev/null 2>&1 && have_code=1

    EDITOR_CMD=""; EDITOR_NAME=""
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
        case "$saved" in cursor|code) ;; *) saved="cursor" ;; esac
        echo ""
        printf '    \033[1;37mOpen with\033[0m\n\n'
        printf '    \033[0;90m1  Cursor\033[0m\n'
        printf '    \033[0;90m2  VS Code\033[0m\n\n'
        printf '    \033[0;90m(Enter = %s)\033[0m\n' "$saved"
        read -r ed_choice
        case "$(printf '%s' "$ed_choice" | tr '[:upper:]' '[:lower:]')" in
            1|cursor|c) EDITOR_CMD="cursor"; EDITOR_NAME="Cursor" ;;
            2|code|vscode|v) EDITOR_CMD="code"; EDITOR_NAME="VS Code" ;;
            "") [ "$saved" = "code" ] && { EDITOR_CMD="code"; EDITOR_NAME="VS Code"; } || { EDITOR_CMD="cursor"; EDITOR_NAME="Cursor"; } ;;
            *) EDITOR_CMD="cursor"; EDITOR_NAME="Cursor" ;;
        esac
        printf '%s' "$EDITOR_CMD" > "$EDITOR_PREF" 2>/dev/null || true
        echo ""
    fi

    already_down=""
    bg_pid=""
    tunnel_msg=""

    cleanup_session() {
        if [ -n "${go_id:-}" ] && [ "$already_down" != "1" ]; then
            echo ""
            printf '    \033[0;90mDisconnecting...\033[0m\n'
            sshx "$CM down '$go_id'" 2>/dev/null || true
            printf '    \033[0;32m.git restored on Mac.\033[0m\n'
            already_down=1
        fi
        if [ -n "${bg_pid:-}" ] && kill -0 "$bg_pid" 2>/dev/null; then
            kill "$bg_pid" 2>/dev/null || true
            wait "$bg_pid" 2>/dev/null || true
        fi
        bg_pid=""
    }
    trap cleanup_session EXIT

    try_mount() {
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
            warn "Key rejected - reinstalling server key"
            new_pub="$(sshx "cat ~/.ssh/claude_laptop.pub" 2>/dev/null)"
            if [ -n "$new_pub" ]; then
                touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
                grep -qxF "$new_pub" "$HOME/.ssh/authorized_keys" || echo "$new_pub" >> "$HOME/.ssh/authorized_keys"
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
    }

    prompt_retry() {
        echo ""
        printf '    \033[0;90mR = retry   Q = quit\033[0m\n'
        read -r -n 1 rk </dev/tty 2>/dev/null || read -r -n 1 rk
        echo ""
        case "$(printf '%s' "$rk" | tr '[:upper:]' '[:lower:]')" in
            r) return 0 ;;
            *) exit 1 ;;
        esac
    }

    while true; do
        if [ -n "$bg_pid" ] && kill -0 "$bg_pid" 2>/dev/null; then
            kill "$bg_pid" 2>/dev/null || true
            wait "$bg_pid" 2>/dev/null || true
            bg_pid=""
        fi
        pkill -f "ssh.*-R ${PORT}:localhost:22" 2>/dev/null || true

        step "Checking SSH service"
        if laptop_ssh_ready; then
            step_ok
        else
            step_fail "Remote Login is OFF"
            printf '    Enabling Remote Login...\n'
            if enable_remote_login; then
                step_ok "enabled"
            else
                step_fail "could not enable Remote Login"
                warn "Go to: System Settings -> Sharing -> Remote Login"
                prompt_retry
                continue
            fi
        fi

        step "Starting SSH tunnel"
        ssh -N -o ExitOnForwardFailure=no -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
            -R "$PORT:localhost:22" "$ALIAS" 2>/dev/null &
        bg_pid=$!
        step_ok "pid $bg_pid"

        up=""
        tunnel_msg=""
        for i in $(seq 1 8); do
            sleep 2
            printf '    Tunnel check %d/8...' "$i"
            if ! kill -0 "$bg_pid" 2>/dev/null; then
                tunnel_msg="SSH process exited"
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
            if [ -n "$tunnel_msg" ]; then
                warn "$tunnel_msg"
            elif ! port_open "$SERVER_IP" 22; then
                warn "Server unreachable - VPN disconnected?"
            else
                warn "Check Mac firewall - SSH must allow inbound connections"
            fi
            prompt_retry
            continue
        fi

        sshx "$CM recover" 2>/dev/null || true

        step "Mounting files"
        try_mount

        if [ $mount_ok -eq 0 ]; then
            step_fail "$mount_out"
            if echo "$mount_out" | grep -qi "path not found\|no such file"; then
                warn "Fix the project path: press e then edit the project"
            elif echo "$mount_out" | grep -qi "not running\|refused"; then
                warn "Enable SSH: System Settings -> Sharing -> Remote Login"
            fi
            prompt_retry
            continue
        fi

        step_ok "${mount_t}s"
        clean_out="$(printf '%s' "$mount_out" | sed 's/^already mounted: //')"
        [ -n "$clean_out" ] && printf '      -> \033[0;90m%s\033[0m\n' "$clean_out"

        step "Opening $EDITOR_NAME"
        "$EDITOR_CMD" --folder-uri "vscode-remote://ssh-remote+$ALIAS$go_path"
        step_ok "$go_path"

        echo ""
        printf "    \033[0;90mRun 'claude' in the %s terminal.\033[0m\n" "$EDITOR_NAME"
        echo ""
        printf '    \033[0;90m============================================\033[0m\n'
        printf '    \033[0;36mSession active -- keep this window open\033[0m\n'
        printf '    \033[0;90mR = reconnect   Q or Enter = disconnect\033[0m\n'
        printf '    \033[0;90m============================================\033[0m\n'
        echo ""

        action="q"
        got_key=""
        while kill -0 "$bg_pid" 2>/dev/null; do
            if read -r -t 1 -n 1 key </dev/tty 2>/dev/null || read -r -t 1 -n 1 key; then
                key="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
                if [ "$key" = "r" ]; then action="r"; fi
                got_key=1
                break
            fi
        done
        if [ -z "$got_key" ] && ! kill -0 "$bg_pid" 2>/dev/null; then
            action="r"
            printf '    \033[0;33mConnection dropped - reconnecting...\033[0m\n'
        fi

        cleanup_session

        if [ "$action" != "r" ]; then
            break
        fi

        already_down=""
        echo ""
        printf '    \033[0;36mReconnecting in 2s...\033[0m\n'
        sleep 2
        echo ""
    done

    trap - EXIT
fi
echo ""
