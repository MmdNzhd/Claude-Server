#!/bin/bash
# cursor-remote-proxy-sync - merge remote Cursor Machine proxy settings
#
# Remote Cursor agents inherit laptop http.proxy (often 127.0.0.1:18998), which
# exists only on the laptop. This writes Machine-scoped overrides so remote
# code/MCP never stay stuck on the laptop-only front door.
#
# Live mode (ss listen check on PROXY_PORT):
#   xray_10809    - 10809 UP  → http(s).proxy=http://127.0.0.1:10809,
#                   http.proxySupport=override
#   server_direct - 10809 DOWN → http.proxySupport=off and drop proxy URL keys
#                   so Cursor uses the server NIC directly.
#
# "server_direct" means Machine proxy off on the remote host. It does NOT change
# xray outbound routing. austria-xhttp remains the primary egress when xray is
# up (Cursor IP unification). No austria→direct balancer is installed here:
# a catch-all fallback would risk leaking office IP when austria fails open.
#
# Usage:
#   (root)  cursor-remote-proxy-sync --all
#           cursor-remote-proxy-sync --user <username>
#   (user)  cursor-remote-proxy-sync              # sync own Machine settings
#           cursor-remote-proxy-sync --user $USER
#
# Path: /home/$u/.cursor-server/data/Machine/settings.json (merge; keep other keys)

set -euo pipefail

PROXY_URL="http://127.0.0.1:10809"
PROXY_PORT=10809

_xray_listening() {
    if command -v ss >/dev/null 2>&1; then
        ss -lnt "sport = :${PROXY_PORT}" 2>/dev/null | grep -q ":${PROXY_PORT}"
        return $?
    fi
    if command -v timeout >/dev/null 2>&1; then
        timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/${PROXY_PORT}" 2>/dev/null
        return $?
    fi
    return 1
}

_is_skip_user() {
    local u="$1"
    case "$u" in
        nobody|snap*|designer) return 0 ;;
    esac
    return 1
}

_can_sync_user() {
    local u="$1"
    if [ "$EUID" -eq 0 ]; then
        return 0
    fi
    [ "$u" = "$(id -un)" ]
}

_sync_user() {
    local u="$1"
    local mode="$2"
    local home="/home/$u"
    local machine_dir="$home/.cursor-server/data/Machine"
    local settings="$machine_dir/settings.json"

    id "$u" &>/dev/null || {
        echo "cursor-remote-proxy-sync: unknown user: $u" >&2
        return 1
    }
    [ -d "$home" ] || return 0
    if _is_skip_user "$u"; then
        printf 'SKIP %s\n' "$u"
        return 0
    fi
    if ! _can_sync_user "$u"; then
        echo "cursor-remote-proxy-sync: must be root to sync user $u (or run as that user)" >&2
        return 1
    fi

    mkdir -p "$machine_dir"
    if [ "$EUID" -eq 0 ]; then
        chmod 755 "$home/.cursor-server" 2>/dev/null || true
        chmod 755 "$home/.cursor-server/data" 2>/dev/null || true
        chmod 755 "$machine_dir"
    fi

    python3 - "$settings" "$PROXY_URL" "$mode" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
proxy_url = sys.argv[2]
mode = sys.argv[3]

existing = {}
if path.is_file():
    try:
        with path.open(encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            existing = data
    except Exception:
        existing = {}

if mode == "xray_10809":
    existing["http.proxy"] = proxy_url
    existing["https.proxy"] = proxy_url
    existing["http.proxyStrictSSL"] = False
    existing["http.proxySupport"] = "override"
else:
    # server_direct: no proxy on remote — use server NIC
    existing["http.proxySupport"] = "off"
    for key in ("http.proxy", "https.proxy", "http.proxyStrictSSL"):
        existing.pop(key, None)

path.parent.mkdir(parents=True, exist_ok=True)
with path.open("w", encoding="utf-8") as fh:
    json.dump(existing, fh, indent=2)
    fh.write("\n")
path.chmod(0o644)
PY

    if [ "$EUID" -eq 0 ]; then
        chown -R "$u:$u" "$home/.cursor-server"
    fi
    printf 'OK %s mode=%s %s\n' "$u" "$mode" "$settings"
}

TARGET=""
MODE="self"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --all)
            MODE="all"
            shift
            ;;
        --user)
            [ "$#" -ge 2 ] || {
                echo "cursor-remote-proxy-sync: --user requires a username" >&2
                exit 1
            }
            MODE="user"
            TARGET="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: cursor-remote-proxy-sync [--all | --user NAME | NAME]" >&2
            echo "  Modes: xray_10809 (proxy 10809) or server_direct (proxySupport=off)" >&2
            exit 0
            ;;
        --*)
            echo "cursor-remote-proxy-sync: unknown option: $1" >&2
            exit 1
            ;;
        *)
            MODE="user"
            TARGET="$1"
            shift
            ;;
    esac
done

if _xray_listening; then
    PROXY_MODE="xray_10809"
    echo "cursor-remote-proxy-sync: mode=${PROXY_MODE} (${PROXY_URL} listening)"
else
    PROXY_MODE="server_direct"
    echo "cursor-remote-proxy-sync: mode=${PROXY_MODE} (${PROXY_URL} DOWN - Machine proxySupport=off)"
fi

case "$MODE" in
    all)
        if [ "$EUID" -ne 0 ]; then
            echo "cursor-remote-proxy-sync: --all requires root" >&2
            exit 1
        fi
        for u in $(awk -F: '$3>=1000{print $1}' /etc/passwd); do
            [ -d "/home/$u" ] || continue
            _is_skip_user "$u" && continue
            _sync_user "$u" "$PROXY_MODE" || {
                printf 'WARN %s sync failed - continuing\n' "$u" >&2
            }
        done
        ;;
    user)
        [ -n "$TARGET" ] || {
            echo "cursor-remote-proxy-sync: username required" >&2
            exit 1
        }
        _sync_user "$TARGET" "$PROXY_MODE"
        ;;
    self)
        _sync_user "$(id -un)" "$PROXY_MODE"
        ;;
esac
