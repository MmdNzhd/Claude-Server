#!/bin/bash
# audit-cursor-golden — deep Cursor golden auth audit (metadata lengths only, no secrets)
# Usage: sudo claude-server audit-cursor-golden

set -euo pipefail

AUDIT="/usr/local/lib/claude-server/audit-cursor-golden-deep.py"
if [ ! -f "$AUDIT" ]; then
    _dir="$(dirname "$(readlink -f "$0")")"
    for _candidate in \
        "$_dir/../audit-cursor-golden-deep.py" \
        "${CLAUDE_SERVER_REPO:-}/scripts/server/audit-cursor-golden-deep.py"; do
        [ -f "$_candidate" ] && AUDIT="$_candidate" && break
    done
    unset _dir _candidate
fi
[ -f "$AUDIT" ] || { echo "audit-cursor-golden: audit-cursor-golden-deep.py not found" >&2; exit 1; }

exec python3 "$AUDIT"
