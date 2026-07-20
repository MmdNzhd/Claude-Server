#!/usr/bin/env bash
set -euo pipefail
# Extract just the relevant functions from real file and test
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# On server we'll copy mount next to this
SRC="${1:-$HOME/.local/bin/claude-mount}"
# Strip case/main: keep until first '^case '
awk 'BEGIN{p=1} /^case[ ]"\$1"/ {exit} /^case "\$1"/ {exit} {print}' "$SRC" > /tmp/cm_funcs.sh
# Actually case is `case "$1" in`
awk 'BEGIN{p=1} /^case /{exit} {print}' "$SRC" > /tmp/cm_funcs.sh
echo "---- tail funcs ----"
tail -5 /tmp/cm_funcs.sh
echo "---- declare after source ----"
# shellcheck disable=SC1091
set +e
source /tmp/cm_funcs.sh
set -e
declare -F | grep -E 'emit|win_hide|hide_git' || true
type _emit_git_hide_warn || echo TYPE_FAIL
_emit_git_hide_warn $'GIT_HIDE:skip\r' || echo CALL_FAIL
# Also call win hide with no tunnel
LAPTOP_USER= TUNNEL_PORT= GIT_MODE=hide LAPTOP_OS=windows
_win_hide_git_and_create_stubs 'D:/tmp' || echo WIN_FAIL=$?
