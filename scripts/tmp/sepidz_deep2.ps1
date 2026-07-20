$ErrorActionPreference='Continue'
. publish\sepidz-deploy.local.ps1
$pw = [string]$SepidzSudoPassword
$bash = @'
set +e
export LC_ALL=C

echo "======== A) LIVE STATE ========"
date -Is; uptime
echo "-- listen 2100x --"; ss -ltnp 2>/dev/null | grep 2100 || ss -ltn | grep 2100
echo "-- ssh -R related (best effort) --"; ps auxww | grep -E 'sshd:|sshfs' | grep -v grep | head -40
echo "-- sshfs --"; mount | grep sshfs
echo "-- stale mounts? --"; for d in /home/*/mounts/*; do [ -d "$d" ] || continue; timeout 2 ls "$d" >/dev/null 2>&1 && echo "OK $d" || echo "STALE/EIO $d"; done

echo ""
echo "======== B) PER-USER TIMELINE (key events only) ========"
for f in /home/aminb/.claude/logs/connect-20260719.log \
         /home/farzadb/.claude/logs/connect-20260719.log \
         /home/hosseinb/.claude/logs/connect-20260719.log \
         /home/zahrak/.claude/logs/connect-20260719.log \
         /home/smart/.claude/logs/connect-20260719.log; do
  [ -f "$f" ] || continue
  u=$(echo $f|cut -d/ -f3)
  echo ""
  echo "##### $u #####"
  # Extract compact timeline
  grep -E 'session start v|ENSURE_TUNNEL (spawned|ok)|TUNNEL: recovering|CLEAR_MOUNT|STEP end: (Mounting|Opening|SSH tunnel|Server setup)|MOUNT: |session end|ORPHAN_TUNNEL|killing' "$f" \
    | sed 's/\[[A-Z]*\] //g' \
    | awk '{
        # keep timestamp + short msg
        ts=substr($0,1,23);
        msg=$0; sub(/^[^]]*\] /,"",msg); sub(/^[^]]*\] /,"",msg);
        if (length(msg)>120) msg=substr(msg,1,120)"..."
        print ts" | "msg
      }' | tail -60
done

echo ""
echo "======== C) CORRELATE TUNNEL DROP WINDOWS (UTC wall from log local+03:30?) ========"
# Connect logs appear to be laptop local time +03:30. Convert approx by noting patterns.
echo "Events where refused happens AFTER a prior ENSURE_TUNNEL ok in same session (bad), vs only before spawn (normal startup)"
python3 - <<'PY'
import re,glob,os
from collections import defaultdict
files=glob.glob('/home/*/.claude/logs/connect-20260719.log')
pat_ts=re.compile(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\.\d+\]')
for f in sorted(files):
  u=f.split('/')[2]
  lines=open(f,errors='ignore').read().splitlines()
  sessions=[]
  cur=None
  for ln in lines:
    m=pat_ts.match(ln)
    ts=m.group(1) if m else None
    if 'session start v' in ln:
      cur={'start':ts,'ok_tunnel':None,'refused_before':0,'refused_after':0,'recover':0,'mount_ok':0,'open_ok':0,'clear':0,'end':None,'ver':None}
      vm=re.search(r'v(2026\d+\.\d+)', ln)
      if vm: cur['ver']=vm.group(1)
      sessions.append(cur)
    if not cur: continue
    if 'ENSURE_TUNNEL ok' in ln and cur['ok_tunnel'] is None:
      cur['ok_tunnel']=ts
    if 'Connection refused' in ln:
      if cur['ok_tunnel'] is None: cur['refused_before']+=1
      else: cur['refused_after']+=1
    if 'TUNNEL: recovering' in ln: cur['recover']+=1
    if 'STEP end: Mounting files ok' in ln: cur['mount_ok']+=1
    if 'STEP end: Opening Cursor ok' in ln: cur['open_ok']+=1
    if 'CLEAR_MOUNT' in ln: cur['clear']+=1
    if 'session end' in ln: cur['end']=ts
  print(f'USER={u} sessions={len(sessions)} ver_last={sessions[-1]["ver"] if sessions else None}')
  for i,s in enumerate(sessions[-5:],1):
    print(f"  s{i}: start={s['start']} tun_ok={s['ok_tunnel']} refused_pre={s['refused_before']} refused_post={s['refused_after']} recover={s['recover']} mount={s['mount_ok']} open={s['open_ok']} clear={s['clear']} end={s['end']}")
PY

echo ""
echo "======== D) WHY CLEAR_MOUNT / session end? surrounding context ========"
for f in /home/aminb/.claude/logs/connect-20260719.log /home/hosseinb/.claude/logs/connect-20260719.log; do
  u=$(echo $f|cut -d/ -f3)
  echo "---- $u CLEAR_MOUNT contexts ----"
  grep -n 'CLEAR_MOUNT\|TUNNEL: recovering\|session end\|RECOVERY\|already_down\|editor_opened\|STATUS:' "$f" | tail -40
done

echo ""
echo "======== E) CURSOR vs TUNNEL: farzadb/aminb/hosseinb ========"
python3 - <<'PY'
import os,re,glob
from datetime import datetime
# Parse remoteagent disconnect/connect and compare to connect log tunnel events (laptop local time in connect log; cursor logs are UTC server)
# Server cursor logs are UTC. Connect logs look like +03:30 wall (Iran).
# Convert connect ts to UTC by subtracting 3:30 for correlation.

def parse_connect(path):
  ev=[]
  for ln in open(path,errors='ignore'):
    m=re.match(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\.', ln)
    if not m: continue
    ts=datetime.strptime(m.group(1),'%Y-%m-%d %H:%M:%S')
    # treat as Iran local +0330 -> UTC
    # naive: subtract 3h30m
    from datetime import timedelta
    utc=ts-timedelta(hours=3,minutes=30)
    kind=None
    if 'ENSURE_TUNNEL ok' in ln: kind='tunnel_ok'
    elif 'TUNNEL: recovering' in ln: kind='recover'
    elif 'CLEAR_MOUNT' in ln and 'down begin' in ln: kind='clear_mount'
    elif 'session end' in ln: kind='session_end'
    elif 'Opening Cursor ok' in ln: kind='cursor_open'
    elif 'Connection refused' in ln and '210' in ln: kind='refused'
    if kind: ev.append((utc,kind,ln[26:120]))
  return ev

def parse_cursor(user):
  logs=sorted(glob.glob(f'/home/{user}/.cursor-server/data/logs/*/remoteagent.log'))
  ev=[]
  for path in logs[-3:]:
    for ln in open(path,errors='ignore'):
      m=re.match(r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\.\d+', ln)
      if not m: continue
      ts=datetime.strptime(m.group(1),'%Y-%m-%d %H:%M:%S') # already UTC on server
      if 'New connection established' in ln and 'ManagementConnection' in ln:
        ev.append((ts,'cursor_connect',os.path.basename(os.path.dirname(path))))
      if 'disconnected gracefully' in ln:
        ev.append((ts,'cursor_disconnect',os.path.basename(os.path.dirname(path))))
      if 'EIO:' in ln:
        ev.append((ts,'cursor_eio', 'eio'))
  return ev

for user in ['farzadb','aminb','hosseinb','smart']:
  cpath=f'/home/{user}/.claude/logs/connect-20260719.log'
  if not os.path.exists(cpath):
    print(user,'no connect log'); continue
  cev=parse_connect(cpath)
  uev=parse_cursor(user)
  print('\n####',user,'connect_events',len(cev),'cursor_events',len(uev))
  # merge last 30 by time
  all_ev=sorted(cev[-40:]+uev[-40:], key=lambda x:x[0])
  for ts,kind,extra in all_ev[-35:]:
    print(ts.strftime('%H:%M:%S'), kind, str(extra)[:90])
PY

echo ""
echo "======== F) sshd: session churn per user (today) ========"
for u in farzadb aminb hosseinb zahrak nimaz hosseinm; do
  opened=$(grep -c "session opened for user $u" /var/log/auth.log 2>/dev/null || echo 0)
  closed=$(grep -c "session closed for user $u" /var/log/auth.log 2>/dev/null || echo 0)
  # short sessions: Accepted then Disconnected same second-ish - count Disconnect lines
  disc=$(grep -c "Disconnected from user $u" /var/log/auth.log 2>/dev/null || echo 0)
  echo "$u opened=$opened closed=$closed disconnected=$disc"
done
echo "-- sample farzadb rapid reconnect (30s pattern) --"
grep "farzadb" /var/log/auth.log | grep -E 'Accepted publickey|Disconnected from user' | tail -20

echo ""
echo "======== G) Versions in use ========"
for f in /home/*/.claude/logs/connect-20260719.log; do
  u=$(echo $f|cut -d/ -f3)
  ver=$(grep -oE 'session start v[0-9.]+' "$f" | tail -1)
  alias=$(grep -oE 'ALIAS=claude-server[^ ]*' "$f" | tail -1)
  echo "$u $ver $alias"
done

echo DONE_DEEP
'@
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
$pwEsc=$pw.Replace("'","'""'""'")
$remote="printf '%s\n' '$pwEsc' | sudo -S -p '' bash -c 'echo $b64 | base64 -d | bash'"
$o="$env:TEMP\deep2.out"; $e="$env:TEMP\deep2.err"
Remove-Item $o,$e -Force -EA SilentlyContinue
$p=Start-Process ssh -ArgumentList @('-n','-o','BatchMode=yes','-o','ConnectTimeout=15','sepidz@192.168.250.70',$remote) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
if(-not $p.WaitForExit(180000)){ try{$p.Kill()}catch{}; 'TIMEOUT' } else { "exit=$($p.ExitCode)" }
Get-Content $o
