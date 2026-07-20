# -*- coding: utf-8 -*-
import re, sys, json
from datetime import datetime
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
path = r'D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log'
raw = open(path, encoding='utf-8', errors='replace').read().splitlines()
print(f'lines={len(raw)} bytes_file_hint={sum(len(x)+1 for x in raw)}')

ts_re = re.compile(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\] \[(\w+)\](?: \[([0-9a-f]{12})\])? (.*)$')

def pts(s):
    return datetime.strptime(s, '%Y-%m-%d %H:%M:%S.%f')

# --- Exact quit events with ±5 lines and hex of keychar ---
print('\n======== QUIT EVENTS (exact) ========')
for i,l in enumerate(raw,1):
    if 'DECISION: session_key=' in l and 'action=q' in l:
        m = re.search(r'key=(\S+) keychar=(.)', l)
        kc = m.group(2) if m else '?'
        print(f'\n--- L{i} ---')
        print(f'LINE: {l}')
        print(f'keychar={kc!r} codepoints={[hex(ord(c)) for c in kc]} name=U+{ord(kc):04X}')
        for j in range(max(0,i-6), min(len(raw), i+8)):
            mark = '>>>' if j+1==i else '   '
            print(f'{mark}{j+1}:{raw[j][:200]}')

# --- Every PushConf / SSH_END elif / AM mismatch with timing ---
print('\n======== PUSH / AM / SYNTAX TIMELINE ========')
events=[]
for i,l in enumerate(raw,1):
    m=ts_re.match(l)
    if not m: continue
    t,lvl,sid,msg=m.groups()
    keep=False
    kind=''
    if 'PUSH_CONF' in msg: kind='PUSH_CONF'; keep=True
    elif 'syntax error near unexpected token' in msg: kind='SYNTAX_ELIF'; keep=True
    elif 'ACTIVE_MOUNT server_conf=' in msg: kind='AM_MISMATCH'; keep=True
    elif 'ACTIVE_MOUNT=' in msg and 'GIT_MODE=' in msg and 'flags' not in msg and msg.startswith('GIT_MODE='): kind='CLIENT_AM'; keep=True
    elif 'session start v' in msg: kind='SESSION_START'; keep=True
    elif 'SESSION: disconnect' in msg: kind='DISCONNECT'; keep=True
    elif 'CLEAR_MOUNT project=' in msg and 'skip_editor' in msg: kind='CLEAR_MOUNT'; keep=True
    elif 'UPDATE: available' in msg or 'UPDATE: applied_ok' in msg or 'UPDATE: up_to_date' in msg: kind='UPDATE'; keep=True
    elif 'LAUNCH_OK:' in msg: kind='LAUNCH_OK'; keep=True
    elif 'VERDICT_CODE=' in msg: kind='VERDICT'; keep=True
    elif 'DECISION: session_key=' in msg: kind='DECISION'; keep=True
    if keep:
        events.append((pts(t), i, sid or '-', kind, msg[:180]))

for t,i,sid,kind,msg in events:
    print(f'{t.strftime("%H:%M:%S.%f")[:-3]} L{i:4d} [{sid}] {kind:14s} {msg}')

# --- Per-session precise duration and cause ---
print('\n======== SESSION METRICS ========')
sessions=[]
cur=None
for t,i,sid,kind,msg in events:
    if kind=='SESSION_START':
        if cur: sessions.append(cur)
        ver=re.search(r'session start v(\S+)', msg)
        cur={'sid':sid,'ver':ver.group(1) if ver else '?','start':t,'startL':i,'end':None,'end_kind':None,
             'syntax':0,'push':0,'mismatch':0,'launch':None,'verdict':None,'decision':None,'am_client':None}
    if not cur: continue
    if kind=='SYNTAX_ELIF': cur['syntax']+=1
    if kind=='PUSH_CONF': cur['push']+=1
    if kind=='AM_MISMATCH':
        cur['mismatch']+=1
        cur['last_mis']=msg
    if kind=='LAUNCH_OK': cur['launch']=t
    if kind=='VERDICT': cur['verdict']=msg.split('=',1)[-1]
    if kind=='DECISION': cur['decision']=msg
    if kind=='CLIENT_AM':
        am=re.search(r'ACTIVE_MOUNT=(\S+)', msg)
        if am: cur['am_client']=am.group(1)
    if kind in ('DISCONNECT','CLEAR_MOUNT','UPDATE') and kind!='UPDATE':
        cur['end']=t; cur['end_kind']=kind; cur['endL']=i
    if kind=='UPDATE' and 'applied_ok' in msg:
        cur['end']=t; cur['end_kind']='UPDATE_RELAUNCH'; cur['endL']=i
if cur: sessions.append(cur)

for s in sessions:
    dur = (s['end']-s['start']).total_seconds() if s.get('end') else None
    print(json.dumps({
        'sid': s['sid'], 'ver': s['ver'],
        'start': str(s['start']), 'end': str(s.get('end')), 'end_kind': s.get('end_kind'),
        'duration_s': round(dur,3) if dur is not None else None,
        'am_client': s.get('am_client'),
        'syntax_elif': s['syntax'], 'push_conf_lines': s['push'], 'am_mismatch': s['mismatch'],
        'verdict': s.get('verdict'),
        'decision': s.get('decision'),
        'last_mis': s.get('last_mis'),
    }, ensure_ascii=False, indent=2))

# --- Reconstruct .21 quit predicate for each decision ---
print('\n======== QUIT PREDICATE RECONSTRUCTION (.21 behavior) ========')
print('''In v20260719.21 session loop (pre-fix), typical pattern was:
  $action = 'q'   # DEFAULT
  on key: if KeyChar=='r' OR Key==R -> r
          elseif KeyChar=='g' OR Key==G -> g
          elseif KeyChar=='o' OR Key==O -> o
          elseif Key==Enter -> q
          # NOTE: Q/q often also mapped; Farzad decisions show action=q with Key=Q
  then ALWAYS break with action (default q if unmatched)

Observed:
  keychar=q  -> KeyChar matches 'q' OR Key=Q  -> intentional
  keychar=ض  -> KeyChar is ARABIC LETTER DAD U+0636, NOT ascii q
               but Key=ConsoleKey.Q (physical) -> matched via Key==Q OR default action=q
''')

# Prove ض code
c='\u0636'
print(f'ARABIC LETTER DAD: {c!r} U+{ord(c):04X} ascii_range={32<=ord(c)<=126}')

# --- Gaps: classify sleep vs sync ---
print('\n======== GAP CLASSIFICATION ========')
prev=None
for i,l in enumerate(raw,1):
    m=ts_re.match(l)
    if not m: continue
    t=pts(m.group(1))
    if prev:
        gap=(t-prev[0]).total_seconds()
        if gap>=55:
            # count lines skipped in file between
            print(f'gap={gap:.3f}s file_lines_between={i-prev[1]-1}  {prev[0].strftime("%H:%M:%S")}L{prev[1]} -> {t.strftime("%H:%M:%S")}L{i}')
            print(f'  prev: {raw[prev[1]-1][:160]}')
            print(f'  next: {raw[i-1][:160]}')
            # if file_lines_between==0, clock jumped (sleep) with no log lines omitted
            # if many lines missing from expected 800ms loop, either sleep OR unsynced TRACE
    prev=(t,i)

print('\nDONE')
