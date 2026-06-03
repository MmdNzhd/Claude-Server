#!/bin/bash
# claude-watchdog — monitors SSHFS mounts and recovers from hangs/disconnects.
# Run once per session: called from .bashrc after automount (runs in background).
# Only one instance per user runs at a time (lock file guard).

LOCK_FILE="/tmp/claude-watchdog-${USER}.pid"
MOUNT_BIN="$HOME/.local/bin/claude-mount"
[ -x "$MOUNT_BIN" ] || MOUNT_BIN="/usr/local/bin/claude-mount"
CONF_DIR="$HOME/.claude-mounts.d"
CONNECT_CONF="$HOME/.claude-connect.conf"
CHECK_INTERVAL=30   # seconds between checks
HANG_TIMEOUT=5      # seconds before declaring a mount hung

# Only one watchdog per user
if [ -f "$LOCK_FILE" ]; then
    OLD_PID=$(cat "$LOCK_FILE" 2>/dev/null)
    if kill -0 "$OLD_PID" 2>/dev/null; then
        exit 0  # already running
    fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

tunnel_up() {
    local port=""
    [ -f "$CONNECT_CONF" ] || return 1
    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        [ "$k" = "TUNNEL_PORT" ] && port="$v"
    done < "$CONNECT_CONF"
    [ -n "$port" ] || return 1
    timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null
}

mount_hung() {
    local path="$1"
    # if ls times out, mount is hung
    ! timeout "$HANG_TIMEOUT" ls "$path" >/dev/null 2>&1
}

while true; do
    sleep "$CHECK_INTERVAL"

    [ -d "$CONF_DIR" ] || continue
    [ -x "$MOUNT_BIN" ] || continue

    for conf in "$CONF_DIR"/*.conf; do
        [ -f "$conf" ] || continue
        id=""
        lpath=""
        while IFS='=' read -r k v; do
            v="${v#\"}" v="${v%\"}"
            case "$k" in
                id)    id="$v" ;;
                lpath) lpath="$v" ;;
            esac
        done < "$conf"
        [ -n "$id" ] && [ -n "$lpath" ] || continue

        # only care about currently mounted paths
        mountpoint -q "$lpath" 2>/dev/null || continue

        if mount_hung "$lpath"; then
            # force unmount the hung mount
            fusermount -uz "$lpath" 2>/dev/null || true
            sleep 2

            # remount only if tunnel is back up
            if tunnel_up; then
                "$MOUNT_BIN" up "$id" 2>/dev/null || true
            fi
        fi
    done
done
