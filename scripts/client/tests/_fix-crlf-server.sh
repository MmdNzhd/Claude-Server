#!/bin/bash
# One-shot: strip CRLF from claude-mount scripts (Windows scp leaves \r)
set -euo pipefail
for f in /usr/local/lib/claude-mount /usr/local/bin/claude-automount /usr/local/bin/claude-watchdog; do
    [ -f "$f" ] && sed -i 's/\r$//' "$f"
done
for home in /home/*/; do
    u="$(basename "$home")"
    id "$u" >/dev/null 2>&1 || continue
    for f in "$home/.local/bin/claude-mount" "$home/.local/bin/claude-automount"; do
        [ -f "$f" ] && sed -i 's/\r$//' "$f"
    done
done
echo CRLF_FIXED
