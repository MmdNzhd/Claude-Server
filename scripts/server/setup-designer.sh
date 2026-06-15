#!/bin/bash
# setup-designer.sh - setup the shared "designer" user for Claude Design.
# Run as ROOT on server. Only needs to run ONCE.
# Usage: sudo bash setup-designer.sh [--add-key <pubkey>]
#
# Creates a single shared "designer" user. Multiple designers connect to it
# with their own SSH keys. Only one can use the screen at a time — a new
# connection kicks the previous one.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  + $1${NC}"; }
warn() { echo -e "${YELLOW}  ! $1${NC}"; }
fail() { echo -e "${RED}  x $1${NC}"; exit 1; }
step() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

[ "$EUID" -ne 0 ] && fail "must run as root"

USERNAME="designer"
ADD_KEY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --add-key) ADD_KEY="$2"; shift 2 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

# Check deps
for bin in Xvfb x11vnc websockify google-chrome-stable fluxbox autocutsel; do
    command -v "$bin" &>/dev/null || fail "$bin not found - run install-designer-deps.sh first"
done

step "1 - create user: $USERNAME"
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USERNAME"
    # lock password - SSH key only
    passwd -l "$USERNAME"
    ok "user $USERNAME created (password locked)"
else
    ok "user $USERNAME already exists"
fi

step "2 - shared Chrome profile"
mkdir -p /opt/chrome-design-profile
chown -R $USERNAME:$USERNAME /opt/chrome-design-profile
chmod -R 755 /opt/chrome-design-profile
ok "/opt/chrome-design-profile ready"

step "3 - session directory"
mkdir -p /home/$USERNAME/.designer
chown -R $USERNAME:$USERNAME /home/$USERNAME/.designer
ok "~/.designer ready"

step "3b - .local/share (required by Chrome NSS / GPU process)"
mkdir -p /home/$USERNAME/.local/share/pki/nssdb
chown -R $USERNAME:$USERNAME /home/$USERNAME/.local
ok "~/.local/share ready"

step "4 - install designer-start"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/designer-start.sh" ]; then
    install -m 755 "$SCRIPT_DIR/designer-start.sh" /usr/local/bin/designer-start
    ok "designer-start installed"
else
    warn "designer-start.sh not found next to setup-designer.sh"
fi

step "5 - SSH"
mkdir -p /home/$USERNAME/.ssh
touch /home/$USERNAME/.ssh/authorized_keys
chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
chmod 700 /home/$USERNAME/.ssh
chmod 600 /home/$USERNAME/.ssh/authorized_keys
ok "~/.ssh ready"

if [ -n "$ADD_KEY" ]; then
    if ! grep -qF "$ADD_KEY" /home/$USERNAME/.ssh/authorized_keys; then
        echo "$ADD_KEY" >> /home/$USERNAME/.ssh/authorized_keys
        ok "SSH key added"
    else
        ok "SSH key already present"
    fi
fi

UID_NUM=$(id -u "$USERNAME")
NOVNC_PORT=$((26000 + UID_NUM))

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  designer user is ready!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "  To add a designer's SSH key:"
echo "    sudo bash setup-designer.sh --add-key \"<pubkey>\""
echo ""
echo "  Or manually:"
echo "    cat >> /home/designer/.ssh/authorized_keys"
echo ""
echo "  noVNC port: $NOVNC_PORT  (tunneled via SSH to localhost:6080)"
echo ""
