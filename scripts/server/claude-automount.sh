#!/bin/bash
# claude-automount -- runs from ~/.bashrc on interactive login.
# Mounts all configured projects (from ~/.claude-mounts.d/) if the tunnel is up.
# Idempotent: safe to run repeatedly.

set -u

# Cursor/VS Code spawn bash -ilc to resolve the shell environment. That must not
# re-run mount/auth/recover (~20s). connect.bat already mounted and synced auth.
# Early resolve often has NONE of VSCODE_IPC_HOOK_CLI / TERM_PROGRAM set yet.
if [ -n "${VSCODE_IPC_HOOK_CLI:-}" ] || [ -n "${CURSOR_AGENT:-}" ] || [ "${TERM_PROGRAM:-}" = "vscode" ] \
    || [ -n "${VSCODE_RESOLVING_ENVIRONMENT:-}" ] || [ -n "${VSCODE_PID:-}" ] \
    || [ -n "${CURSOR_TRACE_ID:-}" ]; then
    exit 0
fi
_ppargs=$(ps -o args= -p "${PPID:-0}" 2>/dev/null || true)
case "$_ppargs" in
    *cursor-server*|*vscode-server*|*bootstrap-fork*|*server-main.js*|*remote-cli*)
        exit 0
        ;;
esac

# Bound all login-path work so a hung auth/heal cannot break Cursor shell resolve.
# Server-wide OAuth: keep credentials.json empty and sync token into settings.json.
if [ -x /usr/local/bin/claude-auth-sync ]; then
    timeout 4 /usr/local/bin/claude-auth-sync >/dev/null 2>&1 || true
fi

if [ -x /usr/local/bin/cursor-auth-sync ] && [ -f /etc/cursor-auth/golden/auth.json ]; then
    timeout 4 /usr/local/bin/cursor-auth-sync >/dev/null 2>&1 || true
fi

if [ -x /usr/local/bin/laptop-exec-setup ]; then
    timeout 5 /usr/local/bin/laptop-exec-setup --user >/dev/null 2>&1 || true
    timeout 5 /usr/local/bin/laptop-exec-setup --all-projects >/dev/null 2>&1 || true
fi

# Full self-heal (CRLF, Cursor git-off, conf normalize, stale mounts, shim)
if [ -x /usr/local/bin/claude-self-heal ]; then
    timeout 8 /usr/local/bin/claude-self-heal --quiet >/dev/null 2>&1 || true
elif [ -x "$HOME/.local/bin/claude-self-heal" ]; then
    timeout 8 "$HOME/.local/bin/claude-self-heal" --quiet >/dev/null 2>&1 || true
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
        v="$(printf '%s' "$v" | tr -d '\r')"
        case "$k" in
            TUNNEL_PORT) TUNNEL_PORT="$v" ;;
            ACTIVE_MOUNT|active_mount) ACTIVE_MOUNT="$v" ;;
        esac
    done < "$CONNECT_CONF"
    if [ -n "$TUNNEL_PORT" ]; then
        if ! timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$TUNNEL_PORT" 2>/dev/null; then
            # Still self-heal: unmount stale SSHFS so IO cannot hang while offline
            if [ -x /usr/local/bin/claude-self-heal ]; then
                /usr/local/bin/claude-self-heal --quiet 2>/dev/null || true
            fi
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

# Infer ACTIVE_MOUNT from LAST_ACTIVE only (never first alphabetical conf).
LAST_ACTIVE="$HOME/.cache/claude-last-active-mount"
if [ -z "${ACTIVE_MOUNT:-}" ]; then
    if [ -f "$LAST_ACTIVE" ]; then
        ACTIVE_MOUNT="$(tr -d '\r\n' < "$LAST_ACTIVE" 2>/dev/null || true)"
    fi
    # Do NOT write first alphabetical conf as ACTIVE_MOUNT when empty;
    # leave empty unless LAST_ACTIVE (above) or connect set it explicitly.
    if [ -n "${ACTIVE_MOUNT:-}" ] && [ -f "$CONNECT_CONF" ]; then
        if grep -qiE '^ACTIVE_MOUNT=' "$CONNECT_CONF" 2>/dev/null; then
            sed -i "s/^ACTIVE_MOUNT=.*/ACTIVE_MOUNT=$ACTIVE_MOUNT/I" "$CONNECT_CONF" 2>/dev/null || true
        else
            printf '\nACTIVE_MOUNT=%s\n' "$ACTIVE_MOUNT" >> "$CONNECT_CONF"
        fi
    fi
fi

# Only mount the project connect.bat selected (never mount all projects on login)
if [ -n "$ACTIVE_MOUNT" ]; then
    "$MOUNT_BIN" up "$ACTIVE_MOUNT" 2>/dev/null || true
    mkdir -p "$(dirname "$STAMP")" 2>/dev/null || true
    touch "$STAMP" 2>/dev/null || true
    mkdir -p "$(dirname "$LAST_ACTIVE")" 2>/dev/null || true
    printf '%s\n' "$ACTIVE_MOUNT" > "$LAST_ACTIVE" 2>/dev/null || true
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



# windows-mcp-forward (optional; Windows hybrid)
# Quietly ensure localhost forward when this user has windows-mcp env + tunnel.
if [ -f "$HOME/.config/windows-mcp/env" ]; then
    if [ -x "$HOME/.local/bin/windows-mcp-forward" ]; then
        "$HOME/.local/bin/windows-mcp-forward" start >/dev/null 2>&1 || true
    elif [ -x /usr/local/bin/windows-mcp-forward ]; then
        /usr/local/bin/windows-mcp-forward start >/dev/null 2>&1 || true
    fi
fi
