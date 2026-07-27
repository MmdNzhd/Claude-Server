#!/bin/bash
# deploy-mount-fix.sh - redeploy claude-mount + claude-automount (ACTIVE_MOUNT, down-others, EncodedCommand)
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

# atomic_install MODE SRC DST [OWNER] [GROUP]
# Installs SRC to DST via a same-directory temp file + rename so a process already
# executing DST (e.g. claude-watchdog polling claude-mount every 30s) never observes
# a partially-written file.
atomic_install() {
    local mode="$1" src="$2" dst="$3" owner="${4:-}" group="${5:-}" tmp="${3}.new.$$"
    if [ -n "$owner" ]; then
        install -m "$mode" -o "$owner" -g "$group" "$src" "$tmp" || return 1
    else
        install -m "$mode" "$src" "$tmp" || return 1
    fi
    mv -f "$tmp" "$dst"
}

if [ "$EUID" -ne 0 ]; then
    fail "run as root: sudo claude-server deploy-mount-fix"
fi

SELF="$(readlink -f "$0")"
DEPLOY_DIR="$(cd "$(dirname "$SELF")" && pwd)"
COMMANDS_DIR="$DEPLOY_DIR"
SERVER_DIR="$(cd "$COMMANDS_DIR/.." && pwd)"

_resolve_mount_sources() {
    local d
    for d in \
        "$DEPLOY_DIR" \
        "$SERVER_DIR" \
        "${CLAUDE_SERVER_REPO:-}/scripts/server" \
        "/home/smart/mounts/claude-code-server/scripts/server" \
        "/opt/claude-code-server/scripts/server" \
        "/usr/local/lib/claude-server"; do
        [ -n "$d" ] || continue
        [ -f "$d/claude-mount.sh" ] || continue
        MOUNT_SRC="$d/claude-mount.sh"
        AUTO_SRC="$d/claude-automount.sh"
        WATCH_SRC="$d/claude-watchdog.sh"
        return 0
    done
    if [ -f /usr/local/lib/claude-mount ] && [ -f /usr/local/bin/claude-automount ]; then
        warn "repo sources not found - redeploying from /usr/local (already installed)"
        MOUNT_SRC="/usr/local/lib/claude-mount"
        AUTO_SRC="/usr/local/bin/claude-automount"
        WATCH_SRC="/usr/local/bin/claude-watchdog"
        return 0
    fi
    return 1
}

MOUNT_SRC="" AUTO_SRC="" WATCH_SRC=""
_resolve_mount_sources || fail "claude-mount.sh not found (set CLAUDE_SERVER_REPO or run from repo)"

_strip_crlf() {
    local f="$1"
    [ -f "$f" ] || return 0
    sed -i 's/\r$//' "$f"
}

_strip_crlf "$MOUNT_SRC"
_strip_crlf "$AUTO_SRC"

if ! bash -n "$MOUNT_SRC" 2>/dev/null; then
    fail "claude-mount.sh syntax error (bash -n failed) - fix repo before deploy"
fi
[ -f "$WATCH_SRC" ] && _strip_crlf "$WATCH_SRC"

echo ""
echo -e "${BOLD}Deploy mount + automount fix${NC}"
echo -e "  ${BOLD}source${NC}  $MOUNT_SRC"
echo ""

atomic_install 755 "$AUTO_SRC" /usr/local/bin/claude-automount
ok "claude-automount -> /usr/local/bin/"
if [ -f "$SERVER_DIR/claude-self-heal.sh" ]; then
  heal_tmp="/usr/local/bin/claude-self-heal.new.$$"
  install -m 755 "$SERVER_DIR/claude-self-heal.sh" "$heal_tmp"
  sed -i 's/\r$//' "$heal_tmp" 2>/dev/null || true
  mv -f "$heal_tmp" /usr/local/bin/claude-self-heal
  ok "claude-self-heal -> /usr/local/bin/"
fi

atomic_install 755 "$MOUNT_SRC" /usr/local/lib/claude-mount
ok "claude-mount -> /usr/local/lib/claude-mount"
rm -f /usr/local/bin/claude-mount
ln -sf /usr/local/lib/claude-mount /usr/local/bin/claude-mount
if [ ! -x /usr/local/bin/claude-mount ]; then
    atomic_install 755 /usr/local/lib/claude-mount /usr/local/bin/claude-mount
fi
if grep -q "cmd /c exit 0" /usr/local/bin/claude-mount /usr/local/lib/claude-mount 2>/dev/null; then
    fail "claude-mount still contains cmd /c exit 0 (Windows CMD flash)"
fi
grep -q "WindowStyle Hidden -Command exit" /usr/local/lib/claude-mount || fail "claude-mount missing hidden Windows probe"

if [ -f "$WATCH_SRC" ]; then
    atomic_install 755 "$WATCH_SRC" /usr/local/bin/claude-watchdog
    ok "claude-watchdog -> /usr/local/bin/"
fi

grep -q 'cmd_down_others' /usr/local/lib/claude-mount || fail "claude-mount missing down-others"
grep -q 'EncodedCommand' /usr/local/lib/claude-mount || fail "claude-mount missing EncodedCommand git hide"
grep -q '_force_unmount_project' /usr/local/lib/claude-mount || fail "claude-mount missing force unmount"
grep -q 'up "$ACTIVE_MOUNT"' /usr/local/bin/claude-automount || fail "claude-automount missing ACTIVE_MOUNT"
if [ -f /usr/local/bin/claude-watchdog ]; then
    grep -q '_load_conf' /usr/local/bin/claude-watchdog || fail "claude-watchdog missing ACTIVE_MOUNT guard"
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
    atomic_install 755 /usr/local/lib/claude-mount "$home/.local/bin/claude-mount" "$u" "$u"
    if [ -f /usr/local/bin/claude-self-heal ]; then
        atomic_install 755 /usr/local/bin/claude-self-heal "$home/.local/bin/claude-self-heal" "$u" "$u"
    fi
    if [ -f /usr/local/bin/laptop-exec ]; then
        atomic_install 755 /usr/local/bin/laptop-exec "$home/.local/bin/laptop-exec" "$u" "$u"
    fi
    atomic_install 755 /usr/local/bin/claude-automount "$home/.local/bin/claude-automount" "$u" "$u"
    _patch_bashrc "$home/.bashrc"
    ok "$u ~/.local/bin/claude-mount + claude-automount"
done

echo ""
echo -e "${GREEN}Done.${NC} Users should reconnect connect.bat (v20260727.21+)."
echo ""
