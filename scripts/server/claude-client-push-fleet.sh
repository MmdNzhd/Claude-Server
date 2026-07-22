#!/usr/bin/env bash
# claude-client-push-fleet - root cron: push client bundle to every user with a live tunnel.
# Survives any old laptop connect.bat / broken connect-update.

set -u
PUSH=/usr/local/bin/claude-client-push-laptop
[ -x "$PUSH" ] || exit 0

for conf in /home/*/.claude-connect.conf; do
    [ -f "$conf" ] || continue
    user="$(basename "$(dirname "$conf")")"
    # skip system-ish
    case "$user" in
        root|lost+found) continue ;;
    esac
    id "$user" >/dev/null 2>&1 || continue
    # cheap: only if TUNNEL_PORT looks open
    port="$(grep -E '^TUNNEL_PORT=' "$conf" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r"')"
    [ -n "$port" ] || continue
    if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/${port}" 2>/dev/null; then
        sudo -u "$user" -H env FORCE="${FORCE:-0}" "$PUSH" >/dev/null 2>&1 || true
    fi
done
exit 0
