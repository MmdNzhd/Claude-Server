#!/bin/bash
export NO_OPEN_BROWSER=1
PASS='sepidz@Admin'
AGENT=$(printf '%s\n' "$PASS" | sudo -S bash -lc 'command -v agent || ls /root/.local/bin/agent 2>/dev/null' | tail -1)
if [ -z "$AGENT" ] || [ ! -x "$AGENT" ]; then
  AGENT=$(printf '%s\n' "$PASS" | sudo -S ls /root/.local/bin/agent 2>/dev/null | tail -1)
fi
echo "agent: $AGENT"
printf '%s\n' "$PASS" | sudo -S env NO_OPEN_BROWSER=1 HOME=/root "$AGENT" login 2>&1
