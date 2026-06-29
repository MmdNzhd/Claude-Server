#!/bin/bash
# claude-auth-sync — sync server OAuth token into ~/.claude for CLI + VS Code extension
#
# Claude 2.1.x prefers ~/.claude/.credentials.json over CLAUDE_CODE_OAUTH_TOKEN.
# We keep credentials.json as {} and put the server token in settings.json env
# (required for the VS Code extension, which does not inherit /etc/environment).
#
# Usage (root):  claude-auth-sync <username>
#                 claude-auth-sync --all
# Usage (user):   claude-auth-sync

set -euo pipefail

_oauth_token() {
    grep -m1 '^CLAUDE_CODE_OAUTH_TOKEN=' /etc/environment 2>/dev/null | cut -d= -f2- || true
}

_sync_home() {
    local h="$1"
    local owner="${2:-}"

    local token
    token="$(_oauth_token)"
    [ -n "$token" ] || return 0

    mkdir -p "$h/.claude"
    printf '%s\n' '{}' > "$h/.claude/.credentials.json"
    chmod 600 "$h/.claude/.credentials.json"

    local settings="$h/.claude/settings.json"
    [ -f "$settings" ] || printf '%s\n' '{}' > "$settings"

    python3 - "$settings" "$token" <<'PY'
import json, sys
path, token = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
except (json.JSONDecodeError, OSError):
    data = {}
if not isinstance(data, dict):
    data = {}
env = data.get("env")
if not isinstance(env, dict):
    env = {}
data["env"] = env
env["CLAUDE_CODE_OAUTH_TOKEN"] = token
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

    if [ -n "$owner" ]; then
        chown -R "$owner" "$h/.claude"
    fi
}

case "${1:-}" in
    --all)
        [ "$EUID" -eq 0 ] || { echo "claude-auth-sync: must run as root for --all" >&2; exit 1; }
        [ -n "$(_oauth_token)" ] || {
            echo "claude-auth-sync: no CLAUDE_CODE_OAUTH_TOKEN in /etc/environment" >&2
            exit 1
        }
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
        [ "$EUID" -eq 0 ] || { echo "claude-auth-sync: must run as root for other users" >&2; exit 1; }
        u="$1"
        id "$u" &>/dev/null || { echo "claude-auth-sync: unknown user: $u" >&2; exit 1; }
        [ -n "$(_oauth_token)" ] || {
            echo "claude-auth-sync: no CLAUDE_CODE_OAUTH_TOKEN in /etc/environment" >&2
            exit 1
        }
        _sync_home "/home/$u" "$u:$u"
        printf 'OK %s\n' "$u"
        ;;
esac
