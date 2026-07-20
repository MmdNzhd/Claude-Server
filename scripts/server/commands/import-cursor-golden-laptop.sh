#!/bin/bash
# import-cursor-golden-laptop.sh - import golden Cursor identity from laptop server profile push
#
# Usage (root): claude-server import-cursor-golden-laptop /tmp/cursor-laptop-golden-smart
#
# Laptop pushes auth ONLY from %LOCALAPPDATA%\ClaudeServerCursorProfile (never personal Cursor).

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

[ "$EUID" -eq 0 ] || {
    echo -e "${RED}must run as root: sudo claude-server import-cursor-golden-laptop <dir>${NC}" >&2
    exit 1
}

IMPORT_DIR="${1:-}"
if [ -z "$IMPORT_DIR" ] || [ ! -d "$IMPORT_DIR" ]; then
    echo "Usage: sudo claude-server import-cursor-golden-laptop <import-dir>" >&2
    exit 1
fi

LIB="/usr/local/lib/claude-server/cursor-auth-lib.py"
if [ ! -f "$LIB" ]; then
    _cmd_dir="$(dirname "$(readlink -f "$0")")"
    for _candidate in \
        "$_cmd_dir/../cursor-auth-lib.py" \
        "${CLAUDE_SERVER_REPO:-/opt/claude-code-server}/scripts/server/cursor-auth-lib.py"; do
        [ -f "$_candidate" ] && LIB="$_candidate" && break
    done
    unset _cmd_dir _candidate
fi
[ -f "$LIB" ] || {
    echo -e "${RED}cursor-auth-lib.py not found - run: sudo claude-server install${NC}" >&2
    exit 1
}

SOURCE_HOST="$(hostname -f 2>/dev/null || hostname)-laptop-push"
python3 "$LIB" import-laptop-dir "$IMPORT_DIR" "$SOURCE_HOST"

SYNC_BIN="/usr/local/bin/cursor-auth-sync"
[ -x "$SYNC_BIN" ] || SYNC_BIN="$(dirname "$(readlink -f "$0")")/../cursor-auth-sync.sh"
[ -x "$SYNC_BIN" ] || {
    echo -e "${RED}cursor-auth-sync not found${NC}" >&2
    exit 1
}

echo ""
echo -e "${BOLD}=== Re-sync all users from updated golden ===${NC}"
bash "$SYNC_BIN" --all

chmod 700 /etc/cursor-auth/golden 2>/dev/null || true
chmod 600 /etc/cursor-auth/golden/* 2>/dev/null || true

echo ""
echo -e "${GREEN}OK golden imported from laptop server profile.${NC}"
echo "  On laptop: reconnect or press R, then Developer: Reload Window in [Claude Server]."
echo ""
