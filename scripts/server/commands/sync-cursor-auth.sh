#!/bin/bash
# sync-cursor-auth.sh — push golden Cursor identity to all developer ~/.config/Cursor trees
# Usage: sudo claude-server sync-cursor-auth [username]

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

[ "$EUID" -ne 0 ] && {
    echo -e "${RED}must run as root: sudo claude-server sync-cursor-auth${NC}" >&2
    exit 1
}

SYNC_BIN="/usr/local/bin/cursor-auth-sync"
if [ ! -x "$SYNC_BIN" ]; then
    _cmd_dir="$(dirname "$(readlink -f "$0")")"
    for _candidate in \
        "$_cmd_dir/../cursor-auth-sync.sh" \
        "${CLAUDE_SERVER_REPO:-/opt/claude-code-server}/scripts/server/cursor-auth-sync.sh"; do
        [ -x "$_candidate" ] && SYNC_BIN="$_candidate" && break
    done
    unset _cmd_dir _candidate
fi
[ -x "$SYNC_BIN" ] || {
    echo -e "${RED}cursor-auth-sync not found — run: sudo claude-server install${NC}" >&2
    exit 1
}

GOLDEN="/etc/cursor-auth/golden/auth.json"
if [ ! -f "$GOLDEN" ]; then
    echo -e "${RED}no golden Cursor auth at /etc/cursor-auth/golden/${NC}" >&2
    echo "  Export first: sudo cursor-auth-export --from-user <name>" >&2
    echo "  (user must have logged into Cursor once via Remote SSH or agent login)" >&2
    exit 1
fi

echo ""
echo -e "${BOLD}=== Sync Cursor golden identity to user homes ===${NC}"
echo ""

if [ -n "${1:-}" ]; then
    bash "$SYNC_BIN" "$1"
else
    bash "$SYNC_BIN" --all
fi

echo ""
echo -e "${GREEN}Done.${NC} Users should reload Cursor (Developer: Reload Window) if a session is open."
echo ""
