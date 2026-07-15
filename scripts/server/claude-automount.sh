#!/bin/bash
# claude-automount -- runs from ~/.bashrc on interactive login.
# Mounts all configured projects (from ~/.claude-mounts.d/) if the tunnel is up.
# Idempotent: safe to run repeatedly.

set -u

# Cursor/VS Code spawn bash -ilc to resolve the shell environment. That must not
# re-run mount/auth/recover (~20s). connect.bat already mounted and synced auth.
if [ -n "${VSCODE_IPC_HOOK_CLI:-}" ] || [ -n "${CURSOR_AGENT:-}" ] || [ "${TERM_PROGRAM:-}" = "vscode" ]; then
    exit 0
fi

# Server-wide OAuth: keep credentials.json empty and sync token into settings.json.
if [ -x /usr/local/bin/claude-auth-sync ]; then
    /usr/local/bin/claude-auth-sync
fi

if [ -x /usr/local/bin/cursor-auth-sync ] && [ -f /etc/cursor-auth/golden/auth.json ]; then
    /usr/local/bin/cursor-auth-sync
fi

if [ -x /usr/local/bin/laptop-exec-setup ]; then
    /usr/local/bin/laptop-exec-setup --user
    /usr/local/bin/laptop-exec-setup --all-projects 2>/dev/null || true
fi

MOUNT_BIN="$HOME/.local/bin/claude-mount"
[ -x "$MOUNT_BIN" ] || MOUNT_BIN="/usr/local/bin/claude-mount"
[ -x "$MOUNT_BIN" ] || MOUNT_BIN="/usr/local/lib/claude-mount"

# Fall back to legacy single-mount if new system not available
if [ ! -x "$MOUNT_BIN" ]; then
    exit 0
fi

# If no mounts configured yet, nothing to do
CONF_DIR="$HOME/.claude-mounts.d"
[ -d "$CONF_DIR" ] && compgen -G "$CONF_DIR/*.conf" >/dev/null 2>&1 || exit 0

# Check tunnel is up before attempting mounts (avoids 30s sshfs timeout on login)
CONNECT_CONF="$HOME/.claude-connect.conf"
ACTIVE_MOUNT=""
if [ -f "$CONNECT_CONF" ]; then
    TUNNEL_PORT=""
    while IFS='=' read -r k v; do
        v="${v#\"}" v="${v%\"}"
        case "$k" in
            TUNNEL_PORT) TUNNEL_PORT="$v" ;;
            ACTIVE_MOUNT|active_mount) ACTIVE_MOUNT="$v" ;;
        esac
    done < "$CONNECT_CONF"
    if [ -n "$TUNNEL_PORT" ]; then
        if ! timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TUNNEL_PORT" 2>/dev/null; then
            exit 0
        fi
    fi
fi

# Throttle full automount on repeated interactive shells (same SSH session).
STAMP="$HOME/.cache/claude-automount.stamp"
if [ -n "${ACTIVE_MOUNT:-}" ] && [ -f "$STAMP" ]; then
    stamp_age=$(( $(date +%s) - $(stat -c %Y "$STAMP" 2>/dev/null || echo 0) ))
    if [ "$stamp_age" -lt 300 ] && "$MOUNT_BIN" check "$ACTIVE_MOUNT" >/dev/null 2>&1; then
        # OFF mode must still run up (cheap) so stale hide sessions restore .git on laptop.
        _am_git=""
        if [ -f "$HOME/.claude-connect.conf" ]; then
            _am_git="$(grep -iE '^GIT_MODE=' "$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2- | tr '[:upper:]' '[:lower:]' | tr -d '\r\n ')"
        fi
        case "${_am_git:-off}" in
            server|on|yes|1|slow|hide|fast) exit 0 ;;
        esac
        "$MOUNT_BIN" up "$ACTIVE_MOUNT" 2>/dev/null || true
        exit 0
    fi
fi

# Restore any .git dirs hidden by a previous crashed session before mounting
"$MOUNT_BIN" recover 2>/dev/null || true

# Only mount the project connect.bat selected (never mount all projects on login)
if [ -n "$ACTIVE_MOUNT" ]; then
    "$MOUNT_BIN" up "$ACTIVE_MOUNT" 2>/dev/null || true
    mkdir -p "$(dirname "$STAMP")" 2>/dev/null || true
    touch "$STAMP" 2>/dev/null || true
fi

# Auto-init CodeGraph and Headroom for any newly mounted project.
# Runs in background after a short delay so SSHFS mounts settle first.
(
    sleep 5
    MOUNTS_DIR="$HOME/mounts"
    if [ -d "$MOUNTS_DIR" ] && command -v codegraph >/dev/null 2>&1; then
        for project in "$MOUNTS_DIR"/*/; do
            [ -d "$project" ] || continue
            # Skip if already indexed or if mount is empty (not yet ready)
            [ -d "$project/.codegraph" ] && continue
            [ -z "$(ls -A "$project" 2>/dev/null)" ] && continue
            timeout 120 codegraph init "$project" >/dev/null 2>&1 || true
        done
    fi
    # Headroom: register MCP if not already in settings
    if command -v headroom >/dev/null 2>&1; then
        SETTINGS="$HOME/.claude/settings.json"
        if [ -f "$SETTINGS" ] && ! grep -q '"headroom"' "$SETTINGS" 2>/dev/null; then
            headroom mcp install >/dev/null 2>&1 || true
        fi
    fi
) &

# start watchdog in background to recover from hangs/disconnects
WATCHDOG="/usr/local/bin/claude-watchdog"
if [ -x "$WATCHDOG" ]; then
    nohup "$WATCHDOG" >/dev/null 2>&1 &
fi


