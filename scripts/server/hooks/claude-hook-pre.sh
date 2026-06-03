#!/bin/bash
# PreToolUse hook: enforce per-user active session limit.
# exit 0 = allow tool, exit 2 = block tool (Claude Code cancels it)
#
# Fast path: if this session is already marked active, just touch and allow.
# This hook runs on EVERY tool call so it must be fast.

ACTIVE_DIR="/var/run/claude-active"
LIMITS_FILE="/etc/claude-limits.conf"

# CLAUDE_WRAPPER_PID is set by /usr/local/bin/claude wrapper.
# If not set (e.g. VS Code launches claude directly), fall back to PPID
# which is Claude Code's own PID — consistent across all tool calls in a session.
SESSION_PID="${CLAUDE_WRAPPER_PID:-$PPID}"
ACTIVE_FILE="${ACTIVE_DIR}/${USER}.${SESSION_PID}.active"

mkdir -p "$ACTIVE_DIR"

# Fast path: already active for this session
if [ -f "$ACTIVE_FILE" ]; then
    touch "$ACTIVE_FILE"
    exit 0
fi

# First tool call in this session: clean up stale markers for this user only.
# We only touch our own files to avoid permission errors on other users' files.
for f in "$ACTIVE_DIR"/${USER}.*.active; do
    [ -f "$f" ] || continue
    pid="${f##*\.}"
    [ -z "$pid" ] && { rm -f "$f"; continue; }
    kill -0 "$pid" 2>/dev/null || rm -f "$f"
done

# Get active_limit for this user
ACTIVE_LIMIT=$(awk -v u="$USER" '
    /^#/ { next }
    $1==u { print $3; found=1; exit }
    $1=="default" { def=$3 }
    END { if (!found) print def }
' "$LIMITS_FILE" 2>/dev/null)
ACTIVE_LIMIT="${ACTIVE_LIMIT:-2}"

[ "$ACTIVE_LIMIT" = "unlimited" ] && { touch "$ACTIVE_FILE"; exit 0; }

ACTIVE_COUNT=$(find "$ACTIVE_DIR" -maxdepth 1 -name "${USER}.*.active" 2>/dev/null | wc -l)

if [ "$ACTIVE_COUNT" -ge "$ACTIVE_LIMIT" ]; then
    echo "Active session limit reached ($ACTIVE_COUNT/$ACTIVE_LIMIT). Wait for another session to finish processing." >&2
    exit 2
fi

touch "$ACTIVE_FILE"
exit 0
