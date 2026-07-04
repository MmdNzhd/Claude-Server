# Designer Connect Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create Mac (`connect.sh`) and Windows (`connect.ps1`) scripts for the `designer` user that SSHFS-mount a laptop folder to `/home/designer/work/laptop` and forward noVNC (port 27015) so the designer can upload files via Chrome to claude.ai/design.

**Architecture:** The scripts are forks of the developer connect scripts with three key changes: (1) `REMOTE_USER` hardcoded to `designer`, (2) no project picker — a single fixed `laptop` mount is auto-created on first run, (3) the SSH tunnel adds `-L 127.0.0.1:27015:127.0.0.1:27015` so the designer can reach noVNC at `http://localhost:27015/vnc.html` instead of opening an editor.

**Tech Stack:** Bash (Mac), PowerShell 5.1+ (Windows), OpenSSH, SSHFS via `claude-mount`

## Global Constraints

- No Persian text in scripts — English only in all comments, variable names, error messages (CLAUDE.md rule)
- `CM='$HOME/.local/bin/claude-mount'` must use single quotes so `$HOME` expands on the remote shell
- `PORT = 20000 + server_UID`; guard: `20000 < PORT ≤ 65535`
- `already_down` / `$alreadyDown` flag prevents double-cleanup in EXIT/finally traps
- `_novnc_opened` / `$novncOpened` flag prevents re-opening browser on tunnel reconnect
- `_tunnel_alive()` must use `ps -o state=` zombie filter, not just `kill -0`
- Single-quote sanitization on all user-supplied paths before passing to remote shell
- `timeout 8 ssh ...` in cleanup to bound hang if `claude-mount down` stalls
- Both EXIT and SIGTERM traps on Mac (kill won't trigger EXIT alone)
- `[Console]::Key` + `KeyChar` physical key checks on Windows (Persian/Arabic keyboard support)
- `ExitOnForwardFailure=no` on tunnel so a port-27015 conflict on laptop doesn't kill SSHFS

---

## Task 1: Mac connect.sh

**Files:**
- Create: `scripts/client/users/designer/connect.sh`

**Interfaces:**
- Consumes: `claude-mount` on server at `~/.local/bin/claude-mount`; `claude-mount.sh` in `../../server/` relative to script
- Produces: working Mac launcher that mounts `/home/designer/work/laptop` and opens noVNC

- [ ] **Step 1: Create the directory**

```bash
mkdir -p scripts/client/users/designer
```

- [ ] **Step 2: Write connect.sh**

Create `scripts/client/users/designer/connect.sh` with the complete content below:

```bash
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

tunnel_up() {
    sshx "timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$PORT' 2>/dev/null && echo UP" 2>/dev/null | grep -q UP
}

port_open()   { nc -zw3 "$1" "$2" 2>/dev/null; }
novnc_open()  { nc -zw2 127.0.0.1 "$NOVNC_PORT" 2>/dev/null; }

if [ "$(id -u)" -eq 0 ]; then
    die "Do not run with sudo. Run as your normal user: bash connect.sh"
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
    printf '%s\n' "$out" | grep -qi 'On' && return 0
    remote_login_on
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
    printf 'LAPTOP_USER=%s\nLAPTOP_PATH=%s\n' "$(whoami)" "$LAPTOP_PATH" > "$CFG"
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

step "Server key"
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

SRC="$(cd "$(dirname "$0")" && pwd)/../../server/claude-mount.sh"
if [ -f "$SRC" ]; then
    sshx "mkdir -p ~/.local/bin" 2>/dev/null || true
    scp -o BatchMode=yes -o ConnectTimeout=30 -q "$SRC" "$ALIAS:~/.local/bin/claude-mount" 2>/dev/null || true
    sshx "chmod +x ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=\$HOME/.local/bin:\$PATH\n' >> ~/.bashrc" 2>/dev/null || true
fi

echo ""
printf '    \033[0;32mReady\033[0m\n'
echo ""

MOUNT_LPATH="/home/$REMOTE_USER/mounts/$MOUNT_ID"
existing="$(sshx "$CM list 2>/dev/null" 2>/dev/null | grep "^${MOUNT_ID}|" || true)"
if [ -z "$existing" ]; then
    step "Configuring laptop mount"
    clean_path="$(printf '%s' "$LAPTOP_PATH" | tr "'" '-')"
    sshx "$CM add '$MOUNT_ID' 'Laptop' '$clean_path' '$MOUNT_LPATH'" 2>/dev/null || true
    step_ok "$MOUNT_LPATH"
else
    step "Laptop mount"
    step_ok "already configured"
fi

already_down=0
bg_pid=""
_novnc_opened=0

cleanup_session() {
    [ "$already_down" -eq 1 ] && return 0
    already_down=1
    printf '\n    Disconnecting...\n'
    timeout 8 ssh -n -o BatchMode=yes -o ConnectTimeout=5 "$ALIAS" "$CM down '$MOUNT_ID'" 2>/dev/null || true
    [ -n "$bg_pid" ] && kill "$bg_pid" 2>/dev/null || true
}
trap cleanup_session EXIT
trap 'cleanup_session; exit 143' SIGTERM

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
    mount_out="$(sshx "$CM up '$MOUNT_ID' 2>&1")"
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
            grep -qxF "$new_pub" "$HOME/.ssh/authorized_keys" || echo "$new_pub" >> "$HOME/.ssh/authorized_keys"
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

    if [ "$_novnc_opened" -eq 0 ]; then
        step "Opening noVNC"
        if novnc_open; then
            open "http://localhost:${NOVNC_PORT}/vnc.html" 2>/dev/null || true
            step_ok "http://localhost:${NOVNC_PORT}/vnc.html"
        else
            step_fail "noVNC port ${NOVNC_PORT} not reachable on localhost"
            warn "VNC stack may not be running. Ask admin: ssh smart@$SERVER_IP sudo designer-start start"
            warn "Fallback (LAN only): http://${SERVER_IP}:${NOVNC_PORT}/vnc.html"
        fi
        _novnc_opened=1
    fi

    echo ""
    printf '    ============================================\n'
    printf '    Session active -- keep this window open\n'
    printf '    R = reconnect   Q or Enter = disconnect\n'
    printf '    ============================================\n'
    echo ""

    while read -r -t 0 </dev/tty 2>/dev/null; do read -r -n 1 </dev/tty 2>/dev/null || true; done

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

    echo ""
    printf '    Disconnecting...\n'
    ssh -n -o BatchMode=yes -o ConnectTimeout=5 "$ALIAS" "$CM down '$MOUNT_ID'" 2>/dev/null || true
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
echo ""
```

- [ ] **Step 3: Make executable**

```bash
chmod +x scripts/client/users/designer/connect.sh
```

- [ ] **Step 4: Static checks**

```bash
bash -n scripts/client/users/designer/connect.sh
```

Expected: no output (clean parse).

```bash
grep -n '[^\x00-\x7F]' scripts/client/users/designer/connect.sh
```

Expected: no output (no non-ASCII / no Persian text).

```bash
grep -c "CM='\\\$HOME" scripts/client/users/designer/connect.sh
```

Expected: `1` (single-quoted CM variable present).

- [ ] **Step 5: Verify key invariants**

```bash
grep -n 'already_down' scripts/client/users/designer/connect.sh
```

Expected: multiple lines — declaration, trap, main loop reset, and set-to-1 lines.

```bash
grep -n '_novnc_opened' scripts/client/users/designer/connect.sh
```

Expected: declaration (`=0`), set-to-1 after open, guard `if` check — 3+ lines.

```bash
grep -n 'ps -p.*state=' scripts/client/users/designer/connect.sh
```

Expected: 1 line — zombie filter in `_tunnel_alive()`.

```bash
grep -n '\-L.*27015' scripts/client/users/designer/connect.sh
```

Expected: 1 line in the `ssh -N` tunnel command.

- [ ] **Step 6: Commit**

```bash
git add scripts/client/users/designer/connect.sh
git commit -m "feat: add designer Mac connect script with SSHFS + noVNC port forward"
```

---

## Task 2: Windows connect.ps1 + connect.bat

**Files:**
- Create: `scripts/client/users/designer/connect.ps1`
- Create: `scripts/client/users/designer/connect.bat`

**Interfaces:**
- Consumes: same server-side `claude-mount`; `claude-mount.sh` and `claude-git-setup.sh` in `..\..\server\` relative to script
- Produces: working Windows launcher (double-click connect.bat) that mounts and opens noVNC

- [ ] **Step 1: Write connect.ps1**

Create `scripts/client/users/designer/connect.ps1` with the complete content below:

```powershell
# connect.ps1 - Designer Connect launcher for Windows.
# Usage:  double-click connect.bat
#         connect.bat -Setup   (reconfigure laptop path)

param([switch]$Setup)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $scriptPath = $PSCommandPath -replace "'", "''"
    $setupFlag  = if ($Setup) { ' -Setup' } else { '' }
    $cmd = "& '$scriptPath'$setupFlag; if (`$LASTEXITCODE -ne 0) { Write-Host ''; Read-Host '    Press Enter to close' }"
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $cmd
    exit
}

$ErrorActionPreference = "Continue"
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Host "  [X] OpenSSH client (ssh.exe) not found." -ForegroundColor Red
    Write-Host "      Install it via: Settings -> Apps -> Optional Features -> OpenSSH Client" -ForegroundColor DarkGray
    Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
}

$ServerIP   = "192.168.210.240"
$Alias      = "claude-server"
$RemoteUser = "designer"
$CfgDir     = Join-Path $env:USERPROFILE ".config\claude-connect-designer"
$Cfg        = Join-Path $CfgDir "connect.conf"
$SshDir     = Join-Path $env:USERPROFILE ".ssh"
$CM         = '$HOME/.local/bin/claude-mount'
$NovncPort  = 27015
$MountId    = "laptop"

function Die($m)  { Write-Host ""; Write-Host "  [X] $m" -ForegroundColor Red; Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1 }
function Warn($m) { Write-Host "  [!] $m" -ForegroundColor DarkYellow }
function Step($m) { Write-Host ("    " + $m).PadRight(46, '.') -NoNewline -ForegroundColor DarkCyan }
function StepOk  {
    param([string]$d='')
    if ($d) { Write-Host " $d" -ForegroundColor Green } else { Write-Host " ok" -ForegroundColor Green }
    foreach ($fx in $script:pendingFixes) { Write-Host "      -> fixed: $fx" -ForegroundColor DarkGray }
    $script:pendingFixes = @()
}
function StepFail {
    param([string]$d='')
    Write-Host " failed" -ForegroundColor Red
    if ($d) { Write-Host "      -> $d" -ForegroundColor DarkGray }
    $script:pendingFixes = @()
}
$script:pendingFixes = @()

function Repair-SshPerm([string]$path, [string]$label) {
    if (-not (Test-Path $path)) { return }
    $out = (icacls $path 2>$null) -join ' '
    icacls $path /reset 2>$null | Out-Null
    icacls $path /inheritance:r /grant "$env:USERNAME`:F" 2>$null | Out-Null
    if ($script:LaptopUser -and $script:LaptopUser -ne $env:USERNAME) {
        icacls $path /grant "$($script:LaptopUser)`:F" 2>$null | Out-Null
    }
    if ($out -match '\(I\)|Everyone|BUILTIN\\Users') { $script:pendingFixes += "$label permissions" }
}

function Install-ServerKey([string]$pub, [bool]$ForceRestart = $false) {
    $adminFile = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
    $userFile  = Join-Path $SshDir "authorized_keys"

    $adminDir = Split-Path $adminFile
    if (Test-Path $adminDir) {
        if (-not (Test-Path $adminFile)) { New-Item -ItemType File -Path $adminFile -Force | Out-Null }
        $_adminOut = (icacls $adminFile 2>$null) -join ' '
        icacls $adminFile /reset 2>$null | Out-Null
        icacls $adminFile /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" 2>$null | Out-Null
        if ($_adminOut -match '\(I\)|Everyone|BUILTIN\\Users') { $script:pendingFixes += "administrators_authorized_keys permissions" }
    }

    foreach ($akFile in @($adminFile, $userFile)) {
        if (-not (Test-Path (Split-Path $akFile))) { continue }
        if (-not (Test-Path $akFile)) { New-Item -ItemType File -Path $akFile -Force -ErrorAction SilentlyContinue | Out-Null }
        if (-not (Test-Path $akFile)) { continue }
        $lines = @(Get-Content $akFile -ErrorAction SilentlyContinue | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        if ($lines -notcontains $pub) { Add-Content -Path $akFile -Value $pub -Encoding ASCII }
        if ($akFile -eq $userFile) { Repair-SshPerm $akFile "authorized_keys" }
    }

    $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
    if ($ForceRestart -and $sshdSvc -and $sshdSvc.Status -eq 'Running') {
        Restart-Service sshd -ErrorAction SilentlyContinue
        $deadline = (Get-Date).AddSeconds(20)
        $sshdReady = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 1
            $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
            if ($sshdSvc -and $sshdSvc.Status -eq 'Running') {
                try {
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    if ($tcp.BeginConnect('127.0.0.1', 22, $null, $null).AsyncWaitHandle.WaitOne(1000)) {
                        $tcp.Close(); $sshdReady = $true; break
                    }
                    $tcp.Close()
                } catch {}
            }
        }
        if (-not $sshdReady) {
            $script:pendingFixes += "sshd restart failed - run connect.bat as administrator"
        }
    } elseif (-not $sshdSvc -or $sshdSvc.Status -ne 'Running') {
        Start-Service sshd -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function SshX([string]$Cmd) {
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=30 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 $Alias $Cmd
}

function Test-Tunnel {
    $r = ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=8 `
             -o ServerAliveInterval=3 -o ServerAliveCountMax=2 `
             $Alias "timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$Port' 2>/dev/null && echo UP" 2>$null
    return ($r -match 'UP')
}

function Test-NovncLocal {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ok  = $tcp.BeginConnect('127.0.0.1', $NovncPort, $null, $null).AsyncWaitHandle.WaitOne(2000)
        $tcp.Close()
        return $ok
    } catch { return $false }
}

function PortOpen($ip, $port) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ok  = $tcp.BeginConnect($ip, $port, $null, $null).AsyncWaitHandle.WaitOne(3000)
        $tcp.Close()
        return $ok
    } catch { return $false }
}

function Remove-SshHostBlock($cfgPath, $alias) {
    if (-not (Test-Path $cfgPath)) { return }
    $out  = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($ln in (Get-Content $cfgPath)) {
        if ($ln -match '^\s*Host\s+(.+)$') { $skip = (($matches[1].Trim() -split '\s+') -contains $alias) }
        if (-not $skip) { $out.Add($ln) }
    }
    Set-Content -Path $cfgPath -Value $out -Encoding ASCII
}

New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
New-Item -ItemType Directory -Force -Path $SshDir  | Out-Null

$_dirOut   = (icacls $SshDir 2>$null) -join ' '
$_dirFixed = $_dirOut -match '\(I\)|Everyone|BUILTIN\\Users'
icacls $SshDir /reset 2>$null | Out-Null
icacls $SshDir /inheritance:r /grant "$env:USERNAME`:(OI)(CI)F" 2>$null | Out-Null

Clear-Host
Write-Host ""
Write-Host "    Designer Connect" -ForegroundColor White
Write-Host "    $Alias  |  $ServerIP" -ForegroundColor DarkGray
Write-Host ""
if ($_dirFixed) { Write-Host "      -> fixed: .ssh directory permissions" -ForegroundColor DarkGray; Write-Host "" }

if ($Setup -or -not (Test-Path $Cfg)) {
    Write-Host "  First-time setup" -ForegroundColor Cyan
    Write-Host ""
    $LaptopPath = (Read-Host "    Folder on your laptop to share (e.g. D:\Designs)").Trim() -replace '\\','/'
    if (-not $LaptopPath) { Die "Laptop path is required." }
    @("LAPTOP_USER=$env:USERNAME", "LAPTOP_PATH=$LaptopPath") | Set-Content -Path $Cfg -Encoding ASCII
    Write-Host ""
}
$conf = @{}
Get-Content $Cfg | ForEach-Object { if ($_ -match '^(.+?)=(.*)$') { $conf[$matches[1]] = $matches[2] } }
$LaptopUser = $conf["LAPTOP_USER"]
$LaptopPath = $conf["LAPTOP_PATH"]
$script:LaptopUser = $LaptopUser
if ($LaptopUser -and (Test-Path "C:\Users\$LaptopUser")) {
    $SshDir = Join-Path "C:\Users\$LaptopUser" ".ssh"
}
New-Item -ItemType Directory -Force -Path $SshDir | Out-Null

Step "Laptop SSH key"
$keyA = Join-Path $SshDir "id_ed25519"
if (-not (Test-Path $keyA)) { ssh-keygen -t ed25519 -N '""' -f $keyA -q }
if (Test-Path $keyA) {
    Repair-SshPerm $keyA "SSH private key"
    StepOk
} else { StepFail "could not create key"; Read-Host "    Press Enter to close" | Out-Null; exit 1 }

$sshCfg = Join-Path $SshDir "config"
if (-not (Test-Path $sshCfg)) { New-Item -ItemType File -Path $sshCfg | Out-Null }
Remove-SshHostBlock $sshCfg $Alias
@"

Host $Alias
    HostName $ServerIP
    User $RemoteUser
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
"@ | Add-Content -Path $sshCfg -Encoding ASCII
icacls $sshCfg /reset 2>$null | Out-Null
icacls $sshCfg /inheritance:r /grant "$env:USERNAME`:F" 2>$null | Out-Null

$connected = $false
$needsKey  = $false
for ($attempt = 1; $attempt -le 10; $attempt++) {
    Write-Host -NoNewline ("    Connecting $attempt/10").PadRight(46, '.') -ForegroundColor DarkCyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=15 $Alias "true" 2>$null
    $sw.Stop(); $connT = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if ($LASTEXITCODE -eq 0) {
        Write-Host " $RemoteUser@$ServerIP" -ForegroundColor Green
        $connected = $true; break
    }
    if (PortOpen $ServerIP 22) {
        Write-Host " auth failed (${connT}s) - no key, installing now" -ForegroundColor DarkYellow
        $needsKey = $true; break
    }
    Write-Host " no response (${connT}s)" -ForegroundColor DarkGray
    if ($attempt -lt 10) {
        Write-Host "    Waiting 5s (VPN on? Server up?)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
    }
}

if (-not $connected -and -not $needsKey) {
    Write-Host ""
    Warn "Cannot reach $ServerIP after 10 attempts"
    Warn "VPN connected? Server running?"
    Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
}

if ($needsKey) {
    Write-Host ""
    ssh-keygen -R $ServerIP 2>$null | Out-Null
    Write-Host "    Enter designer password (one time only):" -ForegroundColor Yellow
    $pubKeyContent = (Get-Content "$keyA.pub").Trim() -replace "'", "'\''"
    ssh -o StrictHostKeyChecking=accept-new "$RemoteUser@$ServerIP" `
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && printf '%s\n' '$pubKeyContent' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    $keyCopyOk = ($LASTEXITCODE -eq 0)
    Step "Verifying connection"
    $verifySW = [System.Diagnostics.Stopwatch]::StartNew()
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=15 $Alias "true" 2>$null
    $verifySW.Stop(); $verifyT = [math]::Round($verifySW.Elapsed.TotalSeconds, 1)
    if ($LASTEXITCODE -ne 0) {
        if (-not $keyCopyOk) { StepFail "key copy failed after ${verifyT}s - wrong password?" }
        else { StepFail "still cannot connect after ${verifyT}s" }
        Warn "Cannot connect - user=$RemoteUser  host=$ServerIP"
        Write-Host ""; Read-Host "    Press Enter to close" | Out-Null; exit 1
    }
    StepOk "$RemoteUser@$ServerIP"
}

Step "Getting tunnel port + server key"
$initOut = (SshX "id -u && (test -f ~/.ssh/claude_laptop || ssh-keygen -t ed25519 -N '' -f ~/.ssh/claude_laptop -q) && cat ~/.ssh/claude_laptop.pub") -join "`n"
$lines   = ($initOut -replace "`r",'') -split "`n" | Where-Object { $_.Trim() -ne '' }
$uidStr  = ($lines | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1) -replace '\D',''
$Port    = 20000 + [int]$uidStr
$PubB    = ($lines | Where-Object { $_ -match '^ssh-' } | Select-Object -First 1).Trim()
if ($Port -le 20000) { StepFail "could not get UID from server"; Read-Host "    Press Enter to close" | Out-Null; exit 1 }
if (-not $PubB)      { StepFail "could not read server key";     Read-Host "    Press Enter to close" | Out-Null; exit 1 }
StepOk "port $Port"

Step "Setting up server key"
Install-ServerKey $PubB
StepOk

Step "Configuring server"
Remove-SshHostBlock $sshCfg $Alias
@"

Host $Alias
    HostName $ServerIP
    User $RemoteUser
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
    RemoteForward $Port localhost:22
    ExitOnForwardFailure no
"@ | Add-Content -Path $sshCfg -Encoding ASCII
Repair-SshPerm $sshCfg "SSH config"
SshX "mkdir -p ~/.local/bin && printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\n' '$LaptopUser' '$Port' > ~/.claude-connect.conf" 2>$null | Out-Null
StepOk "laptop=$LaptopUser port=$Port"

$serverScriptDir = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\..\server"))
$src    = Join-Path $serverScriptDir "claude-mount.sh"
$gitSrc = Join-Path $serverScriptDir "claude-git-setup.sh"
if (Test-Path $src)    { scp -o BatchMode=yes -o ConnectTimeout=30 -q $src    "${Alias}:~/.local/bin/claude-mount"     2>$null }
if (Test-Path $gitSrc) { scp -o BatchMode=yes -o ConnectTimeout=30 -q $gitSrc "${Alias}:~/.local/bin/claude-git-setup" 2>$null }
$chmodCmd = @()
if (Test-Path $src)    { $chmodCmd += "chmod +x ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=`$HOME/.local/bin:`$PATH\n' >> ~/.bashrc" }
if (Test-Path $gitSrc) { $chmodCmd += "chmod +x ~/.local/bin/claude-git-setup" }
if ($chmodCmd.Count -gt 0) { SshX ($chmodCmd -join '; ') 2>$null | Out-Null }

Write-Host ""
Write-Host "    Ready" -ForegroundColor Green
Write-Host ""

$MountLpath = "/home/$RemoteUser/mounts/$MountId"
$existing = (SshX "$CM list 2>/dev/null") -join '' | Select-String "^${MountId}\|" | Select-Object -First 1
if (-not $existing) {
    Step "Configuring laptop mount"
    $cleanPath = $LaptopPath -replace "'", "-"
    SshX "$CM add '$MountId' 'Laptop' '$cleanPath' '$MountLpath'" 2>$null | Out-Null
    StepOk $MountLpath
} else {
    Step "Laptop mount"
    StepOk "already configured"
}

Step "Checking SSH service"
$svc = Get-Service sshd -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne 'Running') {
    StepFail "OpenSSH Server not running"
    Write-Host "    Trying to start sshd..." -ForegroundColor Yellow
    try {
        Start-Service sshd -ErrorAction Stop
        Start-Sleep -Seconds 1
        $svc = Get-Service sshd -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') {
            Write-Host "    sshd started ok." -ForegroundColor Green
        } else {
            Die "Could not start sshd. Run as admin: Start-Service sshd"
        }
    } catch { Die "Error starting sshd: $($_.Exception.Message)" }
} else { StepOk }

$fwRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if (-not $fwRule) {
    Write-Host "    [!] Firewall rule for SSH missing - adding..." -ForegroundColor Yellow
    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH SSH Server (sshd)" `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 `
        -ErrorAction SilentlyContinue | Out-Null
} elseif ($fwRule.Enabled.ToString() -ne 'True') {
    Write-Host "    [!] Firewall rule for SSH was disabled - enabling..." -ForegroundColor Yellow
    Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
}

$novncOpened = $false

:mainLoop while ($true) {
$alreadyDown = $false
$bgTunnel    = $null

try {
    :sessionLoop while ($true) {
        if ($bgTunnel -and -not $bgTunnel.HasExited) {
            Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
        }

        Step "Starting SSH tunnel"
        $bgTunnel = Start-Process ssh -WindowStyle Hidden -PassThru -ArgumentList @(
            "-N", "-o", "ExitOnForwardFailure=no",
            "-o", "ServerAliveInterval=20", "-o", "ServerAliveCountMax=5",
            "-R", "$Port`:localhost:22",
            "-L", "127.0.0.1:${NovncPort}:127.0.0.1:${NovncPort}",
            $Alias)
        StepOk "pid $($bgTunnel.Id)"

        $up = $false
        $tunnelMsg = ""
        for ($i = 1; $i -le 8; $i++) {
            Start-Sleep -Seconds 2
            Write-Host -NoNewline "    Tunnel check $i/8..." -ForegroundColor DarkGray
            if ($bgTunnel.HasExited) {
                $tunnelMsg = "SSH process exited with code $($bgTunnel.ExitCode)"
                Write-Host " SSH process died" -ForegroundColor Red
                break
            }
            if (Test-Tunnel) {
                Write-Host " port $Port is open" -ForegroundColor Green
                $up = $true; break
            }
            Write-Host " port $Port not open yet" -ForegroundColor DarkGray
        }

        if (-not $up) {
            Write-Host ""
            Warn "Tunnel did not come up on port $Port"
            if ($tunnelMsg) { Warn $tunnelMsg }
            elseif (-not (PortOpen $ServerIP 22)) { Warn "Server unreachable - VPN disconnected?" }
            else { Warn "Check Windows Firewall - port 22 must allow inbound connections" }
            Write-Host ""
            Write-Host "    R = retry   Q = quit" -ForegroundColor DarkGray
            $rk = ''
            while ($rk -ne 'r' -and $rk -ne 'q') {
                if ([Console]::KeyAvailable) {
                    $ki2 = [Console]::ReadKey($true)
                    if ($ki2.KeyChar.ToString().ToLower() -eq 'r' -or $ki2.Key -eq [ConsoleKey]::R) { $rk = 'r' }
                    elseif ($ki2.KeyChar.ToString().ToLower() -eq 'q' -or $ki2.Key -eq [ConsoleKey]::Q) { $rk = 'q' }
                } else { Start-Sleep -Milliseconds 200 }
            }
            if ($rk -eq 'r') { Write-Host ""; continue }
            $alreadyDown = $true; break sessionLoop
        }

        SshX "$CM recover" 2>$null | Out-Null

        Step "Mounting files"
        $mountSW  = [System.Diagnostics.Stopwatch]::StartNew()
        $mountOut = (SshX "$CM up '$MountId' 2>&1") | Out-String
        $mountSW.Stop(); $mountT = [math]::Round($mountSW.Elapsed.TotalSeconds, 1)
        $mountOk  = $LASTEXITCODE -eq 0 -and $mountOut -notmatch 'error:|FAILED|No tunnel|not configured'

        if (-not $mountOk -and $mountOut -match 'key auth failed|connection reset|reset by peer|publickey|Permission denied') {
            Write-Host " retrying..." -ForegroundColor DarkGray
            if ($mountOut -match 'connection reset|reset by peer') {
                Warn "Connection reset - killing stale mounts, fixing firewall, restarting sshd"
                SshX 'pkill -u "$USER" sshfs 2>/dev/null; true' 2>$null | Out-Null
                $fw = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
                if (-not $fw) {
                    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH SSH Server (sshd)" `
                        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any `
                        -ErrorAction SilentlyContinue | Out-Null
                    $script:pendingFixes += "SSH firewall rule created"
                } elseif ($fw.Enabled.ToString() -ne 'True' -or $fw.Profile.ToString() -notmatch 'Any') {
                    Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Enabled True -Profile Any -ErrorAction SilentlyContinue
                    $script:pendingFixes += "SSH firewall rule fixed"
                }
            } else {
                Warn "Key rejected - reinstalling server key and restarting sshd"
            }
            $newPub = ((SshX "cat ~/.ssh/claude_laptop.pub") -join '').Trim()
            if ($newPub) {
                Install-ServerKey $newPub -ForceRestart $true
                if (-not (Test-Tunnel)) {
                    Write-Host ""; Warn "Tunnel dropped after sshd restart - reconnecting..."
                    continue
                }
                Step "Mounting files"
                $mountSW  = [System.Diagnostics.Stopwatch]::StartNew()
                $mountOut = (SshX "$CM up '$MountId' 2>&1") | Out-String
                $mountSW.Stop(); $mountT = [math]::Round($mountSW.Elapsed.TotalSeconds, 1)
                $mountOk  = $LASTEXITCODE -eq 0 -and $mountOut -notmatch 'error:|FAILED|No tunnel|not configured'
            }
        }

        if (-not $mountOk) {
            StepFail $mountOut.Trim()
            if ($mountOut -match 'No such file|not found|cannot find') {
                Warn "Path not found on laptop. Re-run connect.bat -Setup to correct the path."
            }
            Write-Host ""
            Write-Host "    R = retry   Q = quit" -ForegroundColor DarkGray
            $rk = ''
            while ($rk -ne 'r' -and $rk -ne 'q') {
                if ([Console]::KeyAvailable) {
                    $ki2 = [Console]::ReadKey($true)
                    if ($ki2.KeyChar.ToString().ToLower() -eq 'r' -or $ki2.Key -eq [ConsoleKey]::R) { $rk = 'r' }
                    elseif ($ki2.KeyChar.ToString().ToLower() -eq 'q' -or $ki2.Key -eq [ConsoleKey]::Q) { $rk = 'q' }
                } else { Start-Sleep -Milliseconds 200 }
            }
            if ($rk -eq 'r') { Write-Host ""; continue }
            $alreadyDown = $true; break sessionLoop
        }

        StepOk "${mountT}s"
        $cleanOut = ($mountOut.Trim() -replace '^already mounted:\s*', '')
        if ($cleanOut) { Write-Host "      -> $cleanOut" -ForegroundColor DarkGray }

        if (-not $novncOpened) {
            Step "Opening noVNC"
            if (Test-NovncLocal) {
                Start-Process "http://localhost:${NovncPort}/vnc.html"
                StepOk "http://localhost:${NovncPort}/vnc.html"
            } else {
                StepFail "noVNC port $NovncPort not reachable on localhost"
                Warn "VNC stack may not be running. Ask admin: ssh smart@$ServerIP sudo designer-start start"
                Warn "Fallback (LAN only): http://${ServerIP}:${NovncPort}/vnc.html"
            }
            $novncOpened = $true
        }

        Write-Host ""
        Write-Host "    ============================================" -ForegroundColor DarkGray
        Write-Host "    Session active -- keep this window open" -ForegroundColor Cyan
        Write-Host "    R = reconnect   Q or Enter = disconnect" -ForegroundColor DarkGray
        Write-Host "    ============================================" -ForegroundColor DarkGray
        Write-Host ""

        while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }

        $action = 'q'
        $gotKey = $false
        while (-not $bgTunnel.HasExited) {
            if ([Console]::KeyAvailable) {
                $ki = [Console]::ReadKey($true)
                if ($ki.KeyChar.ToString().ToLower() -eq 'r' -or $ki.Key -eq [ConsoleKey]::R) { $action = 'r' }
                $gotKey = $true
                break
            }
            Start-Sleep -Milliseconds 500
        }
        if (-not $gotKey -and $bgTunnel.HasExited) {
            $action = 'r'
            Write-Host "    Connection dropped - reconnecting..." -ForegroundColor Yellow
        }

        Write-Host ""
        Write-Host "    Disconnecting..." -ForegroundColor DarkGray
        SshX "$CM down '$MountId'" 2>$null | Out-Null
        if (-not $bgTunnel.HasExited) {
            Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
        }
        $alreadyDown = $true

        if ($action -ne 'r') { break sessionLoop }

        $alreadyDown = $false
        Write-Host ""
        Write-Host "    Reconnecting in 2s..." -ForegroundColor Cyan
        Start-Sleep -Seconds 2
        Write-Host ""
    }
} finally {
    if (-not $alreadyDown) {
        Write-Host ""
        Write-Host "    Disconnecting..." -ForegroundColor DarkGray
        SshX "$CM down '$MountId'" 2>$null | Out-Null
        Write-Host ""
    }
    if ($bgTunnel -and -not $bgTunnel.HasExited) {
        Stop-Process -Id $bgTunnel.Id -Force -ErrorAction SilentlyContinue
    }
}

while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }

Write-Host ""
Write-Host "    Disconnected. What would you like to do?" -ForegroundColor Cyan
Write-Host "    C = connect again   X = exit" -ForegroundColor DarkGray
Write-Host ""

$choice = ""
while ($choice -ne "c" -and $choice -ne "x") {
    if ([Console]::KeyAvailable) {
        $ki = [Console]::ReadKey($true)
        $kc = $ki.KeyChar.ToString().ToLower()
        if ($kc -eq "c" -or $ki.Key -eq [ConsoleKey]::C) {
            Write-Host "    Reconnecting..." -ForegroundColor Green
            Start-Sleep -Seconds 1
            Write-Host ""
            continue mainLoop
        } elseif ($kc -eq "x" -or $ki.Key -eq [ConsoleKey]::X) {
            Write-Host "    Exiting..." -ForegroundColor DarkGray
            break mainLoop
        }
    } else { Start-Sleep -Milliseconds 100 }
}

} # end :mainLoop
Write-Host ""
```

- [ ] **Step 2: Write connect.bat**

Create `scripts/client/users/designer/connect.bat`:

```batch
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0connect.ps1" %*
```

- [ ] **Step 3: Static checks**

```powershell
# Parse check (run in PowerShell)
$null = [System.Management.Automation.PSParser]::Tokenize(
    (Get-Content scripts/client/users/designer/connect.ps1 -Raw), [ref]$null)
Write-Host "Parse OK"
```

Expected: `Parse OK`

```bash
grep -n '[^\x00-\x7F]' scripts/client/users/designer/connect.ps1
```

Expected: no output (no Persian/non-ASCII text).

- [ ] **Step 4: Verify key invariants**

```bash
# alreadyDown double-cleanup guard
grep -n 'alreadyDown' scripts/client/users/designer/connect.ps1 | wc -l
```

Expected: 6+ lines (declaration, set false at loop top, set true on cleanup paths, guard in finally).

```bash
# novncOpened flag - not re-opened on reconnect
grep -n 'novncOpened' scripts/client/users/designer/connect.ps1
```

Expected: declaration (`= $false`), `if (-not $novncOpened)` guard, `= $true` set — 3 lines.

```bash
# Local port forward in tunnel args
grep -n 'NovncPort.*127.0.0.1\|127.0.0.1.*NovncPort' scripts/client/users/designer/connect.ps1
```

Expected: 1 line in the `Start-Process ssh` ArgumentList.

```bash
# Persian keyboard physical key checks present
grep -n 'ConsoleKey.*R\|ConsoleKey.*Q\|ConsoleKey.*C\|ConsoleKey.*X' scripts/client/users/designer/connect.ps1 | wc -l
```

Expected: 6+ lines (R/Q in tunnel-fail, R/Q in mount-fail, R in wait loop, C/X in post-disconnect menu).

```bash
# ExitOnForwardFailure=no present
grep -c 'ExitOnForwardFailure=no' scripts/client/users/designer/connect.ps1
```

Expected: `1`

- [ ] **Step 5: Commit**

```bash
git add scripts/client/users/designer/connect.ps1 scripts/client/users/designer/connect.bat
git commit -m "feat: add designer Windows connect script with SSHFS + noVNC port forward"
```

---

## Task 3: Update CLAUDE.md File Map

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- No code interfaces — documentation only

- [ ] **Step 1: Add designer scripts to File Map section**

In `CLAUDE.md`, find the `File Map` section and add the designer user scripts under the `scripts/client/users/` path:

```
  client/
    mac/connect.sh                # Mac launcher (bash, runs in Terminal)
    windows/connect.ps1           # Windows launcher (PowerShell, self-elevates to admin)
    users/<name>/connect.ps1      # Per-user forks (e.g. sepidz)
    users/designer/connect.sh     # Designer Mac launcher — SSHFS + noVNC port forward
    users/designer/connect.ps1    # Designer Windows launcher — SSHFS + noVNC port forward
```

- [ ] **Step 2: Verify**

```bash
grep -A 8 'File Map' CLAUDE.md | grep designer
```

Expected: 2 lines (one for .sh, one for .ps1).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document designer connect scripts in File Map"
```
