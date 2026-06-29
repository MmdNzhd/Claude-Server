#!/bin/bash
# sync-auth.sh — push server OAuth token to all developer ~/.claude/ trees
# Usage: sudo claude-server sync-auth [username]

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

[ "$EUID" -ne 0 ] && {
    echo -e "${RED}must run as root: sudo claude-server sync-auth${NC}" >&2
    exit 1
}

SYNC_BIN="/usr/local/bin/claude-auth-sync"
if [ ! -x "$SYNC_BIN" ]; then
    _cmd_dir="$(dirname "$(readlink -f "$0")")"
    for _candidate in \
        "$_cmd_dir/../claude-auth-sync.sh" \
        "${CLAUDE_SERVER_REPO:-/opt/claude-code-server}/scripts/server/claude-auth-sync.sh"; do
        [ -x "$_candidate" ] && SYNC_BIN="$_candidate" && break
    done
    unset _cmd_dir _candidate
fi
[ -x "$SYNC_BIN" ] || {
    echo -e "${RED}claude-auth-sync not found — run: sudo claude-server install${NC}" >&2
    exit 1
}

if ! grep -q '^CLAUDE_CODE_OAUTH_TOKEN=' /etc/environment 2>/dev/null; then
    echo -e "${RED}no CLAUDE_CODE_OAUTH_TOKEN in /etc/environment${NC}" >&2
    echo "  Set token first, then re-run: sudo claude-server sync-auth" >&2
    exit 1
fi

echo ""
echo -e "${BOLD}=== Sync OAuth token to user settings ===${NC}"
echo ""

if [ -n "${1:-}" ]; then
    bash "$SYNC_BIN" "$1"
else
    bash "$SYNC_BIN" --all
fi

echo ""
echo -e "${GREEN}Done.${NC} Users should reload VS Code (Developer: Reload Window)."
echo ""
