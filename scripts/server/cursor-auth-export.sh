#!/bin/bash
# cursor-auth-export - capture golden Cursor identity from a logged-in user
#
# Usage (root):
#   cursor-auth-export --from-user <username>
#   cursor-auth-export --from-path /path/to/globalStorage

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
[ -f "$LIB" ] || { echo "cursor-auth-export: cursor-auth-lib.py not found" >&2; exit 1; }

[ "$EUID" -eq 0 ] || { echo "cursor-auth-export: must run as root" >&2; exit 1; }

FROM_USER=""
FROM_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --from-user)
            [ $# -ge 2 ] || { echo "cursor-auth-export: --from-user requires a username" >&2; exit 1; }
            FROM_USER="$2"
            shift 2
            ;;
        --from-path)
            [ $# -ge 2 ] || { echo "cursor-auth-export: --from-path requires a directory" >&2; exit 1; }
            FROM_PATH="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: sudo cursor-auth-export --from-user <username>"
            echo "       sudo cursor-auth-export --from-path /path/to/globalStorage"
            echo ""
            echo "  --from-user tries: ~/.config/Cursor/, ~/.cursor-server/, then agent login files"
            exit 0
            ;;
        *)
            echo "cursor-auth-export: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [ -n "$FROM_USER" ] && [ -n "$FROM_PATH" ]; then
    echo "cursor-auth-export: use only one of --from-user or --from-path" >&2
    exit 1
fi

if [ -z "$FROM_USER" ] && [ -z "$FROM_PATH" ]; then
    echo "cursor-auth-export: specify --from-user or --from-path" >&2
    exit 1
fi

SOURCE_HOST="$(hostname -f 2>/dev/null || hostname)"
if [ -n "$FROM_USER" ]; then
    id "$FROM_USER" &>/dev/null || { echo "cursor-auth-export: unknown user: $FROM_USER" >&2; exit 1; }
    python3 - "$FROM_USER" "$SOURCE_HOST" "$LIB" <<'PY'
import sys
from pathlib import Path
import importlib.util

username = sys.argv[1]
source_host = sys.argv[2]
lib_path = sys.argv[3]

spec = importlib.util.spec_from_file_location("cursor_auth_lib", lib_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

home = Path(f"/home/{username}")
mod.export_from_user(home, username, source_host)

auth = mod.load_golden_auth()
if mod.jwt_expired(auth.get("accessToken", "")):
    print("cursor-auth-export: warning: access token is expired or expiring soon", file=sys.stderr)
    print("cursor-auth-export: run cursor-auth-refresh after export, or re-login first", file=sys.stderr)
PY
else
    python3 - "$FROM_PATH" "$SOURCE_HOST" "$LIB" <<'PY'
import sys
from pathlib import Path
import importlib.util

lib_path = sys.argv[3]
spec = importlib.util.spec_from_file_location("cursor_auth_lib", lib_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

global_dir = Path(sys.argv[1])
source_host = sys.argv[2]
mod.export_from_global_storage(global_dir, source_host)

auth = mod.load_golden_auth()
if mod.jwt_expired(auth.get("accessToken", "")):
    print("cursor-auth-export: warning: access token is expired or expiring soon", file=sys.stderr)
    print("cursor-auth-export: run cursor-auth-refresh after export, or re-login first", file=sys.stderr)
PY
fi

chmod 700 /etc/cursor-auth/golden 2>/dev/null || true
chmod 600 /etc/cursor-auth/golden/* 2>/dev/null || true

echo "OK golden bundle written to /etc/cursor-auth/golden/"
echo "Next: sudo claude-server sync-cursor-auth"
