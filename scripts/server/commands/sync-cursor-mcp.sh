#!/bin/bash
# sync-cursor-mcp.sh - push standard Cursor MCP pack to all developer ~/.cursor/mcp.json trees
# Usage: sudo claude-server sync-cursor-mcp [username]

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

[ "$EUID" -ne 0 ] && {
    echo -e "${RED}must run as root: sudo claude-server sync-cursor-mcp${NC}" >&2
    exit 1
}

SYNC_BIN="/usr/local/bin/cursor-mcp-sync"
if [ ! -x "$SYNC_BIN" ]; then
    _cmd_dir="$(dirname "$(readlink -f "$0")")"
    for _candidate in \
        "$_cmd_dir/cursor-mcp-sync.sh" \
        "$_cmd_dir/../cursor-mcp-sync.sh" \
        "${CLAUDE_SERVER_REPO:-/opt/claude-code-server}/scripts/server/cursor-mcp-sync.sh"; do
        [ -x "$_candidate" ] && SYNC_BIN="$_candidate" && break
    done
    unset _cmd_dir _candidate
fi
[ -x "$SYNC_BIN" ] || {
    echo -e "${RED}cursor-mcp-sync not found - run: sudo claude-server install${NC}" >&2
    exit 1
}

echo ""
echo -e "${BOLD}=== Sync Cursor MCP pack to user homes ===${NC}"
echo ""

if [ -n "${1:-}" ]; then
    bash "$SYNC_BIN" "$1"
else
    bash "$SYNC_BIN" --all
fi

echo ""
echo -e "${GREEN}Done.${NC} Users should reload Cursor (Developer: Reload Window) if a session is open."
echo ""
