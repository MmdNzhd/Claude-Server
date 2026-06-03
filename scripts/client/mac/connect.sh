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

die()       { echo ""; echo "  [X] $*"; exit 1; }
warn()      { printf '  [!] %s\n' "$*"; }
step() {
    local s="    $*"
    printf '%s' "$s"
    local i; for ((i=${#s}; i<46; i++)); do printf '.'; done
}
step_ok()   { if [ -n "${1:-}" ]; then printf ' %s\n' "$*"; else printf ' ok\n'; fi; }
step_fail() { printf ' failed\n'; [ -n "${1:-}" ] && printf '      -> %s\n' "$*"; }

sshx() { ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 "$ALIAS" "$@"; }
tunnel_up() { timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$PORT" 2>/dev/null; }

mkdir -p "$CFG_DIR" "$HOME/.ssh"

# header
clear
echo ""
printf '    \033[1;37mClaude Code\033[0m\n'
printf '    \033[0;90m%s  |  %s\033[0m\n' "$ALIAS" "$SERVER_IP"
echo ""

# config
SETUP=""
if [ "${1:-}" = "--setup" ] || [ ! -f "$CFG" ]; then
    SETUP=1
    printf '  \033[0;36mFirst-time setup\033[0m\n\n'
    read -rp "    Server username: " REMOTE_USER
    printf 'REMOTE_USER=%s\nLAPTOP_USER=%s\n' "$REMOTE_USER" "$(whoami)" > "$CFG"
    echo ""
fi
. "$CFG"

step "Laptop SSH Server"
if ! pgrep -x sshd >/dev/null 2>&1; then
    step_fail "Remote Login is OFF - enabling..."
    sudo systemsetup -setremotelogin on 2>/dev/null \
      || { step_fail "could not enable. Go to: System Settings -> Sharing -> Remote Login"; exit 1; }
    step_ok "enabled"
else
    step_ok
fi

step "Laptop SSH key"
[ -f "$HOME/.ssh/id_ed25519" ] || ssh-keygen -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519" -q
if [ -f "$HOME/.ssh/id_ed25519" ]; then step_ok; else step_fail "could not create key"; exit 1; fi

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

step "Connecting"
if ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=6 "$ALIAS" true 2>/dev/null; then
    step_ok "$REMOTE_USER@$SERVER_IP"
else
    if ! timeout 3 bash -c "exec 3<>/dev/tcp/$SERVER_IP/22" 2>/dev/null; then
        step_fail "cannot reach $SERVER_IP - VPN connected? Server running?"
        exit 1
    fi
    step_fail "auth failed - installing key"
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
        warn "Cannot connect to $ALIAS ($REMOTE_USER@$SERVER_IP)."
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

# push claude-mount if available
SRC="$(cd "$(dirname "$0")" && pwd)/../../server/claude-mount.sh"
if [ -f "$SRC" ]; then
    sshx "mkdir -p ~/.local/bin" 2>/dev/null || true
    scp -o BatchMode=yes -o ConnectTimeout=10 -q "$SRC" "$ALIAS:~/.local/bin/claude-mount" 2>/dev/null || true
    sshx "chmod +x ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=\$HOME/.local/bin:\$PATH\n' >> ~/.bashrc" 2>/dev/null || true
fi

echo ""
printf '    \033[0;32mReady\033[0m\n'
echo ""

# helpers
load_mounts() {
    sshx "$CM status 2>/dev/null" 2>/dev/null || true
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
    while IFS='|' read -r mid mlabel mpath mstatus; do
        [ -z "$mid" ] && continue
        if [ "$mstatus" = "MOUNTED" ]; then
            printf '    \033[1;37m%d  %s\033[0m  \033[0;32m(on)\033[0m\n' "$i" "$mlabel"
        else
            printf '    \033[0;90m%d  %s\033[0m\n' "$i" "$mlabel"
        fi
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

mounts_raw="$(load_mounts)"
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
        IFS='|' read -r mid mlabel mpath mstatus <<< "$row"
        go_path="$mpath"; go_id="$mid"
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
                IFS='|' read -r cur_id cur_label cur_path _ <<< "$row"
                cur_rpath="$(sshx "grep REMOTE_PATH ~/.claude-mounts.d/$cur_id.conf 2>/dev/null" 2>/dev/null | sed 's/REMOTE_PATH=//;s/"//g')"
                echo ""
                read -rp "    Name  [$cur_label]: " inp; new_label="${inp:-$cur_label}"
                read -rp "    Path  [$cur_rpath]: " inp; new_rpath="${inp:-$cur_rpath}"
                read -rp "    Local [$cur_path]: " inp; new_lpath="${inp:-$cur_path}"
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
    if ! command -v code >/dev/null 2>&1; then
        warn "VSCode not found. Install it + the Remote-SSH extension, then re-run."
        echo ""; exit 1
    fi

    pkill -f "ssh.*-R ${PORT}:localhost:22" 2>/dev/null || true

    step "Mounting files"
    ssh -fN -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
        -R "$PORT:localhost:22" "$ALIAS" 2>/dev/null &
    bg_tunnel_pid=$!

    up=""
    for _ in $(seq 1 6); do sleep 2; if tunnel_up; then up=1; break; fi; done
    if [ -z "$up" ]; then
        step_fail "could not reach laptop on port 22"
        printf '      -> Is SSH Server running? (System Settings -> Sharing -> Remote Login)\n'
        echo ""; exit 1
    fi

    mount_out="$(sshx "$CM up '$go_id' 2>&1")"
    mount_exit=$?
    if [ $mount_exit -ne 0 ] || echo "$mount_out" | grep -q 'FAILED\|No tunnel\|not configured'; then
        step_fail "$mount_out"
        printf '      -> Is SSH Server running on your laptop?\n'
        printf '      -> Is the project path correct? Use "e edit" to fix it.\n'
        echo ""
        printf '    Debug: on server run:\n'
        printf '      ssh -v -p %s -i ~/.ssh/claude_laptop %s@localhost "echo ok"\n' "$PORT" "$LAPTOP_USER"
        echo ""; exit 1
    fi

    kill "$bg_tunnel_pid" 2>/dev/null || true
    step_ok
    [ -n "$mount_out" ] && printf '    \033[0;90m%s\033[0m\n' "$mount_out"

    step "Opening VSCode"
    code --folder-uri "vscode-remote://ssh-remote+$ALIAS$go_path"
    step_ok "$go_path"

    echo ""
    printf "    \033[0;90mRun 'claude' in the VSCode terminal.\033[0m\n"
    sshx "($CM up >/dev/null 2>&1 &); true" 2>/dev/null || true
fi
echo ""
