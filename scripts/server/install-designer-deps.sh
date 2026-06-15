#!/bin/bash
# install-designer-deps.sh - install Xvfb, x11vnc, noVNC, Chromium on Ubuntu 24.
# Run as ROOT once, before creating any designer users.
# Usage: sudo bash install-designer-deps.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  + $1${NC}"; }
warn() { echo -e "${YELLOW}  ! $1${NC}"; }
fail() { echo -e "${RED}  x $1${NC}"; exit 1; }
step() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

[ "$EUID" -ne 0 ] && fail "must run as root: sudo bash install-designer-deps.sh"

step "1 - system update"
apt-get update -q
ok "updated"

step "2 - install Xvfb + x11vnc + window manager + clipboard sync"
apt-get install -y -q xvfb x11vnc fluxbox autocutsel
ok "Xvfb $(Xvfb -version 2>&1 | head -1)"
ok "x11vnc $(x11vnc --version 2>&1 | head -1)"
ok "fluxbox + autocutsel installed"

step "3 - install noVNC + websockify"
apt-get install -y -q novnc python3-websockify
NOVNC_WEB=""
for d in /usr/share/novnc /usr/local/share/novnc; do
    [ -d "$d" ] && { NOVNC_WEB="$d"; break; }
done
[ -z "$NOVNC_WEB" ] && fail "noVNC web directory not found after install"
ok "noVNC at $NOVNC_WEB"

# Ensure vnc.html exists (some packages ship vnc_lite.html only)
if [ ! -f "$NOVNC_WEB/vnc.html" ] && [ -f "$NOVNC_WEB/vnc_lite.html" ]; then
    cp "$NOVNC_WEB/vnc_lite.html" "$NOVNC_WEB/vnc.html"
    ok "vnc.html created from vnc_lite.html"
fi

step "4 - install Chromium"
# On Ubuntu 24, chromium-browser is a snap wrapper that breaks inside Xvfb.
# Install native chromium from the ubuntu package instead.
# If snap chromium is already installed, we still prefer the native binary.
apt-get install -y -q chromium || apt-get install -y -q chromium-browser
CHROME_BIN=$(command -v chromium 2>/dev/null || command -v chromium-browser 2>/dev/null || true)
[ -z "$CHROME_BIN" ] && fail "Chromium not found after install"
# Warn if what we got is a snap wrapper (snap wrappers don't work with Xvfb)
if file "$CHROME_BIN" 2>/dev/null | grep -q "shell script"; then
    warn "$CHROME_BIN looks like a snap wrapper - may not work with Xvfb"
    warn "If Chrome fails to start, install from: https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
    warn "Then re-run this script."
fi
ok "Chromium at $CHROME_BIN"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Designer dependencies installed!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Now add designer users:"
echo "  sudo bash setup-designer.sh <username>"
echo ""
