#!/bin/bash
# deploy-mount-fix.sh ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â redeploy claude-mount + claude-automount (ACTIVE_MOUNT, down-others, EncodedCommand)
# Usage: sudo claude-server deploy-mount-fix
# Safe to re-run. Does not touch OAuth/Cursor auth.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf "  ${GREEN}ok${NC}    %s\n" "$1"; }
warn() { printf "  ${YELLOW}warn${NC}  %s\n" "$1"; }
fail() { printf "  ${RED}FAIL${NC}  %s\n" "$1"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    fail "run as root: sudo claude-server deploy-mount-fix"
fi

SELF="$(readlink -f "$0")"
DEPLOY_DIR="$(cd "$(dirname "$SELF")" && pwd)"
COMMANDS_DIR="$(cd "$(dirname "$SELF")" && pwd)"
SERVER_DIR="$(cd "$COMMANDS_DIR/.." && pwd)"

if [ -f "$DEPLOY_DIR/claude-mount.sh" ]; then
    MOUNT_SRC="$DEPLOY_DIR/claude-mount.sh"
    AUTO_SRC="$DEPLOY_DIR/claude-automount.sh"
    WATCH_SRC="$DEPLOY_DIR/claude-watchdog.sh"
elif [ -f "$SERVER_DIR/claude-mount.sh" ]; then
    MOUNT_SRC="$SERVER_DIR/claude-mount.sh"
    AUTO_SRC="$SERVER_DIR/claude-automount.sh"
    WATCH_SRC="$SERVER_DIR/claude-watchdog.sh"
else
    fail "claude-mount.sh not found (run from repo or ~/claude-mount-deploy/)"
fi

_strip_crlf() {
    local f="$1"
    [ -f "$f" ] || return 0
    sed -i 's/\r$//' "$f"
}

_strip_crlf "$MOUNT_SRC"
_strip_crlf "$AUTO_SRC"
[ -f "$WATCH_SRC" ] && _strip_crlf "$WATCH_SRC"

echo ""
echo -e "${BOLD}Deploy mount + automount fix${NC}"
echo ""

install -m 755 "$AUTO_SRC" /usr/local/bin/claude-automount
ok "claude-automount ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ /usr/local/bin/"

install -m 755 "$MOUNT_SRC" /usr/local/lib/claude-mount
ok "claude-mount ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ /usr/local/lib/claude-mount"
ln -sf /usr/local/lib/claude-mount /usr/local/bin/claude-mount 2>/dev/null || true

if [ -f "$WATCH_SRC" ]; then
    install -m 755 "$WATCH_SRC" /usr/local/bin/claude-watchdog
    ok "claude-watchdog ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ /usr/local/bin/"
fi

grep -q 'cmd_down_others' /usr/local/lib/claude-mount || fail "claude-mount missing down-others"
grep -q 'EncodedCommand' /usr/local/lib/claude-mount || fail "claude-mount missing EncodedCommand git hide"
grep -q '_force_unmount_project' /usr/local/lib/claude-mount || fail "claude-mount missing force unmount"
grep -q 'up "$ACTIVE_MOUNT"' /usr/local/bin/claude-automount || fail "claude-automount missing ACTIVE_MOUNT"
if [ -f /usr/local/bin/claude-watchdog ]; then
    grep -q '_load_active_mount' /usr/local/bin/claude-watchdog || fail "claude-watchdog missing ACTIVE_MOUNT guard"
fi

_patch_bashrc() {
    local bashrc="$1"
    [ -f "$bashrc" ] || return 0
    grep -q 'claude-automount' "$bashrc" || return 0
    if grep -q '.local/bin/claude-automount' "$bashrc"; then
        return 0
    fi
    sed -i 's|/usr/local/bin/claude-automount 2>/dev/null|"$HOME/.local/bin/claude-automount" 2>/dev/null \|\| /usr/local/bin/claude-automount 2>/dev/null|' "$bashrc"
}

for home in /home/*/; do
    u="$(basename "$home")"
    [ "$u" = "lost+found" ] && continue
    id "$u" >/dev/null 2>&1 || continue
    mkdir -p "$home/.local/bin"
    install -m 755 /usr/local/lib/claude-mount "$home/.local/bin/claude-mount"
    install -m 755 /usr/local/bin/claude-automount "$home/.local/bin/claude-automount"
    chown "$u:$u" "$home/.local/bin/claude-mount" "$home/.local/bin/claude-automount"
    _patch_bashrc "$home/.bashrc"
    ok "$u ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ ~/.local/bin/claude-mount + claude-automount"
done

echo ""
echo -e "${GREEN}Done.${NC} Users should reconnect connect.bat (v20260705.4+)."
echo ""
