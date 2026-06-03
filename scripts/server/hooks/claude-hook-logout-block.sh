#!/bin/bash
# UserPromptSubmit hook: block /logout + log prompt timing
LOG_FILE="/var/log/claude-activity.jsonl"
SESSION_PID="${CLAUDE_WRAPPER_PID:-$PPID}"

INPUT=$(cat)

# log that a prompt was received — used to measure response latency
printf '{"timestamp":"%s","event":"PROMPT","user":"%s","session":"%s"}\n' \
    "$(date -Iseconds)" "$USER" "$SESSION_PID" >> "$LOG_FILE" 2>/dev/null || true

if [[ "$USER" == "smart" || "$USER" == "root" ]]; then
    exit 0
fi

PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)
if [ "$PROMPT" = "/logout" ]; then
    echo "Logout is disabled on this server. Contact admin (smart)." >&2
    exit 2
fi
exit 0
