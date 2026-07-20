#!/bin/bash
f=/home/smart/.claude/logs/connect-20260719.log
echo "=== banner miss while claiming bg_alive (false positive candidates) ==="
python3 - <<'PY'
from pathlib import Path
import re
lines=Path("/home/smart/.claude/logs/connect-20260719.log").read_text(errors="replace").splitlines()
# dedupe by unique timestamp+msg (log may be duplicated in sync)
seen=set(); uniq=[]
for l in lines:
    key=l[:80]+l[l.find(']'):] if ']' in l else l
    # simplify: use full line after first timestamp
    if l in seen: continue
    seen.add(l)
    uniq.append(l)

miss_events=[]
for i,l in enumerate(uniq):
    if 'TUNNEL_BANNER miss' in l or 'TUNNEL_SYNC ok=0' in l or 'TUNNEL_SYNC soft_fail' in l or 'TUNNEL_DROP' in l:
        miss_events.append((i,l))
print('unique miss/drop events', len(miss_events))
for i,l in miss_events[:40]:
    print(l[:180])

print('\n=== CLEAR_MOUNT count unique sessions ===')
for l in uniq:
    if 'CLEAR_MOUNT project' in l or 'connection dropped' in l or 'ORPHAN_TUNNEL' in l:
        print(l[:160])

print('\n=== version from BOOT ===')
for l in uniq:
    if 'session begin' in l.lower() or 'VERSION' in l or 'v202607' in l or 'connect_version' in l.lower() or 'CLIENT' in l:
        if any(x in l for x in ['VERSION','v2026','session begin','========','connect']):
            print(l[:180])
