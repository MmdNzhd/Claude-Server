#!/bin/bash
# cursor-auth-source-path — print ~/relative path to globalStorage with Cursor tokens
set -euo pipefail

LIB="/usr/local/lib/claude-server/cursor-auth-lib.py"
if [ ! -f "$LIB" ]; then
    _dir="$(dirname "$(readlink -f "$0")")"
    for _candidate in \
        "$_dir/cursor-auth-lib.py" \
        "${CLAUDE_SERVER_REPO:-/opt/claude-code-server}/scripts/server/cursor-auth-lib.py"; do
        [ -f "$_candidate" ] && LIB="$_candidate" && break
    done
    unset _dir _candidate
fi
[ -f "$LIB" ] || { echo "cursor-auth-source-path: cursor-auth-lib.py not found" >&2; exit 1; }

exec python3 "$LIB" source-path
