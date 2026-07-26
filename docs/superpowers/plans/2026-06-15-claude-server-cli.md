# claude-server CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `claude-server` CLI — a dispatcher that installs a new server with one command and consolidates user management, verify, and status in one place.

**Architecture:** A bash dispatcher in `scripts/server/claude-server` that routes subcommands to separate files in `commands/`. The `install` command bootstraps on a new server and installs the dispatcher itself to `/usr/local/bin`.

**Tech Stack:** Bash, Python3 (only for existing check-tokens.py)

---

## File Map

| File | Action | Description |
|------|--------|-------------|
| `scripts/server/claude-server` | Create | Main dispatcher |
| `scripts/server/commands/install.sh` | Create | Full server install |
| `scripts/server/commands/add-user.sh` | Create | Create developer user |
| `scripts/server/commands/verify.sh` | Create | Test all components |
| `scripts/server/commands/status.sh` | Create | Sessions + usage |
| `scripts/server/server-setup.sh` | Modify | Add deprecation notice |
| `scripts/server/setup-new-user.sh` | Modify | Add deprecation notice |
| `docs/claude-design.md` | Modify | Add claude-server commands |
| `CLAUDE.md` | Create | Script sync rules |

---

## Task 1: CLAUDE.md and folder structure

**Files:**
- Create: `CLAUDE.md`
- Create: `scripts/server/commands/.gitkeep`

- [ ] **Step 1: Create commands folder**

```bash
mkdir -p /home/smart/mounts/claude-code-server/scripts/server/commands
```

- [ ] **Step 2: Write CLAUDE.md**

File `CLAUDE.md` at project root:

```markdown
# Claude Code Server — Project Rules

## Script sync rule

Whenever one of the files below changes, deploy files must be updated too:

| Changed file | Must update |
|----------------|----------------|
| `scripts/server/hooks/claude-hook-*.sh` | `scripts/server/commands/install.sh` (deploy hooks section) |
| `scripts/server/claude-wrapper.sh` | `scripts/server/commands/install.sh` (deploy wrapper section) |
| `scripts/server/claude-limits.conf` | `scripts/server/commands/install.sh` (deploy config section) |
| `scripts/server/claude-automount.sh` | `scripts/server/commands/install.sh` (deploy scripts section) |
| `scripts/server/commands/add-user.sh` | Verify settings.json template is still correct |

Every change to hooks or wrapper must be deployed on the server with:
```bash
sudo claude-server install
```
This command is idempotent — safe to run again without worry.

## scripts/server structure

- `claude-server` — CLI dispatcher (installed to `/usr/local/bin/claude-server`)
- `commands/` — each subcommand is a separate file
- `hooks/` — Claude Code hooks (deployed to `/usr/local/bin/`)
- Deprecated scripts: `server-setup.sh`, `setup-new-user.sh`, `install-designer-deps.sh`, `setup-designer.sh`
```

- [ ] **Step 3: Verify folder was created**

```bash
ls /home/smart/mounts/claude-code-server/scripts/server/commands/
ls /home/smart/mounts/claude-code-server/CLAUDE.md
```

Expected: folder exists, CLAUDE.md exists.

- [ ] **Step 4: commit**

```bash
cd /home/smart/mounts/claude-code-server
git add CLAUDE.md scripts/server/commands/
git commit -m "chore: add CLAUDE.md rules and commands/ directory"
```

---

## Task 2: dispatcher — `scripts/server/claude-server`

**Files:**
- Create: `scripts/server/claude-server`

- [ ] **Step 1: Write dispatcher file**

```bash
#!/bin/bash
# claude-server - Claude Code Server management CLI
# Usage: claude-server <command> [options]
# Install: sudo bash scripts/server/claude-server install

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
COMMANDS_DIR="$SCRIPT_DIR/commands"

# If run from /usr/local/bin, find commands dir
if [ ! -d "$COMMANDS_DIR" ]; then
    # installed mode: commands are alongside the installed script or in repo
    REPO_COMMANDS="/home/smart/mounts/claude-code-server/scripts/server/commands"
    [ -d "$REPO_COMMANDS" ] && COMMANDS_DIR="$REPO_COMMANDS"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
    echo ""
    echo -e "${BOLD}claude-server${NC} v${VERSION} — Claude Code Server management"
    echo ""
    echo "Usage: claude-server <command> [options]"
    echo ""
    echo "Commands:"
    echo "  install              Full server install from scratch (must be root)"
    echo "  add-user <name>      Add a new developer"
    echo "  verify               Test all components"
    echo "  status               Session and usage status"
    echo ""
    echo "Options:"
    echo "  --help, -h           This help"
    echo "  --version, -v        Version"
    echo ""
    echo "Examples:"
    echo "  sudo claude-server install"
    echo "  sudo claude-server add-user amir"
    echo "  claude-server verify"
    echo "  claude-server status"
    echo ""
}

CMD="${1:-}"
shift 2>/dev/null || true

case "$CMD" in
    install|add-user|verify|status)
        SCRIPT="$COMMANDS_DIR/${CMD}.sh"
        if [ ! -f "$SCRIPT" ]; then
            echo -e "${RED}Error:${NC} command script not found: $SCRIPT" >&2
            echo "Run from repo root or reinstall: sudo claude-server install" >&2
            exit 1
        fi
        exec bash "$SCRIPT" "$@"
        ;;
    --version|-v)
        echo "claude-server v${VERSION}"
        ;;
    --help|-h|"")
        usage
        ;;
    *)
        echo -e "${RED}Unknown command:${NC} $CMD" >&2
        usage >&2
        exit 1
        ;;
esac
```

- [ ] **Step 2: Make executable and test --help**

```bash
chmod +x /home/smart/mounts/claude-code-server/scripts/server/claude-server
bash /home/smart/mounts/claude-code-server/scripts/server/claude-server --help
bash /home/smart/mounts/claude-code-server/scripts/server/claude-server --version
```

Expected: help displayed, version is `1.0.0`.

- [ ] **Step 3: Test unknown command**

```bash
bash /home/smart/mounts/claude-code-server/scripts/server/claude-server foo 2>&1
echo "exit: $?"
```

Expected: message `Unknown command: foo` and exit code 1.

- [ ] **Step 4: commit**

```bash
cd /home/smart/mounts/claude-code-server
git add scripts/server/claude-server
git commit -m "feat: add claude-server dispatcher CLI"
```

---

## Task 3: `commands/verify.sh`

Write this first because other tasks are tested with it.

**Files:**
- Create: `scripts/server/commands/verify.sh`

- [ ] **Step 1: Write verify.sh file**

```bash
#!/bin/bash
# commands/verify.sh - verify all Claude Code Server components
# Usage: claude-server verify

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
GRAY='\033[0;37m'
NC='\033[0m'

ok()   { printf "  ${GREEN}ok${NC}    %s\n" "$1"; }
warn() { printf "  ${YELLOW}warn${NC}  %s\n" "$1"; }
fail() { printf "  ${RED}FAIL${NC}  %s\n" "$1"; FAILURES=$((FAILURES+1)); }
info() { printf "  ${GRAY}--${NC}    %s\n" "$1"; }

FAILURES=0

echo ""
echo -e "${BOLD}=== Claude Code Server — Verify ===${NC}"
echo ""

# --- System binaries ---
echo -e "${BOLD}System${NC}"

CLAUDE_VER=$(claude --version 2>/dev/null | head -1)
[ -n "$CLAUDE_VER" ] && ok "claude: $CLAUDE_VER" || fail "claude: not in PATH"

[ -L /usr/local/bin/claude-real ] && \
    ok "claude-real → $(readlink /usr/local/bin/claude-real)" || \
    fail "claude-real: symlink missing"

[ -f /usr/local/bin/claude ] && ok "claude wrapper: exists" || fail "claude wrapper: missing"

for h in claude-hook-pre claude-hook-stop claude-hook-logout-block; do
    [ -x "/usr/local/bin/$h" ] && ok "$h: installed" || fail "$h: missing or not executable"
done

for b in claude-automount claude-git-setup; do
    [ -x "/usr/local/bin/$b" ] && ok "$b: installed" || warn "$b: missing"
done

[ -f /usr/local/lib/claude-mount ] && ok "claude-mount: installed" || warn "claude-mount: missing"
[ -f /etc/claude-limits.conf ] && ok "claude-limits.conf: exists" || warn "claude-limits.conf: missing (default limit=2)"
[ -d /var/run/claude-active ] && ok "/var/run/claude-active: exists" || fail "/var/run/claude-active: missing"
[ -f /var/log/claude-activity.jsonl ] && ok "activity log: exists" || warn "activity log: missing (will be created on first use)"

echo ""
echo -e "${BOLD}Designer${NC}"

for bin in Xvfb x11vnc websockify fluxbox; do
    command -v "$bin" &>/dev/null && ok "$bin: installed" || fail "$bin: not found"
done
command -v google-chrome-stable &>/dev/null && \
    ok "Chrome: $(google-chrome-stable --version 2>/dev/null | head -1)" || \
    fail "Chrome: not found"
id designer &>/dev/null && ok "designer user: exists" || warn "designer user: missing"
[ -x /usr/local/bin/designer-start ] && ok "designer-start: installed" || warn "designer-start: missing"

echo ""
echo -e "${BOLD}Users${NC}"
echo ""

SYSTEM_USERS="nobody root daemon bin sys sync games man lp mail news uucp proxy www-data backup list irc gnats _apt designer"

for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd | sort); do
    h="/home/$u"
    [ -d "$h" ] || continue
    echo "$SYSTEM_USERS" | grep -qw "$u" && continue

    score=0; total=4
    has_mount=false;  [ -f "$h/.local/bin/claude-mount" ]    && has_mount=true    && ((score++))
    has_hooks=false
    has_effort=false
    if [ -f "$h/.claude/settings.json" ]; then
        grep -q 'claude-hook-pre'  "$h/.claude/settings.json" 2>/dev/null && has_hooks=true  && ((score++))
        grep -q 'effortLevel'      "$h/.claude/settings.json" 2>/dev/null && has_effort=true && ((score++))
    fi
    has_bashrc=false; grep -q 'claude-automount' "$h/.bashrc" 2>/dev/null && has_bashrc=true && ((score++))

    if   [ "$score" -eq "$total" ]; then tag="${GREEN}READY${NC}"
    elif [ "$score" -eq 0 ];        then tag="${RED}EMPTY${NC}"
    else                                 tag="${YELLOW}PARTIAL ($score/$total)${NC}"
    fi

    printf "  ${BOLD}%-16s${NC} " "$u"
    echo -e "$tag"
    $has_mount   && ok "claude-mount"       || fail "claude-mount missing"
    $has_hooks   && ok "hooks in settings"  || fail "hooks missing in settings.json"
    $has_effort  && ok "effortLevel set"    || warn "effortLevel missing"
    $has_bashrc  && ok "automount .bashrc"  || fail "automount missing in .bashrc"
    echo ""
done

# --- Summary ---
if [ "$FAILURES" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All checks passed.${NC}"
else
    echo -e "${RED}${BOLD}$FAILURES check(s) failed.${NC}"
    exit 1
fi
echo ""
```

- [ ] **Step 2: Make executable and run**

```bash
chmod +x /home/smart/mounts/claude-code-server/scripts/server/commands/verify.sh
bash /home/smart/mounts/claude-code-server/scripts/server/commands/verify.sh
```

Expected: colored output showing which components are installed.

- [ ] **Step 3: Test via dispatcher**

```bash
bash /home/smart/mounts/claude-code-server/scripts/server/claude-server verify
```

Expected: same output.

- [ ] **Step 4: commit**

```bash
cd /home/smart/mounts/claude-code-server
git add scripts/server/commands/verify.sh
git commit -m "feat: add claude-server verify command"
```

---

## Task 4: `commands/status.sh`

**Files:**
- Create: `scripts/server/commands/status.sh`

- [ ] **Step 1: Write status.sh file**

```bash
#!/bin/bash
# commands/status.sh - show active sessions and usage stats
# Usage: claude-server status [--days N]

DAYS="${2:-7}"
LOG_FILE="/var/log/claude-activity.jsonl"
ACTIVE_DIR="/var/run/claude-active"

BOLD='\033[1m'
GREEN='\033[0;32m'
GRAY='\033[0;37m'
NC='\033[0m'

echo ""
echo -e "${BOLD}=== Claude Server Status ===${NC}"
echo ""

# --- Active sessions ---
echo -e "${BOLD}Active sessions${NC}"
ACTIVE_FILES=("$ACTIVE_DIR"/*.active)
if [ -e "${ACTIVE_FILES[0]}" ]; then
    for f in "${ACTIVE_FILES[@]}"; do
        base=$(basename "$f")
        user="${base%%.*}"
        pid="${base##*.}"; pid="${pid%.active}"
        if kill -0 "$pid" 2>/dev/null; then
            echo "  $user  (pid $pid)"
        fi
    done
else
    echo -e "  ${GRAY}none${NC}"
fi

echo ""

# --- Prompt usage ---
if [ -f "$LOG_FILE" ]; then
    echo -e "${BOLD}Usage — last ${DAYS} days (prompts)${NC}"
    SINCE=$(date -d "-${DAYS} days" -Iseconds 2>/dev/null || date -v-${DAYS}d -Iseconds 2>/dev/null)
    jq -r --arg s "$SINCE" \
        'select(.timestamp >= $s) | select(.event=="PROMPT") | .user' \
        "$LOG_FILE" 2>/dev/null | \
    awk '{count[$1]++; last[$1]=$0} END {
        for(u in count) printf "  %-16s %4d prompts\n", u, count[u]
    }' | sort -t' ' -k2 -rn
    echo ""
fi

# --- Token stats from log ---
if [ -f "$LOG_FILE" ] && grep -qE '"event":"STATS"|"event": "STATS"' "$LOG_FILE" 2>/dev/null; then
    echo -e "${BOLD}Token usage (cumulative from stats cache)${NC}"
    grep -E '"event":"STATS"|"event": "STATS"' "$LOG_FILE" | python3 -c "
import json, sys
users = {}
for line in sys.stdin:
    try:
        d = json.loads(line)
        users[d['user']] = d
    except Exception:
        pass

total_cost = 0.0
rows = []
for u, d in users.items():
    o  = d.get('outputTokens', 0)
    cr = d.get('cacheReadInputTokens', 0)
    cw = d.get('cacheCreationInputTokens', 0)
    cost = (o/1e6)*15 + (cr/1e6)*0.3 + (cw/1e6)*3.75
    total_cost += cost
    fmt = lambda n: f'{n/1e6:.1f}M' if n >= 1e6 else f'{n/1e3:.0f}K' if n >= 1e3 else str(n)
    rows.append((u, fmt(o), cost, d.get('totalMessages', 0)))

rows.sort(key=lambda r: r[2], reverse=True)
print(f\"  {'User':<16} {'Output':>7}  {'Cost USD':>9}  {'Messages':>9}\")
print('  ' + '-'*46)
for u, o, cost, msgs in rows:
    print(f'  {u:<16} {o:>7}  \${cost:>8.2f}  {msgs:>9,}')
print('  ' + '-'*46)
print(f\"  {'TOTAL':<16} {'':>7}  \${total_cost:>8.2f}\")
" 2>/dev/null
    echo ""
fi
```

- [ ] **Step 2: Make executable and test**

```bash
chmod +x /home/smart/mounts/claude-code-server/scripts/server/commands/status.sh
bash /home/smart/mounts/claude-code-server/scripts/server/claude-server status
```

Expected: active sessions and usage displayed.

- [ ] **Step 3: commit**

```bash
cd /home/smart/mounts/claude-code-server
git add scripts/server/commands/status.sh
git commit -m "feat: add claude-server status command"
```

---

## Task 5: `commands/add-user.sh`

**Files:**
- Create: `scripts/server/commands/add-user.sh`

- [ ] **Step 1: Write add-user.sh file**

```bash
#!/bin/bash
# commands/add-user.sh - add a new developer user
# Usage: sudo claude-server add-user <username> [--no-password-change]

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}+${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
fail() { echo -e "  ${RED}x${NC} $1"; exit 1; }
step() { echo -e "\n${BOLD}=== $1 ===${NC}"; }

[ "$EUID" -ne 0 ] && fail "must run as root: sudo claude-server add-user <username>"

USERNAME="${1:-}"
NO_PASSWD_CHANGE=false
shift 2>/dev/null || true
for arg in "$@"; do
    [ "$arg" = "--no-password-change" ] && NO_PASSWD_CHANGE=true
done

[ -z "$USERNAME" ] && { echo "Usage: sudo claude-server add-user <username> [--no-password-change]"; exit 1; }

echo ""
echo -e "${BOLD}Adding developer: $USERNAME${NC}"

step "1 - create user"
if id "$USERNAME" &>/dev/null; then
    ok "user $USERNAME already exists"
else
    useradd -m -s /bin/bash "$USERNAME"
    ok "user $USERNAME created"
    echo "  Set password for $USERNAME:"
    passwd "$USERNAME"
fi

step "2 - home directory"
mkdir -p "/home/$USERNAME/work"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"
chmod 700 "/home/$USERNAME"
ok "/home/$USERNAME/work ready (isolated)"

step "3 - claude-mount"
mkdir -p "/home/$USERNAME/.local/bin"
if [ -f /usr/local/lib/claude-mount ]; then
    install -m 755 /usr/local/lib/claude-mount "/home/$USERNAME/.local/bin/claude-mount"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.local/bin/claude-mount"
    ok "~/.local/bin/claude-mount installed"
else
    warn "/usr/local/lib/claude-mount not found — run: sudo claude-server install"
fi

if [ -f /usr/local/bin/claude-git-setup ]; then
    install -m 755 /usr/local/bin/claude-git-setup "/home/$USERNAME/.local/bin/claude-git-setup"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.local/bin/claude-git-setup"
    ok "~/.local/bin/claude-git-setup installed"
fi

step "4 - Claude settings + hooks"
# NOTE: if hooks change, this template must be updated too (see CLAUDE.md)
mkdir -p "/home/$USERNAME/.claude"
cat > "/home/$USERNAME/.claude/settings.json" << 'SETTINGS'
{
  "theme": "dark",
  "model": "claude-sonnet-4-6",
  "effortLevel": "low",
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-logout-block"}]}],
    "PreToolUse":       [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-pre"}]}],
    "Stop":             [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-stop"}]}]
  }
}
SETTINGS
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.claude"
ok "~/.claude/settings.json written"

step "5 - SSH"
mkdir -p "/home/$USERNAME/.ssh"
touch "/home/$USERNAME/.ssh/authorized_keys"
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
chmod 700 "/home/$USERNAME/.ssh"
chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
ok "~/.ssh ready"

step "6 - auto-mount in .bashrc"
BASHRC="/home/$USERNAME/.bashrc"
touch "$BASHRC"
if ! grep -q "claude-automount" "$BASHRC"; then
    cat >> "$BASHRC" << 'HOOK'

# --- Claude Code auto-mount ---
case $- in
  *i*)
    if [ -z "$CLAUDE_AUTOMOUNT_DONE" ] && [ -x /usr/local/bin/claude-automount ]; then
        export CLAUDE_AUTOMOUNT_DONE=1
        /usr/local/bin/claude-automount 2>/dev/null
        [ "$PWD" = "$HOME" ] && [ -d "$HOME/work" ] && cd "$HOME/work"
    fi
    ;;
esac
# --- end Claude Code auto-mount ---
HOOK
    ok "auto-mount added to .bashrc"
else
    ok "auto-mount already in .bashrc"
fi
chown "$USERNAME:$USERNAME" "$BASHRC"

step "7 - first-login password change"
if $NO_PASSWD_CHANGE; then
    warn "skipped (--no-password-change)"
else
    chage -d 0 "$USERNAME"
    ok "$USERNAME must change password on first login"
fi

echo ""
echo -e "${GREEN}${BOLD}Done.${NC} User $USERNAME is ready."
echo "  Next: give them SSH access to connect"
echo "  Verify: claude-server verify"
echo ""
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /home/smart/mounts/claude-code-server/scripts/server/commands/add-user.sh
```

- [ ] **Step 3: Test without username**

```bash
bash /home/smart/mounts/claude-code-server/scripts/server/claude-server add-user 2>&1
echo "exit: $?"
```

Expected: usage message, exit code 1.

- [ ] **Step 4: Test without root**

```bash
bash /home/smart/mounts/claude-code-server/scripts/server/commands/add-user.sh testverify 2>&1
echo "exit: $?"
```

Expected: `must run as root`, exit code 1.

- [ ] **Step 5: commit**

```bash
cd /home/smart/mounts/claude-code-server
git add scripts/server/commands/add-user.sh
git commit -m "feat: add claude-server add-user command"
```

---

## Task 6: `commands/install.sh`

**Files:**
- Create: `scripts/server/commands/install.sh`

- [ ] **Step 1: Write install.sh file**

```bash
#!/bin/bash
# commands/install.sh - full Claude Code Server install
# Usage: sudo claude-server install
# Idempotent — safe to run again after updates.

set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SERVER_DIR="$REPO_DIR/scripts/server"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}+${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
fail() { echo -e "  ${RED}x${NC} $1"; exit 1; }
step() { echo -e "\n${BOLD}=== $1 ===${NC}"; }

[ "$EUID" -ne 0 ] && fail "must run as root: sudo claude-server install"

echo ""
echo -e "${BOLD}Claude Code Server — Full Install${NC}"
echo "repo: $REPO_DIR"
echo ""

step "1 - system update + prerequisites"
apt-get update -q
apt-get install -y -q sshfs curl git python3 jq
ok "prerequisites installed"
if ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
    echo "user_allow_other" >> /etc/fuse.conf
    ok "user_allow_other enabled in /etc/fuse.conf"
fi

step "2 - Node.js LTS"
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - 2>/dev/null
    apt-get install -y -q nodejs
    ok "Node.js $(node --version) installed"
else
    ok "Node.js already installed: $(node --version)"
fi

step "3 - Claude Code CLI"
npm install -g @anthropic-ai/claude-code --quiet 2>/dev/null || \
    npm install -g @anthropic-ai/claude-code 2>&1 | tail -3
CLAUDE_BIN=$(find /usr/lib/node_modules /usr/local/lib/node_modules \
    -name "claude.exe" -path "*claude-code*" 2>/dev/null | head -1)
[ -z "$CLAUDE_BIN" ] && fail "Claude binary not found after install"
ln -sf "$CLAUDE_BIN" /usr/local/bin/claude-real
ok "claude-real → $CLAUDE_BIN"
/usr/local/bin/claude-real --version >/dev/null && ok "claude-real --version works"

step "4 - wrapper + hooks"
[ -f "$SERVER_DIR/claude-wrapper.sh" ] && \
    install -m 755 "$SERVER_DIR/claude-wrapper.sh" /usr/local/bin/claude && \
    ok "claude wrapper installed" || warn "claude-wrapper.sh not found"

for hook in claude-hook-logout-block claude-hook-pre claude-hook-stop; do
    src="$SERVER_DIR/hooks/${hook}.sh"
    [ -f "$src" ] && install -m 755 "$src" "/usr/local/bin/$hook" && ok "$hook installed" \
        || warn "$hook not found in hooks/"
done

step "5 - helper scripts"
[ -f "$SERVER_DIR/claude-automount.sh" ] && \
    install -m 755 "$SERVER_DIR/claude-automount.sh" /usr/local/bin/claude-automount && \
    ok "claude-automount installed"
[ -f "$SERVER_DIR/claude-mount.sh" ] && \
    install -m 644 "$SERVER_DIR/claude-mount.sh" /usr/local/lib/claude-mount && \
    ok "claude-mount installed to /usr/local/lib/"
[ -f "$SERVER_DIR/claude-git-setup.sh" ] && \
    install -m 755 "$SERVER_DIR/claude-git-setup.sh" /usr/local/bin/claude-git-setup && \
    ok "claude-git-setup installed"
[ -f "$SERVER_DIR/designer-start.sh" ] && \
    install -m 755 "$SERVER_DIR/designer-start.sh" /usr/local/bin/designer-start && \
    ok "designer-start installed"

step "6 - config + runtime dirs"
[ -f "$SERVER_DIR/claude-limits.conf" ] && \
    install -m 644 "$SERVER_DIR/claude-limits.conf" /etc/claude-limits.conf && \
    ok "/etc/claude-limits.conf installed"
mkdir -p /var/run/claude-active
chmod 1777 /var/run/claude-active
ok "/var/run/claude-active ready"
touch /var/log/claude-activity.jsonl
chmod 666 /var/log/claude-activity.jsonl
ok "/var/log/claude-activity.jsonl ready"

step "7 - SSH forwarding"
if grep -qiE "^[[:space:]]*AllowTcpForwarding[[:space:]]+no" /etc/ssh/sshd_config 2>/dev/null; then
    sed -i -E 's/^[[:space:]]*AllowTcpForwarding[[:space:]]+no/AllowTcpForwarding yes/I' /etc/ssh/sshd_config
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    ok "AllowTcpForwarding enabled"
else
    ok "AllowTcpForwarding: ok"
fi

step "8 - designer dependencies"
for pkg in xvfb x11vnc fluxbox autocutsel; do
    dpkg -l "$pkg" 2>/dev/null | grep -q '^ii' && ok "$pkg: already installed" || {
        apt-get install -y -q "$pkg" && ok "$pkg installed"
    }
done

# websockify
if ! command -v websockify &>/dev/null; then
    apt-get install -y -q python3-websockify 2>/dev/null || \
        pip3 install websockify --quiet 2>/dev/null || \
        warn "websockify: install manually"
else
    ok "websockify: installed"
fi

# noVNC
if [ ! -d /opt/novnc ]; then
    if command -v novnc &>/dev/null; then
        NOVNC_PATH=$(dirname "$(command -v novnc)")/../share/novnc
        [ -d "$NOVNC_PATH" ] && ln -sf "$(realpath "$NOVNC_PATH")" /opt/novnc && ok "noVNC → /opt/novnc"
    else
        git clone --depth=1 https://github.com/novnc/noVNC.git /opt/novnc 2>/dev/null && ok "noVNC cloned"
    fi
else
    ok "noVNC: /opt/novnc exists"
fi

# Chrome
if ! command -v google-chrome-stable &>/dev/null; then
    curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        -o /tmp/chrome.deb 2>/dev/null
    apt-get install -y /tmp/chrome.deb 2>/dev/null && ok "Chrome installed" || \
        warn "Chrome install failed - install manually"
    rm -f /tmp/chrome.deb
else
    ok "Chrome: $(google-chrome-stable --version 2>/dev/null | head -1)"
fi

step "9 - designer user"
if ! id designer &>/dev/null; then
    useradd -m -s /bin/bash designer
    passwd -l designer
    ok "designer user created (password locked)"
else
    ok "designer user: exists"
fi
mkdir -p /opt/chrome-design-profile /home/designer/.designer /home/designer/.local/share
chown -R designer:designer /opt/chrome-design-profile /home/designer/.designer /home/designer/.local
ok "designer directories ready"

step "10 - admin user: smart"
if ! id smart &>/dev/null; then
    useradd -m -s /bin/bash -G sudo smart
    echo "  Set password for smart:"
    passwd smart
    ok "user smart created"
else
    ok "user smart: exists"
fi
chmod 755 /home/smart

step "11 - install claude-server CLI"
install -m 755 "$SERVER_DIR/claude-server" /usr/local/bin/claude-server
# install commands dir alongside
mkdir -p /usr/local/lib/claude-server
for cmd in "$SERVER_DIR/commands/"*.sh; do
    install -m 755 "$cmd" /usr/local/lib/claude-server/
done
# patch dispatcher to use /usr/local/lib/claude-server
sed -i "s|COMMANDS_DIR=.*|COMMANDS_DIR=/usr/local/lib/claude-server|" /usr/local/bin/claude-server || true
ok "claude-server installed to /usr/local/bin/claude-server"

echo ""
echo -e "${GREEN}${BOLD}========================================${NC}"
echo -e "${GREEN}${BOLD}  Install complete!${NC}"
echo -e "${GREEN}${BOLD}========================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Set auth token (run once on a laptop with browser):"
echo "       claude setup-token"
echo "     Then on server as root:"
echo "       echo 'export CLAUDE_CODE_OAUTH_TOKEN=<token>' > /etc/profile.d/claude-auth.sh"
echo "       chmod 644 /etc/profile.d/claude-auth.sh"
echo "       echo 'CLAUDE_CODE_OAUTH_TOKEN=<token>' >> /etc/environment"
echo ""
echo "  2. Add developers:"
echo "       sudo claude-server add-user <username>"
echo ""
echo "  3. Verify:"
echo "       claude-server verify"
echo ""
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /home/smart/mounts/claude-code-server/scripts/server/commands/install.sh
```

- [ ] **Step 3: Test without root**

```bash
bash /home/smart/mounts/claude-code-server/scripts/server/commands/install.sh 2>&1 | head -3
echo "exit: $?"
```

Expected: `must run as root`, exit code 1.

- [ ] **Step 4: commit**

```bash
cd /home/smart/mounts/claude-code-server
git add scripts/server/commands/install.sh
git commit -m "feat: add claude-server install command"
```

---

## Task 7: deprecation notices + docs update

**Files:**
- Modify: `scripts/server/server-setup.sh`
- Modify: `scripts/server/setup-new-user.sh`
- Modify: `docs/claude-design.md`

- [ ] **Step 1: Add deprecation to server-setup.sh**

After `#!/bin/bash` add this (before anything else):

```bash
echo ""
echo "  DEPRECATED: use 'sudo claude-server install' instead."
echo "  This script is kept for reference only."
echo "  Press Ctrl+C to cancel, or Enter to continue anyway."
read -r _
```

- [ ] **Step 2: Add deprecation to setup-new-user.sh**

```bash
echo ""
echo "  DEPRECATED: use 'sudo claude-server add-user <username>' instead."
echo "  Press Ctrl+C to cancel, or Enter to continue anyway."
read -r _
```

- [ ] **Step 3: Add claude-server commands to docs/claude-design.md**

Find the "Management commands" section and add:

```markdown
## Server management with claude-server

```bash
# Install on a new server
git clone <repo> && sudo bash scripts/server/claude-server install

# Add a developer
sudo claude-server add-user amir

# Check server health
claude-server verify

# Session and usage status
claude-server status
```
```

- [ ] **Step 4: commit**

```bash
cd /home/smart/mounts/claude-code-server
git add scripts/server/server-setup.sh scripts/server/setup-new-user.sh docs/claude-design.md
git commit -m "docs: add deprecation notices and claude-server docs"
```

---

## Task 8: Final end-to-end test

- [ ] **Step 1: Test all commands from dispatcher**

```bash
bash /home/smart/mounts/claude-code-server/scripts/server/claude-server --help
bash /home/smart/mounts/claude-code-server/scripts/server/claude-server --version
bash /home/smart/mounts/claude-code-server/scripts/server/claude-server verify
bash /home/smart/mounts/claude-code-server/scripts/server/claude-server status
```

Expected: all run without error.

- [ ] **Step 2: Test unknown command**

```bash
bash /home/smart/mounts/claude-code-server/scripts/server/claude-server xyz 2>&1
echo "exit: $?"
```

Expected: `Unknown command: xyz`, exit code 1.

- [ ] **Step 3: verify on real server**

```bash
claude-server verify 2>/dev/null || bash /home/smart/mounts/claude-code-server/scripts/server/claude-server verify
```

Expected: all system components ok.

- [ ] **Step 4: final commit**

```bash
cd /home/smart/mounts/claude-code-server
git add -A
git commit -m "feat: complete claude-server CLI implementation"
```
