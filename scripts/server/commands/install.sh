#!/bin/bash
# commands/install.sh - full Claude Code Server install from scratch
# Usage: sudo claude-server install
# Idempotent — safe to run again after updates to hooks or scripts.

set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# In repo mode: commands/ is inside scripts/server/
# In installed mode: /usr/local/lib/claude-server/ — repo must be cloned nearby
REPO_DIR="${CLAUDE_SERVER_REPO:-$(cd "$SCRIPT_DIR/../../.." && pwd 2>/dev/null)}"
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

# ─── Step 1: System prerequisites ───────────────────────────────────────────
step "1 - system update + prerequisites"
apt-get update -q
apt-get install -y -q sshfs curl git python3 jq
ok "prerequisites installed"

if ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
    echo "user_allow_other" >> /etc/fuse.conf
    ok "user_allow_other enabled in /etc/fuse.conf"
else
    ok "user_allow_other: already set"
fi

# ─── Step 2: Node.js ─────────────────────────────────────────────────────────
step "2 - Node.js LTS"
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - 2>/dev/null
    apt-get install -y -q nodejs
    ok "Node.js $(node --version) installed"
else
    ok "Node.js already installed: $(node --version)"
fi

# ─── Step 3: Claude Code CLI ─────────────────────────────────────────────────
step "3 - Claude Code CLI"
npm install -g @anthropic-ai/claude-code --quiet 2>/dev/null || \
    npm install -g @anthropic-ai/claude-code 2>&1 | tail -5

CLAUDE_BIN=$(find /usr/lib/node_modules /usr/local/lib/node_modules \
    -name "claude.exe" -path "*claude-code*" 2>/dev/null | head -1)
[ -z "$CLAUDE_BIN" ] && fail "Claude binary not found after install"
ln -sf "$CLAUDE_BIN" /usr/local/bin/claude-real
ok "claude-real → $CLAUDE_BIN"
/usr/local/bin/claude-real --version >/dev/null && ok "claude-real works"

# ─── Step 4: wrapper + hooks ─────────────────────────────────────────────────
step "4 - wrapper + hooks"

if [ -f "$SERVER_DIR/claude-wrapper.sh" ]; then
    install -m 755 "$SERVER_DIR/claude-wrapper.sh" /usr/local/bin/claude
    ok "claude wrapper → /usr/local/bin/claude"
else
    warn "claude-wrapper.sh not found — using claude-real directly"
    [ -f /usr/local/bin/claude-real ] && ln -sf /usr/local/bin/claude-real /usr/local/bin/claude
fi

for hook in claude-hook-logout-block claude-hook-pre claude-hook-stop; do
    src="$SERVER_DIR/hooks/${hook}.sh"
    if [ -f "$src" ]; then
        install -m 755 "$src" "/usr/local/bin/${hook}.sh"
        install -m 755 "$src" "/usr/local/bin/${hook}"
        ok "$hook → /usr/local/bin/ (with and without .sh)"
    else
        warn "$hook not found in hooks/"
    fi
done

# ─── Step 5: helper scripts ──────────────────────────────────────────────────
step "5 - helper scripts"

if [ -f "$SERVER_DIR/claude-automount.sh" ]; then
    install -m 755 "$SERVER_DIR/claude-automount.sh" /usr/local/bin/claude-automount
    ok "claude-automount → /usr/local/bin/"
fi
if [ -f "$SERVER_DIR/claude-mount.sh" ]; then
    install -m 644 "$SERVER_DIR/claude-mount.sh" /usr/local/lib/claude-mount
    ok "claude-mount → /usr/local/lib/claude-mount"
fi
if [ -f "$SERVER_DIR/claude-watchdog.sh" ]; then
    install -m 755 "$SERVER_DIR/claude-watchdog.sh" /usr/local/bin/claude-watchdog
    ok "claude-watchdog → /usr/local/bin/"
fi
if [ -f "$SERVER_DIR/claude-git-setup.sh" ]; then
    install -m 755 "$SERVER_DIR/claude-git-setup.sh" /usr/local/bin/claude-git-setup
    ok "claude-git-setup → /usr/local/bin/"
fi
if [ -f "$SERVER_DIR/designer-start.sh" ]; then
    install -m 755 "$SERVER_DIR/designer-start.sh" /usr/local/bin/designer-start
    ok "designer-start → /usr/local/bin/"
fi
if [ -f "$SERVER_DIR/check-tokens.py" ]; then
    install -m 755 "$SERVER_DIR/check-tokens.py" /usr/local/bin/claude-check-tokens
    ok "claude-check-tokens → /usr/local/bin/"
fi

# ─── Step 6: config + runtime dirs ──────────────────────────────────────────
step "6 - config + runtime dirs"

if [ -f "$SERVER_DIR/claude-limits.conf" ]; then
    install -m 644 "$SERVER_DIR/claude-limits.conf" /etc/claude-limits.conf
    ok "/etc/claude-limits.conf installed"
fi

mkdir -p /var/run/claude-active
chmod 1777 /var/run/claude-active
ok "/var/run/claude-active ready (sticky 1777)"

touch /var/log/claude-activity.jsonl
chmod 666 /var/log/claude-activity.jsonl
ok "/var/log/claude-activity.jsonl ready"

# ─── Step 7: SSH forwarding ──────────────────────────────────────────────────
step "7 - SSH forwarding"

if grep -qiE "^[[:space:]]*AllowTcpForwarding[[:space:]]+no" /etc/ssh/sshd_config 2>/dev/null; then
    sed -i -E 's/^[[:space:]]*AllowTcpForwarding[[:space:]]+no/AllowTcpForwarding yes/I' /etc/ssh/sshd_config
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    ok "AllowTcpForwarding enabled"
else
    ok "AllowTcpForwarding: ok (default yes)"
fi

# ─── Step 8: designer dependencies ──────────────────────────────────────────
step "8 - designer dependencies (Xvfb, x11vnc, noVNC, Chrome)"

for pkg in xvfb x11vnc fluxbox autocutsel; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
        ok "$pkg: already installed"
    else
        apt-get install -y -q "$pkg" && ok "$pkg installed"
    fi
done

# websockify
if command -v websockify &>/dev/null; then
    ok "websockify: installed"
else
    apt-get install -y -q python3-websockify 2>/dev/null && ok "websockify installed" || \
    pip3 install websockify --quiet 2>/dev/null && ok "websockify installed via pip" || \
    warn "websockify: install manually (apt install python3-websockify)"
fi

# noVNC
if [ ! -d /opt/novnc ]; then
    NOVNC_SHARE=$(find /usr /opt -name "vnc.html" 2>/dev/null | head -1 | xargs -r dirname 2>/dev/null || true)
    if [ -n "$NOVNC_SHARE" ]; then
        ln -sf "$NOVNC_SHARE" /opt/novnc
        ok "noVNC → /opt/novnc (system)"
    else
        git clone --depth=1 https://github.com/novnc/noVNC.git /opt/novnc 2>/dev/null && ok "noVNC cloned to /opt/novnc" || \
        warn "noVNC: install manually (git clone https://github.com/novnc/noVNC.git /opt/novnc)"
    fi
else
    ok "noVNC: /opt/novnc exists"
fi

# Chrome
if command -v google-chrome-stable &>/dev/null; then
    ok "Chrome: $(google-chrome-stable --version 2>/dev/null | head -1)"
else
    curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        -o /tmp/chrome.deb 2>/dev/null && \
    apt-get install -y /tmp/chrome.deb 2>/dev/null && \
    ok "Chrome installed" || \
    warn "Chrome install failed — install manually"
    rm -f /tmp/chrome.deb
fi

# ─── Step 9: CodeGraph (code intelligence MCP) ──────────────────────────────
step "9 - CodeGraph"
if command -v codegraph &>/dev/null; then
    ok "CodeGraph: already installed ($(codegraph --version 2>/dev/null || echo 'ok'))"
else
    curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh
    ok "CodeGraph installed"
fi

# ─── Step 10: Headroom (context compression MCP) ─────────────────────────────
step "10 - Headroom"
if command -v headroom &>/dev/null; then
    ok "Headroom: already installed"
else
    pip3 install "headroom-ai[mcp]" --quiet && ok "headroom-ai[mcp] installed" || \
        warn "headroom-ai install failed — run manually: pip3 install 'headroom-ai[mcp]'"
fi

# ─── Step 10b: mcp-sqlserver ──────────────────────────────────────────────────
step "10b - mcp-sqlserver"
if command -v mcp-sqlserver &>/dev/null; then
    ok "mcp-sqlserver: already installed"
else
    npm install -g @bilims/mcp-sqlserver --quiet && ok "mcp-sqlserver installed" || \
        warn "mcp-sqlserver install failed — run manually: npm install -g @bilims/mcp-sqlserver"
fi

# ─── Step 11: designer user ───────────────────────────────────────────────────
step "11 - designer user"

if ! id designer &>/dev/null; then
    useradd -m -s /bin/bash designer
    passwd -l designer
    ok "designer user created (password locked)"
else
    ok "designer user: exists"
fi

mkdir -p /opt/chrome-design-profile/Default /home/designer/.designer /home/designer/.local/share
chown -R designer:designer /opt/chrome-design-profile /home/designer/.designer /home/designer/.local
chmod -R 755 /opt/chrome-design-profile

# Use Chrome managed policy so Chrome can never overwrite the download directory setting.
POLICY_DIR="/etc/opt/chrome/policies/managed"
POLICY_FILE="$POLICY_DIR/designer-download.json"
DOWNLOAD_PATH="/home/designer/mounts/laptop"
mkdir -p "$POLICY_DIR"
cat > "$POLICY_FILE" <<EOF
{
  "DownloadDirectory": "${DOWNLOAD_PATH}",
  "PromptForDownloadLocation": false
}
EOF
chmod 644 "$POLICY_FILE"
ok "Chrome managed policy → ${DOWNLOAD_PATH}"
ok "designer directories ready"

# ─── Step 10: admin user smart ───────────────────────────────────────────────
step "12 - admin user: smart"

if ! id smart &>/dev/null; then
    useradd -m -s /bin/bash -G sudo smart
    echo "  Set password for smart:"
    passwd smart
    ok "user smart created"
else
    ok "user smart: exists"
fi
chmod 755 /home/smart

# run full user setup for smart (idempotent)
bash "$SERVER_DIR/commands/add-user.sh" smart --no-password-change

# ─── Step 11: install claude-server CLI ──────────────────────────────────────
step "13 - install claude-server CLI"

install -m 755 "$SERVER_DIR/claude-server" /usr/local/bin/claude-server

mkdir -p /usr/local/lib/claude-server
for cmd_file in "$SERVER_DIR/commands/"*.sh; do
    [ -f "$cmd_file" ] || continue
    install -m 755 "$cmd_file" /usr/local/lib/claude-server/
done
ok "claude-server → /usr/local/bin/claude-server"
ok "commands → /usr/local/lib/claude-server/"

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}========================================${NC}"
echo -e "${GREEN}${BOLD}  Install complete!${NC}"
echo -e "${GREEN}${BOLD}========================================${NC}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Set Claude auth token:"
echo "     On a laptop with a browser: claude setup-token"
echo "     Then on this server as root:"
echo "       echo 'export CLAUDE_CODE_OAUTH_TOKEN=<token>' > /etc/profile.d/claude-auth.sh"
echo "       chmod 640 /etc/profile.d/claude-auth.sh"
echo "       chgrp sudo /etc/profile.d/claude-auth.sh 2>/dev/null || chgrp adm /etc/profile.d/claude-auth.sh 2>/dev/null || true"
echo "       echo 'CLAUDE_CODE_OAUTH_TOKEN=<token>' >> /etc/environment"
echo ""
echo "  2. Add developers:"
echo "       sudo claude-server add-user <username>"
echo ""
echo "  3. Verify:"
echo "       claude-server verify"
echo ""
