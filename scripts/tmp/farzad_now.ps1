$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
echo === NOW ===
date -u
echo === FARZADB HOME CLAUDE ===
S ls -lah /home/farzadb/.claude 2>/dev/null || echo no_claude
S ls -lah /home/farzadb/.claude/logs 2>/dev/null || echo no_logs_dir
S find /home/farzadb -maxdepth 4 -type f \( -name 'connect*.log' -o -name '.connect-buf*' -o -name '*connect*' \) 2>/dev/null | head -40
echo === FARZADB CONNECT CONF ===
S cat /home/farzadb/.claude-connect.conf 2>/dev/null || echo no_conf
S ls -lah /home/farzadb/.claude-mounts.d 2>/dev/null
S cat /home/farzadb/.claude-mounts.d/*.conf 2>/dev/null
echo === FARZADB MOUNTS ===
S ls -lah /home/farzadb/mounts 2>/dev/null
S grep farzadb /proc/mounts || echo no_sshfs_in_proc
echo === FARZADB PROCESSES ===
S ps -u farzadb -o pid,etime,cmd --no-headers 2>/dev/null | head -40
echo === FARZADB SSHD / WHO ===
S who | grep -i farza || true
S ss -tnp 2>/dev/null | grep -i farza | head -20 || true
echo === ALL USER LOG BUFS ===
S find /home -type f \( -name '.connect-buf-*.tmp' -o -name 'connect-*.log' \) -printf '%p %s %TY-%Tm-%TdT%TH:%TM\n' 2>/dev/null | sort
echo === AUTH LAST 3 ===
S tail -n 3 /var/log/claude-auth.log
echo === BUNDLE ===
cat /usr/local/share/claude-client/connect-version.txt
echo === RECENT AUTH FAILS COUNT 1h ===
S python3 - <<'PY'
from datetime import datetime, timezone, timedelta
import json
cut=datetime.now(timezone.utc)-timedelta(hours=2)
n=0; last=None
for line in open('/var/log/claude-auth.log'):
    if 'PROBE_FAIL' not in line: continue
    try: o=json.loads(line)
    except: continue
    ts=o.get('timestamp','').replace('Z','+00:00')
    try: t=datetime.fromisoformat(ts)
    except: continue
    if t>=cut:
        n+=1; last=o
print('fails_2h',n)
if last:
    bp=last.get('body_preview','')[:160]
    print('last', last.get('timestamp'), bp)
PY
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'farzad-now.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/fz.sh && bash /tmp/fz.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(120000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -ErrorAction SilentlyContinue)+'')
if(Test-Path ($out+'.err')){ $e=Get-Content ($out+'.err') -Raw -EA SilentlyContinue; if($e){Write-Host ERR:; Write-Host $e} }
