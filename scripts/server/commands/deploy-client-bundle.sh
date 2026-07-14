#!/bin/bash
# deploy-client-bundle.sh - publish client scripts for laptop auto-update
# Usage: sudo claude-server deploy-client-bundle
# Installs to /usr/local/share/claude-client/ (world-readable, no secrets).

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
    fail "run as root: sudo claude-server deploy-client-bundle"
fi

SELF="$(readlink -f "$0")"
COMMANDS_DIR="$(cd "$(dirname "$SELF")" && pwd)"
REPO_DIR="${CLAUDE_SERVER_REPO:-$(cd "$COMMANDS_DIR/../../.." && pwd 2>/dev/null)}"
CLIENT_DIR="$REPO_DIR/scripts/client"

_resolve_repo() {
    local d
    for d in \
        "$REPO_DIR" \
        "${CLAUDE_SERVER_REPO:-}" \
        "/home/smart/mounts/claude-code-server" \
        "/opt/claude-code-server"; do
        [ -n "$d" ] || continue
        [ -f "$d/scripts/client/windows/connect.ps1" ] || continue
        REPO_DIR="$d"
        CLIENT_DIR="$REPO_DIR/scripts/client"
        return 0
    done
    return 1
}

_resolve_repo || fail "client scripts not found (set CLAUDE_SERVER_REPO)"

BUNDLE_ROOT="/usr/local/share/claude-client"
WIN_SRC="$CLIENT_DIR/windows"
MAC_SRC="$CLIENT_DIR/mac"

[ -f "$WIN_SRC/connect-version.txt" ] || fail "missing $WIN_SRC/connect-version.txt"
[ -f "$WIN_SRC/connect.ps1" ] || fail "missing $WIN_SRC/connect.ps1"
[ -f "$MAC_SRC/connect.sh" ] || fail "missing $MAC_SRC/connect.sh"

_strip_crlf() {
    local f="$1"
    [ -f "$f" ] || return 0
    sed -i 's/\r$//' "$f"
}

echo ""
echo -e "${BOLD}Deploy client bundle (laptop auto-update)${NC}"
echo -e "  ${BOLD}source${NC}  $CLIENT_DIR"
echo -e "  ${BOLD}target${NC}  $BUNDLE_ROOT"
echo ""

rm -rf "$BUNDLE_ROOT"
mkdir -p "$BUNDLE_ROOT/mac"

win_files=(
    connect.bat
    connect-version.txt
    connect.ps1
    connect-rider.bat
    connect-update.ps1
    connect-ui.ps1
    connect-diagnostic.ps1
    editor-launch.ps1
    git-mode.ps1
    cursor-auth-laptop.ps1
)

for name in "${win_files[@]}"; do
    src=""
    case "$name" in
        connect-ui.ps1|editor-launch.ps1|git-mode.ps1|cursor-auth-laptop.ps1|connect-diagnostic.ps1)
            src="$CLIENT_DIR/$name"
            ;;
        *)
            src="$WIN_SRC/$name"
            ;;
    esac
    if [ ! -f "$src" ]; then
        warn "skip missing: $name"
        continue
    fi
    install -m 644 "$src" "$BUNDLE_ROOT/$name"
    _strip_crlf "$BUNDLE_ROOT/$name"
    ok "$name"
done

mac_files=(
    connect.sh
    connect-update.sh
    connect-version.txt
    git-mode.sh
    connect-ui.sh
    editor-launch.sh
    claude-mount.sh
)

for name in "${mac_files[@]}"; do
    src=""
    case "$name" in
        git-mode.sh|connect-ui.sh|editor-launch.sh)
            src="$CLIENT_DIR/$name"
            ;;
        connect-version.txt)
            src="$WIN_SRC/connect-version.txt"
            ;;
        claude-mount.sh)
            src="$REPO_DIR/scripts/server/claude-mount.sh"
            ;;
        *)
            src="$MAC_SRC/$name"
            ;;
    esac
    if [ ! -f "$src" ]; then
        warn "skip missing mac/$name"
        continue
    fi
    install -m 644 "$src" "$BUNDLE_ROOT/mac/$name"
    _strip_crlf "$BUNDLE_ROOT/mac/$name"
    ok "mac/$name"
done

{
    for name in "${win_files[@]}"; do
        [ -f "$BUNDLE_ROOT/$name" ] && printf '%s\n' "$name"
    done
    for name in "${mac_files[@]}"; do
        [ -f "$BUNDLE_ROOT/mac/$name" ] && printf 'mac/%s\n' "$name"
    done
} > "$BUNDLE_ROOT/manifest.txt"
chmod 644 "$BUNDLE_ROOT/manifest.txt"
ok "manifest.txt ($(wc -l < "$BUNDLE_ROOT/manifest.txt") files)"

chmod 755 "$BUNDLE_ROOT" "$BUNDLE_ROOT/mac"
VER="$(tr -d '\r\n' < "$BUNDLE_ROOT/connect-version.txt")"
echo ""
echo -e "${GREEN}Done.${NC} Client bundle v${VER} at $BUNDLE_ROOT"
echo "  Laptops auto-update on connect.bat / mac/connect.sh launch."
echo ""
