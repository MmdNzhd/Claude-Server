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

# Log token usage from stats-cache.json (runs as the user, so readable)
STATS_FILE="$HOME/.claude/stats-cache.json"
if [ -f "$STATS_FILE" ]; then
    python3 - "$USER" "$SESSION_PID" "$LOG_FILE" "$STATS_FILE" << 'PYEOF' 2>/dev/null || true
import json, sys, os
from datetime import date

user, session, log_file, stats_file = sys.argv[1:]
try:
    with open(stats_file) as f:
        d = json.load(f)
    usage = d.get("modelUsage", {})
    if not usage:
        sys.exit(0)
    total_in  = sum(v.get("inputTokens",              0) for v in usage.values())
    total_out = sum(v.get("outputTokens",             0) for v in usage.values())
    total_cr  = sum(v.get("cacheReadInputTokens",     0) for v in usage.values())
    total_cw  = sum(v.get("cacheCreationInputTokens", 0) for v in usage.values())
    msgs      = d.get("totalMessages",  0)
    sess      = d.get("totalSessions",  0)
    entry = json.dumps({
        "timestamp": __import__("subprocess").check_output(["date", "-Iseconds"]).decode().strip(),
        "event":     "STATS",
        "user":      user,
        "session":   session,
        "inputTokens":              total_in,
        "outputTokens":             total_out,
        "cacheReadInputTokens":     total_cr,
        "cacheCreationInputTokens": total_cw,
        "totalMessages":            msgs,
        "totalSessions":            sess,
    }, separators=(",", ":"))
    with open(log_file, "a") as f:
        f.write(entry + "\n")
except Exception:
    pass
PYEOF
fi
