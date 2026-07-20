from pathlib import Path
import re
from datetime import datetime
LOG=Path('/home/smart/.claude/logs/connect-20260719.log')
seen=set(); lines=[]
for l in LOG.read_text(errors='replace').splitlines():
    if l in seen: continue
    seen.add(l); lines.append(l)
# self-heal durations
pat_b=re.compile(r'\[(.*?)\] .*SSH_BEGIN cmd=.*claude-self-heal')
pat_e=re.compile(r'\[(.*?)\] .*SSH_END exit=(\S+) ms=(\d+) out=')
heals=[]
pending=None
for l in lines:
    mb=pat_b.search(l)
    if mb:
        pending=datetime.strptime(mb.group(1), '%Y-%m-%d %H:%M:%S.%f')
        continue
    if pending and 'SSH_END' in l and 'claude-self-heal' not in l:
        # next SSH_END after begin might be the heal - check nearby
        me=re.search(r'\[(.*?)\] .*SSH_END exit=(\S+) ms=(\d+)', l)
        if me:
            # only if within 30s and this end follows heal begin
            te=datetime.strptime(me.group(1), '%Y-%m-%d %H:%M:%S.%f')
            if 0 <= (te-pending).total_seconds() < 60:
                # verify previous begin was heal by checking ms from debug lines
                heals.append(int(me.group(3)))
            pending=None
# better: look for exit lines that mention heal in recent debug, or ms from heal SSH_END with empty that follows
print('heal_ssh_end_ms_samples (heuristic next SSH_END):', heals[:20], 'n=', len(heals))
if heals:
    heals.sort()
    print(f'  min={heals[0]} p50={heals[len(heals)//2]} max={heals[-1]} sum={sum(heals)}')

# PUSH_CONF count vs self-heal begins
pc=sum(1 for l in lines if 'PUSH_CONF laptop_user' in l)
sh=sum(1 for l in lines if 'SSH_BEGIN cmd=' in l and 'claude-self-heal' in l)
print(f'PUSH_CONF_lines={pc} SELF_HEAL_BEGINS={sh}')

# port slot changes
for l in lines:
    if 'ENSURE_TUNNEL spawned' in l or 'CONNECT_VERSION' in l and 'PORT=' in l:
        if 'spawned' in l or re.search(r'PORT=2100', l):
            if 'spawned' in l or 'PORT=2100' in l:
                print(l[1:80] if False else l[:160])
