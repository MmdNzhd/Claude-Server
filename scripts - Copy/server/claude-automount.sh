#!/bin/bash
# claude-automount — idempotent mount trigger for Claude Code.
# Safe to call from ~/.bashrc, from the laptop launcher, or manually.
# Migrates the old single-mount ~/.claude-mount.conf to the new multi-mount
# registry on first run, then delegates to claude-mount.
#
# Install: install -m 755 scripts/server/claude-automount.sh /usr/local/bin/claude-automount

set -u

[ "$(id -u)" -eq 0 ] && { echo "claude-automount: do not run as root" >&2; exit 1; }

CONF_DIR="$HOME/.claude-mounts.d"
CONNECT_CONF="$HOME/.claude-connect.conf"
OLD_CONF="$HOME/.claude-mount.conf"

# ── migrate old single-mount config ──────────────────────────────────────────
_needs_migration() {
    [ -f "$OLD_CONF" ] || return 1                                 # no old conf - nothing to migrate
    [ -n "$(ls "$CONF_DIR"/*.conf 2>/dev/null)" ] && return 1     # new mounts already exist - done
    return 0
}

if _needs_migration; then
    . "$OLD_CONF"

    if [ -n "${LAPTOP_USER:-}" ] && [ -n "${PROJECT_PATH:-}" ]; then
        PORT=$(( 20000 + $(id -u) ))
        mkdir -p "$CONF_DIR"

        printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\n' "$LAPTOP_USER" "$PORT" > "$CONNECT_CONF"

        # derive label from the last component of PROJECT_PATH (e.g. D:/Smart -> Smart)
        LABEL=$(basename "$PROJECT_PATH")

        # Keep ~/work as the local path so nothing breaks for existing users
        printf 'MOUNT_ID=work\nMOUNT_LABEL="%s"\nREMOTE_PATH="%s"\nLOCAL_PATH="%s/work"\n' \
            "$LABEL" "$PROJECT_PATH" "$HOME" > "$CONF_DIR/work.conf"
    fi
fi

# ── delegate to claude-mount ──────────────────────────────────────────────────
if command -v claude-mount >/dev/null 2>&1; then
    exec claude-mount up 2>&1
fi

# ── fallback: claude-mount not installed, use legacy logic ────────────────────
[ -f "$CONF_DIR/work.conf" ] || [ -f "$OLD_CONF" ] || exit 0

. "${CONF_DIR}/work.conf" 2>/dev/null || . "$OLD_CONF"
MOUNT="${LOCAL_PATH:-$HOME/work}"
LAPTOP_USER="${LAPTOP_USER:-}"
PROJECT_PATH="${REMOTE_PATH:-${PROJECT_PATH:-}}"
PORT="${TUNNEL_PORT:-$(( 20000 + $(id -u) ))}"
KEY="$HOME/.ssh/claude_laptop"

[ -n "$LAPTOP_USER" ] && [ -n "$PROJECT_PATH" ] || exit 0

if mountpoint -q "$MOUNT" 2>/dev/null && ls "$MOUNT" >/dev/null 2>&1; then
    exit 0
fi

if ! timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$PORT" 2>/dev/null; then
    echo "claude-automount: tunnel not on port $PORT — run 'connect' on your laptop first" >&2
    exit 1
fi

mountpoint -q "$MOUNT" 2>/dev/null && ! ls "$MOUNT" >/dev/null 2>&1 && \
    fusermount -uz "$MOUNT" 2>/dev/null || true

mkdir -p "$MOUNT"
OPTS="reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,idmap=user,allow_other"
OPTS="$OPTS,StrictHostKeyChecking=no,UserKnownHostsFile=/dev/null"
[ -f "$KEY" ] && OPTS="$OPTS,IdentityFile=$KEY"

ERR=$(mktemp)
if sshfs -p "$PORT" "${LAPTOP_USER}@localhost:${PROJECT_PATH}" "$MOUNT" -o "${OPTS}" 2>"$ERR"; then
    echo "claude-automount: mounted $PROJECT_PATH -> $MOUNT"
    rm -f "$ERR"
else
    echo "claude-automount: mount FAILED" >&2
    cat "$ERR" >&2
    rm -f "$ERR"
    exit 1
fi
