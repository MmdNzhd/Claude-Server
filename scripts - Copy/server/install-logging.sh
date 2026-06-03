#!/bin/bash
# Claude Code logging + limits installer
# Run as root: sudo bash install-logging.sh

set -e

[ "$EUID" -ne 0 ] && { echo "ERROR: run as root: sudo bash install-logging.sh"; exit 1; }

echo "=== 1 — Locating real claude binary ==="
REAL_BIN="/usr/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"

if [ ! -f "$REAL_BIN" ]; then
    echo "  ERROR: Claude binary not found at $REAL_BIN"
    echo "  Run: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

ln -sf "$REAL_BIN" /usr/local/bin/claude-real
chmod 755 /usr/local/bin/claude-real
echo "  OK: claude-real -> $REAL_BIN"

echo ""
echo "=== 2 — Installing limits config ==="
if [ ! -f /etc/claude-limits.conf ]; then
    cat > /etc/claude-limits.conf << 'LIMITS'
# Claude Code usage limits per user
# Format: username  session_limit  active_limit
# session_limit = max concurrent open sessions
# active_limit  = max concurrent sessions actively processing
# Use 'unlimited' for no limit

smart           unlimited   unlimited
mohammad        unlimited   unlimited
hamed           10          2
reza            1           1
aria            3           2
amirhossein     3           2
amir            3           2
mehrdad         3           2
parsa           3           2
kiana           3           2
hamed.kh        3           2
administrator   3           2
default         3           2
LIMITS
    echo "  OK: /etc/claude-limits.conf created"
else
    echo "  OK: /etc/claude-limits.conf already exists (not overwritten)"
fi

echo ""
echo "=== 3 — Installing wrapper ==="
cat > /usr/local/bin/claude << 'WRAPPER'
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
WRAPPER
chmod 755 /usr/local/bin/claude
echo "  OK: wrapper installed"

echo ""
echo "=== 4 — Installing hook scripts ==="
cat > /usr/local/bin/claude-hook-pre.sh << 'HOOKPRE'
#!/bin/bash
ACTIVE_DIR="/var/run/claude-active"
LOG_FILE="/var/log/claude-activity.jsonl"
LIMITS_CONF="/etc/claude-limits.conf"

mkdir -p "$ACTIVE_DIR"

for f in "$ACTIVE_DIR"/*.active; do
    [ -f "$f" ] || continue
    FPID=$(basename "$f" | rev | cut -d. -f2 | rev)
    kill -0 "$FPID" 2>/dev/null || rm -f "$f"
done

ACTIVE_LIMIT=$(awk -v u="$USER" '
    /^#/ { next }
    $1 == u { print $3; found=1; exit }
    $1 == "default" { def=$3 }
    END { if (!found) print def }
' "$LIMITS_CONF")

ACTIVE_FILE="$ACTIVE_DIR/$USER.$CLAUDE_WRAPPER_PID.active"

if [ ! -f "$ACTIVE_FILE" ]; then
    USER_ACTIVE=$(ls "$ACTIVE_DIR"/${USER}.*.active 2>/dev/null | wc -l)
    if [ "$ACTIVE_LIMIT" != "unlimited" ] && [ "$USER_ACTIVE" -ge "$ACTIVE_LIMIT" ]; then
        echo "Active session limit reached ($USER_ACTIVE/$ACTIVE_LIMIT). Wait for another session to finish processing." >&2
        exit 2
    fi
fi

touch "$ACTIVE_FILE"

printf '{"timestamp":"%s","event":"ACTIVE","user":"%s"}\n' \
    "$(date -Iseconds)" "$USER" >> "$LOG_FILE"
HOOKPRE
chmod 755 /usr/local/bin/claude-hook-pre.sh

cat > /usr/local/bin/claude-hook-stop.sh << 'HOOKSTOP'
#!/bin/bash
LOG_FILE="/var/log/claude-activity.jsonl"
rm -f "/var/run/claude-active/$USER.$CLAUDE_WRAPPER_PID.active"
printf '{"timestamp":"%s","event":"IDLE","user":"%s"}\n' \
    "$(date -Iseconds)" "$USER" >> "$LOG_FILE"
HOOKSTOP
chmod 755 /usr/local/bin/claude-hook-stop.sh

cat > /usr/local/bin/claude-hook-logout-block.sh << 'HOOKLOGOUT'
#!/bin/bash
if [[ "$USER" == "smart" || "$USER" == "root" ]]; then
    exit 0
fi
PROMPT=$(cat | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('prompt',''))" 2>/dev/null)
if [ "$PROMPT" = "/logout" ]; then
    echo "Logout is disabled on this server. Contact admin (smart)." >&2
    exit 2
fi
exit 0
HOOKLOGOUT
chmod 755 /usr/local/bin/claude-hook-logout-block.sh
echo "  OK: hook scripts installed"

echo ""
echo "=== 5 — Installing claude-status ==="
cat > /usr/local/bin/claude-status << 'STATUS'
#!/bin/bash
SESSIONS_DIR="/var/run/claude-sessions"
ACTIVE_DIR="/var/run/claude-active"

for f in "$SESSIONS_DIR"/*.session; do
    [ -f "$f" ] || continue
    PID=$(basename "$f" .session)
    kill -0 "$PID" 2>/dev/null || rm -f "$f"
done

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
    if [ "$DURATION_SEC" -lt 60 ]; then DURATION="<1 min"; else DURATION="$(( DURATION_SEC / 60 )) min"; fi
    SESSION_FILE=$(grep -rl "^$user|$session_id|" "$SESSIONS_DIR"/ 2>/dev/null | head -1)
    WPID=$(basename "$SESSION_FILE" .session)
    if ls "$ACTIVE_DIR"/${user}.${WPID}.active 2>/dev/null | grep -q .; then STATUS="PROCESSING"; else STATUS="idle"; fi
    printf "  %-15s  %-12s  %-12s  %s\n" "$user" "$DURATION" "$STATUS" "$cwd"
done 3< <(cat "$SESSIONS_DIR"/*.session 2>/dev/null)
echo ""
STATUS
chmod 755 /usr/local/bin/claude-status
echo "  OK: claude-status installed"

echo ""
echo "=== 6 — Creating directories and log files ==="
mkdir -p /var/run/claude-sessions
chmod 1777 /var/run/claude-sessions

mkdir -p /var/run/claude-active
chmod 1777 /var/run/claude-active

touch /var/log/claude-usage.jsonl
chmod 666 /var/log/claude-usage.jsonl

touch /var/log/claude-activity.jsonl
chmod 666 /var/log/claude-activity.jsonl
echo "  OK: directories and log files ready"

echo ""
echo "=== 7 — Configuring logrotate ==="
cat > /etc/logrotate.d/claude-usage << 'LOGROTATE'
/var/log/claude-usage.jsonl
/var/log/claude-activity.jsonl {
    weekly
    rotate 13
    compress
    delaycompress
    missingok
    notifempty
    create 0666 root root
}
LOGROTATE
echo "  OK: logrotate configured (weekly, 3 months)"

echo ""
echo "=== 8 — Updating settings.json for all users ==="
SETTINGS_CONTENT='{
  "theme": "dark",
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-logout-block.sh"}]}],
    "PreToolUse": [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-pre.sh"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "/usr/local/bin/claude-hook-stop.sh"}]}]
  }
}'

for user in hamed aria amirhossein amir mehrdad parsa reza kiana hamed.kh administrator smart mohammad; do
    [ -d "/home/$user" ] || continue
    mkdir -p "/home/$user/.claude"
    echo "$SETTINGS_CONTENT" > "/home/$user/.claude/settings.json"
    chown "$user:$user" "/home/$user/.claude/settings.json"
    echo "  OK: $user"
done

echo ""
echo "================================================"
echo "  Installation complete"
echo "================================================"
echo ""
echo "Commands:"
echo "  claude-status"
echo "  tail -f /var/log/claude-usage.jsonl"
echo "  tail -f /var/log/claude-activity.jsonl"
echo "  cat /etc/claude-limits.conf"
echo ""
