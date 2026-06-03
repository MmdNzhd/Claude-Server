#!/bin/bash
LOG_FILE="/var/log/claude-activity.jsonl"

# guard: if PID is unset we'd remove the wrong file
if [ -n "${CLAUDE_WRAPPER_PID:-}" ]; then
    rm -f "/var/run/claude-active/$USER.$CLAUDE_WRAPPER_PID.active"
fi

printf '{"timestamp":"%s","event":"IDLE","user":"%s"}\n' \
    "$(date -Iseconds)" "$USER" >> "$LOG_FILE" 2>/dev/null || true
