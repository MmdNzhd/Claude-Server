#!/bin/bash
# server-setup.sh — full Claude Code Server install from scratch
# Run as root on Ubuntu 24
# Usage: bash server-setup.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  + $1${NC}"; }
warn() { echo -e "${YELLOW}  ! $1${NC}"; }
fail() { echo -e "${RED}  x $1${NC}"; exit 1; }
step() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

[ "$EUID" -ne 0 ] && fail "must run as root: sudo bash server-setup.sh"

# -----------------------------------------
step "1 - system update"
# -----------------------------------------
apt-get update -q
apt-get upgrade -y -q
ok "system updated"

# -----------------------------------------
step "2 - install prerequisites"
# -----------------------------------------
apt-get install -y -q sshfs curl git
ok "sshfs, curl, git installed"

# enable user_allow_other for SSHFS
if ! grep -q "^user_allow_other" /etc/fuse.conf; then
    echo "user_allow_other" >> /etc/fuse.conf
    ok "user_allow_other enabled in /etc/fuse.conf"
else
    ok "user_allow_other already enabled"
fi

# -----------------------------------------
step "3 - install Node.js LTS"
# -----------------------------------------
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y -q nodejs
    ok "Node.js $(node --version) installed"
else
    ok "Node.js already installed: $(node --version)"
fi

# -----------------------------------------
step "4 - install Claude Code"
# -----------------------------------------
npm install -g @anthropic-ai/claude-code --quiet

# find the real path and symlink into the global PATH
CLAUDE_BIN=$(npm root -g)/@anthropic-ai/claude-code/cli.js
if [ -f "$CLAUDE_BIN" ]; then
    ln -sf "$CLAUDE_BIN" /usr/local/bin/claude
    chmod 755 /usr/local/bin/claude
    ok "Claude Code installed - /usr/local/bin/claude"
else
    # fallback
    CLAUDE_BIN=$(find /usr -name "claude" -type f 2>/dev/null | head -1)
    [ -z "$CLAUDE_BIN" ] && fail "Claude binary not found"
    ln -sf "$CLAUDE_BIN" /usr/local/bin/claude
    ok "Claude Code installed - $CLAUDE_BIN"
fi

claude --version && ok "claude --version works"

# -----------------------------------------
step "5 - create shared structure"
# -----------------------------------------
mkdir -p /etc/claude-shared
chmod 755 /etc/claude-shared
ok "/etc/claude-shared ready"

# -----------------------------------------
step "5.5 - install claude-automount + configure SSH forwarding"
# -----------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/claude-automount.sh" ]; then
    install -m 755 "$SCRIPT_DIR/claude-automount.sh" /usr/local/bin/claude-automount
    ok "claude-automount installed in /usr/local/bin/"
else
    warn "claude-automount.sh not found next to this script - install manually: install -m 755 claude-automount.sh /usr/local/bin/claude-automount"
fi

# reverse tunnel needs TCP forwarding enabled in sshd (default is yes)
if grep -qiE "^[[:space:]]*AllowTcpForwarding[[:space:]]+no" /etc/ssh/sshd_config; then
    sed -i -E 's/^[[:space:]]*AllowTcpForwarding[[:space:]]+no/AllowTcpForwarding yes/I' /etc/ssh/sshd_config
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    ok "AllowTcpForwarding enabled"
else
    ok "AllowTcpForwarding is fine (default yes)"
fi

# -----------------------------------------
step "6 - create admin user: smart"
# -----------------------------------------
if ! id smart &>/dev/null; then
    useradd -m -s /bin/bash -G sudo smart
    echo ""
    warn "set a password for smart:"
    passwd smart
else
    ok "user smart already exists"
fi

# make sure permissions are correct
chown -R smart:smart /home/smart
chmod 755 /home/smart
mkdir -p /home/smart/work
ok "user smart ready"

# -----------------------------------------
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  base install complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "Next step - Claude login (must be done as user smart):"
echo ""
echo "  su - smart"
echo "  claude"
echo ""
echo "After login, share the credentials:"
echo "  (as root)"
echo "  cp /home/smart/.claude/.credentials.json /etc/claude-shared/credentials.json"
echo "  chmod 644 /etc/claude-shared/credentials.json"
echo "  rm /home/smart/.claude/.credentials.json"
echo "  ln -sf /etc/claude-shared/credentials.json /home/smart/.claude/.credentials.json"
echo ""
echo "Then to add each user:"
echo "  bash setup-new-user.sh <username>"
echo ""
