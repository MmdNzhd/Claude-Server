#!/bin/bash
SESSIONS_DIR="/var/run/claude-sessions"
ACTIVE_DIR="/var/run/claude-active"

# Clean stale sessions
for f in "$SESSIONS_DIR"/*.session; do
    [ -f "$f" ] || continue
    PID=$(basename "$f" .session)
    kill -0 "$PID" 2>/dev/null || rm -f "$f"
done

# Clean stale active files
for f in "$ACTIVE_DIR"/*.active; do
    [ -f "$f" ] || continue
    FPID=$(basename "$f" | rev | cut -d. -f2 | rev)
    kill -0 "$FPID" 2>/dev/null || rm -f "$f"
done

COUNT=$(ls "$SESSIONS_DIR"/*.session 2>/dev/null | wc -l)
ACTIVE_COUNT=$(ls "$ACTIVE_DIR"/*.active 2>/dev/null | wc -l)

if [ "$COUNT" -eq 0 ]; then
    echo "No active sessions"
    exit 0
fi

echo "Sessions: $COUNT open, $ACTIVE_COUNT processing"
echo ""
printf "  %-15s  %-12s  %-12s  %s\n" "USER" "DURATION" "STATUS" "DIRECTORY"
printf "  %-15s  %-12s  %-12s  %s\n" "----" "--------" "------" "---------"

NOW=$(date +%s)
while IFS='|' read -r user session_id start_epoch cwd <&3; do
    DURATION_SEC=$(( NOW - start_epoch ))
    if [ "$DURATION_SEC" -lt 60 ]; then
        DURATION="<1 min"
    else
        DURATION="$(( DURATION_SEC / 60 )) min"
    fi

    # Find wrapper PID for this session from filename
    SESSION_FILE=$(grep -rl "^$user|$session_id|" "$SESSIONS_DIR"/ 2>/dev/null | head -1)
    WPID=$(basename "$SESSION_FILE" .session)
    if ls "$ACTIVE_DIR"/${user}.${WPID}.active 2>/dev/null | grep -q .; then
        STATUS="PROCESSING"
    else
        STATUS="idle"
    fi

    printf "  %-15s  %-12s  %-12s  %s\n" "$user" "$DURATION" "$STATUS" "$cwd"
done 3< <(cat "$SESSIONS_DIR"/*.session 2>/dev/null)
echo ""
