#!/bin/bash
f=/home/smart/.claude/logs/connect-20260719.log
echo "=== raw lines around first DROP (12:38:06 to 12:38:10) ==="
awk '/12:38:06\.|12:38:07\.|12:38:08\.|12:38:09\./' "$f" | grep -v 'TUNNEL_SYNC: bg_alive' | head -80

echo
echo "=== unique connection dropped timestamps ==="
grep -F 'TUNNEL: connection dropped' "$f" | sed 's/\].*//' | sort -u

echo
echo "=== unique RECOVERY_BEGIN ==="
grep -F 'RECOVERY_BEGIN' "$f" | sort -u

echo
echo "=== seconds from Opening Cursor ok -> drop ==="
python3 - <<'PY'
from pathlib import Path
import re
from datetime import datetime
lines=Path("/home/smart/.claude/logs/connect-20260719.log").read_text(errors="replace").splitlines()
opens=[]; drops=[]
for l in lines:
    m=re.search(r'\[(20\d\d-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\]', l)
    if not m: continue
    t=datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f")
    if "STEP end: Opening Cursor ok" in l: opens.append(t)
    if "TUNNEL: connection dropped" in l: drops.append(t)
print("opens", len(opens), "drops", len(drops))
for d in drops:
    prev=[o for o in opens if o<=d]
    if prev:
        print(f"drop {d}  seconds_since_last_open={(d-prev[-1]).total_seconds():.1f}")
    else:
        print(f"drop {d}  no prior open")

# what happened to pid 32264
print("\npid 32264 mentions:")
for l in lines:
    if "32264" in l:
        print(l[:200])
PY

echo
echo "=== version strings in log ==="
grep -E 'version=|v2026|connect-version|CLIENT_VERSION|bundle' "$f" | head -30
