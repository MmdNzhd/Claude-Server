#!/bin/bash
# check-usage.sh - show per-user Claude Code usage stats from activity log
# Usage: sudo bash check-usage.sh [--days N] [--user USERNAME]
# No changes made -- read-only.

LOG_FILE="/var/log/claude-activity.jsonl"
DAYS=7
FILTER_USER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --days) DAYS="$2"; shift 2 ;;
        --user) FILTER_USER="$2"; shift 2 ;;
        *) echo "Usage: $0 [--days N] [--user USERNAME]"; exit 1 ;;
    esac
done

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
GRAY='\033[0;37m'
NC='\033[0m'

if [ ! -f "$LOG_FILE" ]; then
    echo "Log file not found: $LOG_FILE"
    exit 1
fi

SINCE=$(date -d "-${DAYS} days" -Iseconds 2>/dev/null || date -v-${DAYS}d -Iseconds 2>/dev/null)

echo ""
echo -e "${BOLD}=== Claude Usage Report — last ${DAYS} days ===${NC}"
echo -e "${GRAY}Log: $LOG_FILE${NC}"
echo ""

# --- Summary table ---
echo -e "${BOLD}  User             Prompts  Sessions  Last active${NC}"
echo "  ──────────────────────────────────────────────────────"

jq -r --arg since "$SINCE" --arg user "$FILTER_USER" '
    select(.timestamp >= $since) |
    select($user == "" or .user == $user) |
    [.event, .user, .timestamp] | @tsv
' "$LOG_FILE" 2>/dev/null | \
awk '
BEGIN { OFS="\t" }
{
    event=$1; user=$2; ts=$3
    if (event == "PROMPT") { prompts[user]++ }
    if (event == "IDLE")   { sessions[user]++ }
    if (ts > last[user])   { last[user] = ts }
    all_users[user] = 1
}
END {
    # collect and sort by prompt count (descending)
    n = 0
    for (u in all_users) { users[n++] = u }
    # bubble sort by prompts desc
    for (i = 0; i < n-1; i++)
        for (j = 0; j < n-1-i; j++)
            if (prompts[users[j]] < prompts[users[j+1]]) {
                tmp = users[j]; users[j] = users[j+1]; users[j+1] = tmp
            }
    for (i = 0; i < n; i++) {
        u = users[i]
        lastdate = substr(last[u], 1, 16)
        gsub("T", " ", lastdate)
        printf "  %-16s  %7d  %8d  %s\n", u, prompts[u]+0, sessions[u]+0, lastdate
    }
}
'

echo ""

# --- Daily breakdown ---
echo -e "${BOLD}=== Daily breakdown ===${NC}"
echo ""

jq -r --arg since "$SINCE" --arg user "$FILTER_USER" '
    select(.timestamp >= $since) |
    select(.event == "PROMPT") |
    select($user == "" or .user == $user) |
    [.timestamp[0:10], .user] | @tsv
' "$LOG_FILE" 2>/dev/null | \
awk '
{
    day=$1; user=$2
    count[day][user]++
    days[day] = 1
    users[user] = 1
}
END {
    # sort days
    n = 0
    for (d in days) { daylist[n++] = d }
    for (i = 0; i < n-1; i++)
        for (j = 0; j < n-1-i; j++)
            if (daylist[j] > daylist[j+1]) {
                tmp = daylist[j]; daylist[j] = daylist[j+1]; daylist[j+1] = tmp
            }

    for (i = 0; i < n; i++) {
        d = daylist[i]
        printf "  %s\n", d
        # collect users for this day
        m = 0
        for (u in users) {
            if (count[d][u] > 0) { ul[m++] = u }
        }
        # sort by count desc
        for (a = 0; a < m-1; a++)
            for (b = 0; b < m-1-a; b++)
                if (count[d][ul[b]] < count[d][ul[b+1]]) {
                    tmp = ul[b]; ul[b] = ul[b+1]; ul[b+1] = tmp
                }
        for (j = 0; j < m; j++) {
            u = ul[j]
            bar = ""
            for (k = 0; k < count[d][u]; k++) bar = bar "#"
            if (length(bar) > 50) bar = substr(bar, 1, 50) "+"
            printf "    %-14s %3d  %s\n", u, count[d][u], bar
        }
        # clear ul for next day
        for (j = 0; j < m; j++) delete ul[j]
        m = 0
        print ""
    }
}
'
