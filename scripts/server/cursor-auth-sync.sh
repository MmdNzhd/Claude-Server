#!/bin/bash
# cursor-auth-sync — push golden Cursor identity into ~/.config/Cursor per user
#
# Usage (root):  cursor-auth-sync <username>
#                 cursor-auth-sync --all
#                 cursor-auth-sync --all --force
# Usage (user):   cursor-auth-sync

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
[ -f "$LIB" ] || { echo "cursor-auth-sync: cursor-auth-lib.py not found" >&2; exit 1; }

FORCE=false
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
        *) ARGS+=("$arg") ;;
    esac
done
set -- "${ARGS[@]}"

_sync_home() {
    local h="$1"
    local owner="${2:-}"
    local force_flag=""
    $FORCE && force_flag="--force"

    python3 - "$h" "$owner" "$force_flag" "$LIB" <<'PY'
import importlib.util
import sys
from pathlib import Path

home = Path(sys.argv[1])
owner = sys.argv[2] or None
force = sys.argv[3] == "--force"
lib_path = sys.argv[4]

spec = importlib.util.spec_from_file_location("cursor_auth_lib", lib_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

mod.sync_user_home(home, owner, force=force)
PY
}

case "${1:-}" in
    --all)
        [ "$EUID" -eq 0 ] || { echo "cursor-auth-sync: must run as root for --all" >&2; exit 1; }
        python3 - "$LIB" <<'PY'
import importlib.util
import sys
from pathlib import Path

lib_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("cursor_auth_lib", lib_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
if not mod.golden_complete():
    raise SystemExit("cursor-auth-sync: golden bundle missing — run: sudo cursor-auth-export --from-user <name>")
PY
        for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
            h="/home/$u"
            [ -d "$h" ] || continue
            [ "$u" = "designer" ] && continue
            _sync_home "$h" "$u:$u"
            printf 'OK %s\n' "$u"
        done
        ;;
    "")
        _sync_home "${HOME:?}" ""
        ;;
    *)
        [ "$EUID" -eq 0 ] || { echo "cursor-auth-sync: must run as root for other users" >&2; exit 1; }
        u="$1"
        id "$u" &>/dev/null || { echo "cursor-auth-sync: unknown user: $u" >&2; exit 1; }
        _sync_home "/home/$u" "$u:$u"
        printf 'OK %s\n' "$u"
        ;;
esac
