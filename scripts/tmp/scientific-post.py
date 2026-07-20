from pathlib import Path
import re
from datetime import datetime
LOG=Path('/home/smart/.claude/logs/connect-20260719.log')
TS=re.compile(r'^\[(20\d\d-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\]')
seen=set(); ev=[]
for line in LOG.read_text(errors='replace').splitlines():
    if line in seen: continue
    seen.add(line)
    m=TS.match(line)
    if not m: continue
    ts=datetime.strptime(m.group(1),'%Y-%m-%d %H:%M:%S.%f')
    msg=line.split('] ',3)[-1] if '] ' in line else line
    ev.append((ts,msg))

# Extract pid lifecycle for tunnel ssh
print('=== tunnel pid lifecycle ===')
for ts,msg in ev:
    if any(k in msg for k in ['ENSURE_TUNNEL spawned','ENSURE_TUNNEL ok','ORPHAN_TUNNEL','TUNNEL_STOP','TUNNEL_SYNC ok=0','CLEAR_MOUNT project','unmounted','ENSURE_TUNNEL killing']):
        print(f"{ts} | {msg[:140]}")

print('\n=== formal predicate check on drop branch ===')
# Between last bg_alive and SYNC_DOWN, was there soft_fail or TUNNEL_DROP? 
drop_ts=None
for ts,msg in ev:
    if 'TUNNEL_SYNC ok=0 reason=tunnel_down' in msg:
        drop_ts=ts; break
alives=[ts for ts,msg in ev if 'TUNNEL_SYNC: bg_alive' in msg and ts<drop_ts]
last=alives[-1]
window=[(ts,msg) for ts,msg in ev if last<=ts<=drop_ts]
print(f'last_alive={last} drop={drop_ts} gap={(drop_ts-last).total_seconds():.3f}s')
classes=[]
for ts,msg in window:
    if 'soft_fail' in msg: classes.append('SOFT')
    if 'TUNNEL_DROP' in msg: classes.append('DROP')
    if 'reattach' in msg: classes.append('REATTACH')
    if 'TUNNEL_BANNER miss' in msg: classes.append('MISS')
    if 'tunnel_down' in msg: classes.append('DOWN')
    if 'bg_alive' in msg: classes.append('ALIVE')
print('classes_in_gap:', classes)
print('HAS_SOFT_FAIL', 'SOFT' in classes)
print('HAS_TUNNEL_DROP', 'DROP' in classes)
print('HAS_REATTACH_LOG', 'REATTACH' in classes)
print('MISS_COUNT', classes.count('MISS'))
