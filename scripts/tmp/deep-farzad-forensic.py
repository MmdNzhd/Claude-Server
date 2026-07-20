# -*- coding: utf-8 -*-
import re, sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
path = r'D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log'
lines = open(path, encoding='utf-8', errors='replace').readlines()
print(f'FILE lines={len(lines)} bytes={sum(len(x) for x in lines)}')

ts_re = re.compile(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?)\]')
sid_re = re.compile(r'\[([0-9a-f]{12})\]')

def parse_ts(s):
    for fmt in ('%Y-%m-%d %H:%M:%S.%f', '%Y-%m-%d %H:%M:%S'):
        try: return datetime.strptime(s, fmt)
        except: pass
    return None

# --- dedupe ---
raw = [l.rstrip('\n') for l in lines]
uniq = []
dup = 0
seen_window = {}
for i,l in enumerate(raw,1):
    # fingerprint without worrying about exact
    key = l
    if uniq and uniq[-1][1] == key:
        dup += 1
        continue
    uniq.append((i, key))
print(f'DEDUPE consecutive_dup_lines={dup} unique_consecutive={len(uniq)}')

# --- sessions ---
sessions = []
cur = None
for i,l in uniq:
    m = re.search(r'session start v(\S+) .*?(?:session=([0-9a-f]{12}))?', l)
    if 'session start v' in l:
        ver = re.search(r'session start v(\S+)', l)
        sid = sid_re.search(l)
        ts = ts_re.match(l)
        if cur: sessions.append(cur)
        cur = {
            'start_line': i, 'start_ts': ts.group(1) if ts else '?',
            'ver': ver.group(1) if ver else '?',
            'sid': sid.group(1) if sid else (re.search(r'session=([0-9a-f]{12})', l).group(1) if re.search(r'session=([0-9a-f]{12})', l) else '?'),
            'project': None, 'mount_ok': None, 'verdict': None, 'end': None, 'end_line': None,
            'clear_mount': 0, 'syntax_err': 0, 'status_ok': 0, 'launch_ok': False,
            'decisions': [], 'updates': [], 'active_mismatch': []
        }
        continue
    if not cur: continue
    if 'ACTIVE_MOUNT=' in l and 'GIT_MODE=' in l:
        am = re.search(r'ACTIVE_MOUNT=(\S+)', l)
        if am: cur['project'] = am.group(1)
    if 'VERDICT_CODE=' in l:
        cur['verdict'] = l.split('VERDICT_CODE=',1)[1].strip()
    if 'LAUNCH_OK:' in l: cur['launch_ok'] = True
    if 'MOUNT ok=' in l:
        cur['mount_ok'] = 'ok=True' in l or 'MOUNT ok=True' in l
    if 'CLEAR_MOUNT project=' in l: cur['clear_mount'] += 1
    if 'syntax error near unexpected token' in l: cur['syntax_err'] += 1
    if 'STATUS_OK' in l: cur['status_ok'] += 1
    if 'UPDATE:' in l: cur['updates'].append((i, l[l.find('UPDATE:'):][:120]))
    if 'ACTIVE_MOUNT server_conf=' in l:
        cur['active_mismatch'].append((i, l[l.find('ACTIVE_MOUNT'):][:160]))
    if 'DECISION: session_key' in l or "Write-ConnectDecision 'session_key'" in l or 'session_key' in l and 'action=' in l:
        cur['decisions'].append((i, l.strip()[-180:]))
    if 'SESSION: disconnect' in l or 'CLEAR_MOUNT stopping editor' in l:
        cur['end'] = 'disconnect' if 'disconnect' in l else cur.get('end') or 'clear_mount'
        cur['end_line'] = i
    if 'UPDATE: applied_ok' in l or 'UPDATE: available' in l:
        cur['end'] = cur.get('end') or 'update_relaunch'
        cur['end_line'] = i

if cur: sessions.append(cur)

print('\n======== SESSION TABLE ========')
for s in sessions:
    print(f"sid={s['sid']} ver={s['ver']} start={s['start_ts']} L{s['start_line']} project={s['project']} launch_ok={s['launch_ok']} verdict={s['verdict']} status_ok={s['status_ok']} clear={s['clear_mount']} syntax_err={s['syntax_err']} end={s['end']} endL={s['end_line']}")
    for d in s['decisions']:
        print(f"  DECISION L{d[0]}: {d[1]}")
    for u in s['updates']:
        print(f"  UPDATE L{u[0]}: {u[1]}")
    for a in s['active_mismatch'][:3]:
        print(f"  AM L{a[0]}: {a[1]}")

# --- global counters ---
print('\n======== GLOBAL COUNTS ========')
patterns = {
    'session_start': r'session start v',
    'UPDATE_any': r'UPDATE:',
    'UPDATE_available': r'UPDATE: available',
    'UPDATE_upto': r'UPDATE: up_to_date',
    'UPDATE_applied': r'UPDATE: applied_ok',
    'CLEAR_MOUNT': r'CLEAR_MOUNT project=',
    'syntax_elif': r'syntax error near unexpected token',
    'STATUS_OK': r'STATUS_OK',
    'tunnel_down|TUNNEL.*drop': r'tunnel_down|connection dropped|TUNNEL: connection dropped',
    'RECOVERY': r'RECOVERY_',
    'soft_fail': r'soft_fail',
    'ENSURE': r'ENSURE_TUNNEL',
    'ORPHAN': r'ORPHAN',
    'LAUNCH_OK': r'LAUNCH_OK:',
    'CURSOR_ON_FOLDER_OK': r'VERDICT_CODE=CURSOR_ON_FOLDER_OK',
    'WARN_menu': r'Enter a number or a/e/d/c/g/q',
    'AM_mismatch_line': r'ACTIVE_MOUNT server_conf=',
    'PUSH_CONF': r'PUSH_CONF',
    'EditorSeen|sticky': r'EditorSeenOpen|editorLabel=sticky|sticky',
}
for name,pat in patterns.items():
    c=sum(1 for _,l in uniq if re.search(pat,l,re.I))
    print(f'{name}: {c}')

# versions seen
vers=Counter()
for _,l in uniq:
    m=re.search(r'(?:session start |up_to_date |available .*-> |CONNECT_VERSION=)v?(\d{8}\.\d+)', l)
    if m: vers[m.group(1)] += 1
print('version_mentions', dict(vers))

# --- decision classification ---
print('\n======== ALL session_key DECISIONS ========')
for i,l in uniq:
    if 'session_key' in l and 'action=' in l:
        print(f'L{i}: {l[-200:]}')

# --- STATUS_OK gaps ---
print('\n======== STATUS_OK GAPS >60s ========')
prev=None
for i,l in uniq:
    if 'STATUS_OK' not in l: continue
    ts=ts_re.match(l)
    if not ts: continue
    t=parse_ts(ts.group(1))
    if prev and t:
        gap=(t-prev[0]).total_seconds()
        if gap>=60:
            print(f'GAP {gap:.0f}s between L{prev[1]} {prev[0]} -> L{i} {t} | {l[-100:]}')
    if t: prev=(t,i)

# --- syntax error samples ---
print('\n======== SYNTAX ERROR SAMPLES ========')
n=0
for i,l in uniq:
    if 'syntax error' in l:
        n+=1
        if n<=5: print(f'L{i}: {l[:240]}')
print(f'total_syntax={n}')

# --- last 30 unique ---
print('\n======== LAST 25 UNIQUE ========')
for i,l in uniq[-25:]:
    print(f'L{i}: {l[:220]}')

# time range
times=[parse_ts(ts_re.match(l).group(1)) for _,l in uniq if ts_re.match(l)]
times=[t for t in times if t]
if times:
    print(f'\nTIME_RANGE {times[0]} -> {times[-1]} duration_h={(times[-1]-times[0]).total_seconds()/3600:.2f}')
