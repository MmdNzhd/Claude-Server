#!/bin/bash
LOG_FILE="/var/log/claude-activity.jsonl"
ACTIVE_DIR="/var/run/claude-active"

# Remove all active markers for this user -- catches both CLAUDE_WRAPPER_PID
# and PPID-based files, and any stale ones left from crashed sessions.
for f in "$ACTIVE_DIR"/${USER}.*.active; do
    [ -f "$f" ] || continue
    pid="${f##*\.}"
    # Remove our session file, and also any other stale ones (dead process or empty PID)
    [ -z "$pid" ] && { rm -f "$f"; continue; }
    kill -0 "$pid" 2>/dev/null || rm -f "$f"
done

# Remove our specific session file explicitly (covers the case where the process
# is still alive but we're stopping -- e.g. the wrapper PID or PPID)
SESSION_PID="${CLAUDE_WRAPPER_PID:-$PPID}"
rm -f "${ACTIVE_DIR}/${USER}.${SESSION_PID}.active" 2>/dev/null || true

printf '{"timestamp":"%s","event":"IDLE","user":"%s","session":"%s"}\n' \
    "$(date -Iseconds)" "$USER" "$SESSION_PID" >> "$LOG_FILE" 2>/dev/null || true
