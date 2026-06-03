#!/bin/bash
REAL_CLAUDE="/usr/local/bin/claude-real"
LOG_FILE="/var/log/claude-usage.jsonl"
SESSIONS_DIR="/var/run/claude-sessions"
LIMITS_CONF="/etc/claude-limits.conf"

get_limit() {
    local user="$1" field="$2"
    awk -v u="$user" -v f="$field" '
        /^#/ { next }
        $1 == u { print (f==1)?$2:$3; found=1; exit }
        $1 == "default" { def=(f==1)?$2:$3 }
        END { if (!found) print def }
    ' "$LIMITS_CONF"
}

if [[ "$1" == "logout" ]]; then
    if [[ "$USER" == "smart" || "$USER" == "root" ]]; then
        "$REAL_CLAUDE" "$@"
        exit $?
    else
        echo "Logout is disabled. Contact admin." >&2
        exit 1
    fi
fi

SESSION_LIMIT=$(get_limit "$USER" 1)

mkdir -p "$SESSIONS_DIR"

for f in "$SESSIONS_DIR"/*.session; do
    [ -f "$f" ] || continue
    grep -q "^$USER|" "$f" 2>/dev/null || continue
    SPID=$(basename "$f" .session)
    kill -0 "$SPID" 2>/dev/null || rm -f "$f" 2>/dev/null
done

if [ "$SESSION_LIMIT" != "unlimited" ]; then
    USER_SESSIONS=$(ls "$SESSIONS_DIR"/*.session 2>/dev/null | xargs -r grep -l "^$USER|" 2>/dev/null | wc -l)
    if [ "$USER_SESSIONS" -ge "$SESSION_LIMIT" ]; then
        echo "Session limit reached ($USER_SESSIONS/$SESSION_LIMIT). Dude, you already have a session open — close it first, genius. DALGHAK🤣😖"
        exit 1
    fi
fi

SESSION_ID=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)
PID=$$
CWD=$(pwd)
START_EPOCH=$(date +%s)
TIMESTAMP=$(date -Iseconds)

echo "$USER|$SESSION_ID|$START_EPOCH|$CWD" > "$SESSIONS_DIR/$PID.session"
CONCURRENT=$(ls "$SESSIONS_DIR"/*.session 2>/dev/null | wc -l)

printf '{"timestamp":"%s","event":"START","user":"%s","session_id":"%s","pid":%d,"cwd":"%s","concurrent_sessions":%d}\n' \
    "$TIMESTAMP" "$USER" "$SESSION_ID" "$PID" "$CWD" "$CONCURRENT" \
    >> "$LOG_FILE"

cleanup() {
    local EXIT_CODE=${1:-$?}
    local END_EPOCH=$(date +%s)
    local DURATION=$(( END_EPOCH - START_EPOCH ))
    local END_TIMESTAMP=$(date -Iseconds)
    rm -f "$SESSIONS_DIR/$PID.session"
    rm -f "/var/run/claude-active/$USER.$PID.active"
    local CONCURRENT_END=$(ls "$SESSIONS_DIR"/*.session 2>/dev/null | wc -l)
    printf '{"timestamp":"%s","event":"END","user":"%s","session_id":"%s","pid":%d,"cwd":"%s","duration_seconds":%d,"exit_code":%d,"concurrent_sessions":%d}\n' \
        "$END_TIMESTAMP" "$USER" "$SESSION_ID" "$PID" "$CWD" "$DURATION" "$EXIT_CODE" "$CONCURRENT_END" \
        >> "$LOG_FILE"
}

trap 'cleanup 130; exit 130' INT
trap 'cleanup 143; exit 143' TERM
trap 'cleanup $?' EXIT

export CLAUDE_WRAPPER_PID=$PID

"$REAL_CLAUDE" "$@"
exit $?
