#!/bin/bash
# server-setup.sh - full Claude Code Server install from scratch
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

step "1 - system update"
apt-get update -q
apt-get upgrade -y -q
ok "system updated"

step "2 - install prerequisites"
apt-get install -y -q sshfs curl git
ok "sshfs, curl, git installed"

if ! grep -q "^user_allow_other" /etc/fuse.conf; then
    echo "user_allow_other" >> /etc/fuse.conf
    ok "user_allow_other enabled in /etc/fuse.conf"
else
    ok "user_allow_other already enabled"
fi

step "3 - install Node.js LTS"
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y -q nodejs
    ok "Node.js $(node --version) installed"
else
    ok "Node.js already installed: $(node --version)"
fi

step "4 - install Claude Code"
npm install -g @anthropic-ai/claude-code --quiet

CLAUDE_BIN=$(npm root -g)/@anthropic-ai/claude-code/bin/claude.exe
if [ ! -f "$CLAUDE_BIN" ]; then
    CLAUDE_BIN=$(find /usr/lib/node_modules /usr/local/lib/node_modules \
        -name "claude.exe" -path "*claude-code*" 2>/dev/null | head -1)
fi
[ -z "$CLAUDE_BIN" ] && fail "Claude binary not found (looked for bin/claude.exe)"
ln -sf "$CLAUDE_BIN" /usr/local/bin/claude-real
ok "Claude Code installed - $CLAUDE_BIN"
/usr/local/bin/claude-real --version && ok "claude-real --version works"

step "5 - create shared structure"
mkdir -p /etc/claude-shared
chmod 755 /etc/claude-shared
ok "/etc/claude-shared ready"

# Install wrapper + limits config
if [ -f "$SCRIPT_DIR/claude-wrapper.sh" ]; then
    install -m 755 "$SCRIPT_DIR/claude-wrapper.sh" /usr/local/bin/claude
    ok "claude wrapper installed at /usr/local/bin/claude"
else
    warn "claude-wrapper.sh not found - claude-real symlink will be used directly"
    [ -f /usr/local/bin/claude-real ] && ln -sf /usr/local/bin/claude-real /usr/local/bin/claude
fi
if [ -f "$SCRIPT_DIR/claude-limits.conf" ]; then
    install -m 644 "$SCRIPT_DIR/claude-limits.conf" /etc/claude-limits.conf
    ok "claude-limits.conf installed at /etc/claude-limits.conf"
else
    warn "claude-limits.conf not found - default limit of 2 sessions will apply"
fi
mkdir -p /var/run/claude-active
chmod 1777 /var/run/claude-active
ok "/var/run/claude-active ready"

step "5.5 - install server scripts + configure SSH forwarding"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$SCRIPT_DIR/claude-automount.sh" ]; then
    install -m 755 "$SCRIPT_DIR/claude-automount.sh" /usr/local/bin/claude-automount
    ok "claude-automount installed in /usr/local/bin/"
else
    warn "claude-automount.sh not found - install manually"
fi

if [ -f "$SCRIPT_DIR/claude-mount.sh" ]; then
    install -m 644 "$SCRIPT_DIR/claude-mount.sh" /usr/local/lib/claude-mount
    ok "claude-mount installed in /usr/local/lib/"
else
    warn "claude-mount.sh not found - install manually"
fi

if [ -f "$SCRIPT_DIR/claude-git-setup.sh" ]; then
    install -m 755 "$SCRIPT_DIR/claude-git-setup.sh" /usr/local/bin/claude-git-setup
    ok "claude-git-setup installed in /usr/local/bin/"
else
    warn "claude-git-setup.sh not found - install manually"
fi

for hook in claude-hook-logout-block.sh claude-hook-pre.sh claude-hook-stop.sh; do
    src="$SCRIPT_DIR/hooks/$hook"
    dst="/usr/local/bin/${hook%.sh}"
    if [ -f "$src" ]; then
        install -m 755 "$src" "$dst"
        ok "${hook%.sh} installed in /usr/local/bin/"
    else
        warn "$hook not found in hooks/"
    fi
done

if grep -qiE "^[[:space:]]*AllowTcpForwarding[[:space:]]+no" /etc/ssh/sshd_config; then
    sed -i -E 's/^[[:space:]]*AllowTcpForwarding[[:space:]]+no/AllowTcpForwarding yes/I' /etc/ssh/sshd_config
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
    ok "AllowTcpForwarding enabled"
else
    ok "AllowTcpForwarding is fine (default yes)"
fi

step "6 - create admin user: smart"
if ! id smart &>/dev/null; then
    useradd -m -s /bin/bash -G sudo smart
    echo ""
    warn "set a password for smart:"
    passwd smart
else
    ok "user smart already exists"
fi
chown -R smart:smart /home/smart
chmod 755 /home/smart
mkdir -p /home/smart/work
ok "user smart ready"

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  base install complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "Next step - set up long-term auth token:"
echo ""
echo "  1. On a laptop with a browser: claude setup-token"
echo "  2. Copy the token, then on server as root:"
echo "     echo 'export CLAUDE_CODE_OAUTH_TOKEN=<token>' > /etc/profile.d/claude-auth.sh"
echo "     chmod 644 /etc/profile.d/claude-auth.sh"
echo "     echo 'CLAUDE_CODE_OAUTH_TOKEN=<token>' >> /etc/environment"
echo "  NOTE: /etc/environment is required for VSCode Remote SSH (non-login shell)."
echo ""
echo "Then add users:"
echo "  bash setup-new-user.sh <username>"
echo ""
