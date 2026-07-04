#!/bin/bash
# claude-latency.sh - show response latency per user from activity log
# Usage: bash claude-latency.sh [--watch] [username]

LOG_FILE="/var/log/claude-activity.jsonl"
WATCH=0
FILTER_USER=""

for arg in "$@"; do
    case "$arg" in
        --watch) WATCH=1 ;;
        *) FILTER_USER="$arg" ;;
    esac
done

analyze() {
    echo "=== Response Latency Report ($(date '+%H:%M:%S')) ==="
    echo ""
    python3 - "$LOG_FILE" "$FILTER_USER" << 'PYEOF'
import sys, json
from datetime import datetime, timezone

log_file = sys.argv[1]
filter_user = sys.argv[2] if len(sys.argv) > 2 else ""

events = []
try:
    with open(log_file) as f:
        for line in f:
            try:
                e = json.loads(line.strip())
                if e.get("event") in ("PROMPT", "IDLE"):
                    events.append(e)
            except:
                pass
except Exception as ex:
    print(f"Cannot read log: {ex}")
    sys.exit(1)

def parse_ts(ts):
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))

# Match each PROMPT to the next IDLE from the same user within 10 minutes
latencies = {}  # user -> [seconds]
recent = []

i = 0
while i < len(events):
    e = events[i]
    if e.get("event") != "PROMPT":
        i += 1
        continue

    user = e.get("user", "")
    if filter_user and user != filter_user:
        i += 1
        continue

    t1 = parse_ts(e["timestamp"])
    # find next IDLE for same user
    for j in range(i + 1, len(events)):
        e2 = events[j]
        if e2.get("event") == "IDLE" and e2.get("user") == user:
            t2 = parse_ts(e2["timestamp"])
            secs = (t2 - t1).total_seconds()
            if 0 < secs < 600:
                latencies.setdefault(user, []).append(secs)
                recent.append((user, secs, e2["timestamp"]))
            i = j
            break
    else:
        i += 1

if not latencies:
    print("No data yet — needs at least one PROMPT+IDLE pair after deploy.")
    sys.exit(0)

print(f"{'USER':<15} {'COUNT':>5} {'MIN':>6} {'AVG':>6} {'MAX':>7}   RECENT")
print("-" * 65)
for user in sorted(latencies):
    vals = latencies[user]
    avg = sum(vals) / len(vals)
    recent_str = "  ".join(f"{v:.1f}s" for v in vals[-4:])
    print(f"{user:<15} {len(vals):>5} {min(vals):>5.1f}s {avg:>5.1f}s {max(vals):>6.1f}s   {recent_str}")

slow = [(u, s, t) for u, s, t in recent if s > 20]
if slow:
    print("")
    print("=== Slowest responses (>20s) ===")
    for u, s, t in sorted(slow, key=lambda x: x[1], reverse=True)[:10]:
        print(f"  {u:<15} {s:>6.1f}s   at {t}")
PYEOF
}

if [ "$WATCH" = "1" ]; then
    while true; do
        clear
        analyze
        echo ""
        echo "(refreshing every 15s — Ctrl+C to stop)"
        sleep 15
    done
else
    analyze
fi
