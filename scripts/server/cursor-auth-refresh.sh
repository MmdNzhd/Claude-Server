#!/bin/bash
# cursor-auth-refresh - refresh golden Cursor OAuth tokens and re-sync all users
#
# Usage (root): cursor-auth-refresh
# Installed via cron: /etc/cron.d/cursor-auth-refresh (every 6 hours)

set -euo pipefail

LIB="/usr/local/lib/claude-server/cursor-auth-lib.py"
SYNC_BIN="/usr/local/bin/cursor-auth-sync"
LOG="/var/log/cursor-auth-refresh.log"

if [ ! -f "$LIB" ]; then
    _dir="$(dirname "$(readlink -f "$0")")"
    for _candidate in \
        "$_dir/cursor-auth-lib.py" \
        "${CLAUDE_SERVER_REPO:-/opt/claude-code-server}/scripts/server/cursor-auth-lib.py"; do
        [ -f "$_candidate" ] && LIB="$_candidate" && break
    done
    unset _dir _candidate
fi
[ -f "$LIB" ] || { echo "cursor-auth-refresh: cursor-auth-lib.py not found" >&2; exit 1; }

[ "$EUID" -eq 0 ] || { echo "cursor-auth-refresh: must run as root" >&2; exit 1; }

if [ ! -x "$SYNC_BIN" ]; then
    _dir="$(dirname "$(readlink -f "$0")")"
    for _candidate in \
        "$_dir/cursor-auth-sync.sh" \
        "${CLAUDE_SERVER_REPO:-/opt/claude-code-server}/scripts/server/cursor-auth-sync.sh"; do
        [ -x "$_candidate" ] && SYNC_BIN="$_candidate" && break
    done
    unset _dir _candidate
fi

_ts() { date -Is 2>/dev/null || date; }

_log() {
    printf '%s %s\n' "$(_ts)" "$1" >> "$LOG"
}

python3 - "$LIB" <<'PY'
import importlib.util
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

lib_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("cursor_auth_lib", lib_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

if not mod.golden_complete():
    raise SystemExit("cursor-auth-refresh: golden bundle missing")

auth = mod.load_golden_auth()
refresh_token = auth.get("refreshToken", "")
if not refresh_token:
    raise SystemExit("cursor-auth-refresh: no refreshToken in golden auth.json")

payload = json.dumps(
    {
        "grant_type": "refresh_token",
        "client_id": mod.OAUTH_CLIENT_ID,
        "refresh_token": refresh_token,
    }
).encode("utf-8")

req = urllib.request.Request(
    "https://api2.cursor.sh/oauth/token",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST",
)

try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = json.loads(resp.read().decode("utf-8"))
except urllib.error.HTTPError as exc:
    detail = exc.read().decode("utf-8", errors="replace")
    raise SystemExit(f"cursor-auth-refresh: HTTP {exc.code}: {detail}") from exc
except urllib.error.URLError as exc:
    raise SystemExit(f"cursor-auth-refresh: network error: {exc}") from exc

if body.get("shouldLogout"):
    raise SystemExit("cursor-auth-refresh: refresh token invalid - re-export golden auth")

access = body.get("access_token") or body.get("accessToken") or ""
if not access:
    raise SystemExit("cursor-auth-refresh: empty access_token in response")

auth["accessToken"] = access
new_refresh = body.get("refresh_token") or body.get("refreshToken")
if new_refresh:
    auth["refreshToken"] = new_refresh

mod.atomic_write(mod.AUTH_JSON, json.dumps(auth, indent=2) + "\n", mode=0o600)

if mod.STATE_KEYS_JSON.is_file():
    try:
        with mod.STATE_KEYS_JSON.open(encoding="utf-8") as f:
            state_keys = json.load(f)
        if isinstance(state_keys, dict):
            state_keys["cursorAuth/accessToken"] = access
            if new_refresh:
                state_keys["cursorAuth/refreshToken"] = new_refresh
            mod.atomic_write(
                mod.STATE_KEYS_JSON,
                json.dumps(state_keys, indent=2) + "\n",
                mode=0o600,
            )
    except (json.JSONDecodeError, OSError):
        pass

mod.atomic_write(
    mod.EXPORTED_AT,
    datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") + "\n",
    mode=0o600,
)
mod.apply_golden_permissions()
print("OK tokens refreshed")
PY

rc=$?
if [ "$rc" -ne 0 ]; then
    _log "ERROR refresh failed (exit $rc)"
    exit "$rc"
fi

_log "OK tokens refreshed"

if [ -x "$SYNC_BIN" ]; then
    if bash "$SYNC_BIN" --all --force; then
        _log "OK synced all users"
    else
        _log "ERROR sync after refresh failed"
        exit 1
    fi
else
    _log "WARN cursor-auth-sync not found - tokens updated but users not synced"
fi
