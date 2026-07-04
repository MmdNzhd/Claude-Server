#!/bin/bash
# commands/status.sh - show active sessions and usage stats
# Usage: claude-server status [--days N]

DAYS=7
for arg in "$@"; do
    case "$arg" in
        --days) shift; DAYS="${1:-7}" ;;
    esac
done

LOG_FILE="/var/log/claude-activity.jsonl"
ACTIVE_DIR="/var/run/claude-active"

BOLD='\033[1m'
GREEN='\033[0;32m'
GRAY='\033[0;37m'
NC='\033[0m'

echo ""
echo -e "${BOLD}=== Claude Server Status ===${NC}"
echo ""

# --- Active sessions ---
echo -e "${BOLD}Active sessions${NC}"
COUNT=0
for f in "$ACTIVE_DIR"/*.active; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    user="${base%%.*}"
    pid="${base##*.}"; pid="${pid%.active}"
    if kill -0 "$pid" 2>/dev/null; then
        echo "  $user  (pid $pid)"
        COUNT=$((COUNT+1))
    fi
done
[ "$COUNT" -eq 0 ] && echo -e "  ${GRAY}none${NC}"

echo ""

if [ ! -f "$LOG_FILE" ]; then
    echo -e "${GRAY}No activity log found.${NC}"
    echo ""
    exit 0
fi

# --- Prompt usage ---
echo -e "${BOLD}Usage — last ${DAYS} days (prompts)${NC}"
SINCE=$(date -d "-${DAYS} days" -Iseconds 2>/dev/null || date -v-${DAYS}d -Iseconds 2>/dev/null)

printf "  %-16s %7s  %8s  %s\n" "User" "Prompts" "Sessions" "Last active"
echo "  ──────────────────────────────────────────────────"

jq -r --arg s "$SINCE" '
    select(.timestamp >= $s) |
    select(.event == "PROMPT" or .event == "IDLE") |
    [.event, .user, .timestamp] | @tsv
' "$LOG_FILE" 2>/dev/null | \
awk '{
    event=$1; user=$2; ts=$3
    if (event == "PROMPT") prompts[user]++
    if (event == "IDLE")   sessions[user]++
    if (ts > last[user])   last[user] = ts
    seen[user] = 1
}
END {
    for (u in seen) { arr[n++] = u }
    for (i=0; i<n-1; i++)
        for (j=0; j<n-1-i; j++)
            if (prompts[arr[j]] < prompts[arr[j+1]]) {
                tmp=arr[j]; arr[j]=arr[j+1]; arr[j+1]=tmp
            }
    for (i=0; i<n; i++) {
        u = arr[i]
        t = substr(last[u],1,16); gsub("T"," ",t)
        printf "  %-16s %7d  %8d  %s\n", u, prompts[u]+0, sessions[u]+0, t
    }
}'

echo ""

# --- Token stats ---
if grep -qE '"event":"STATS"|"event": "STATS"' "$LOG_FILE" 2>/dev/null; then
    echo -e "${BOLD}Token usage (cumulative — from stats cache)${NC}"

    grep -E '"event":"STATS"|"event": "STATS"' "$LOG_FILE" | python3 -c "
import json, sys
users = {}
for line in sys.stdin:
    try:
        d = json.loads(line)
        users[d['user']] = d
    except Exception:
        pass

total_cost = 0.0
rows = []
for u, d in users.items():
    o  = d.get('outputTokens', 0)
    cr = d.get('cacheReadInputTokens', 0)
    cw = d.get('cacheCreationInputTokens', 0)
    cost = (o/1e6)*15 + (cr/1e6)*0.3 + (cw/1e6)*3.75
    total_cost += cost
    fmt = lambda n: f'{n/1e6:.1f}M' if n >= 1e6 else f'{n/1e3:.0f}K' if n >= 1e3 else str(n)
    rows.append((u, fmt(o), cost, d.get('totalMessages', 0)))

rows.sort(key=lambda r: r[2], reverse=True)
print(f\"  {'User':<16} {'Output':>7}  {'Cost USD':>9}  {'Messages':>9}\")
print('  ' + '─'*46)
for u, o, cost, msgs in rows:
    print(f'  {u:<16} {o:>7}  \${cost:>8.2f}  {msgs:>9,}')
print('  ' + '─'*46)
print(f\"  {'TOTAL':<16} {'':>7}  \${total_cost:>8.2f}\")
" 2>/dev/null
    echo ""
fi
