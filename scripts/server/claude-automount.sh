#!/bin/bash
# claude-automount -- runs from ~/.bashrc on interactive login.
# Mounts all configured projects (from ~/.claude-mounts.d/) if the tunnel is up.
# Idempotent: safe to run repeatedly.

set -u

MOUNT_BIN="$HOME/.local/bin/claude-mount"
[ -x "$MOUNT_BIN" ] || MOUNT_BIN="/usr/local/bin/claude-mount"

# Fall back to legacy single-mount if new system not available
if [ ! -x "$MOUNT_BIN" ]; then
    exit 0
fi

# If no mounts configured yet, nothing to do
CONF_DIR="$HOME/.claude-mounts.d"
[ -d "$CONF_DIR" ] && compgen -G "$CONF_DIR/*.conf" >/dev/null 2>&1 || exit 0

# Check tunnel is up before attempting mounts (avoids 30s sshfs timeout on login)
CONNECT_CONF="$HOME/.claude-connect.conf"
if [ -f "$CONNECT_CONF" ]; then
    TUNNEL_PORT=""
    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        [ "$k" = "TUNNEL_PORT" ] && TUNNEL_PORT="$v"
    done < "$CONNECT_CONF"
    if [ -n "$TUNNEL_PORT" ]; then
        if ! timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TUNNEL_PORT" 2>/dev/null; then
            exit 0
        fi
    fi
fi

# Restore any .git dirs hidden by a previous crashed session before mounting
"$MOUNT_BIN" recover 2>/dev/null || true

"$MOUNT_BIN" up 2>/dev/null

# start watchdog in background to recover from hangs/disconnects
WATCHDOG="/usr/local/bin/claude-watchdog"
if [ -x "$WATCHDOG" ]; then
    nohup "$WATCHDOG" >/dev/null 2>&1 &
fi

