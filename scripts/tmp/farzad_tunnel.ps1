$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
echo === TUNNEL 21006 ===
S ss -tlnp | grep -E '21006|sshd' | head -20
S ss -tnp | grep 21006 | head -20 || echo no_21006_conn
echo === FARZAD SSH KEY / AUTH LOG ===
S ls -lah /home/farzadb/.ssh/ 2>/dev/null | head -30
S journalctl -u ssh --since '2 days ago' 2>/dev/null | grep -i farza | tail -30 || true
S grep -i farza /var/log/auth.log 2>/dev/null | tail -40 || true
echo === TEST MOUNT LS TIMEOUT ===
timeout 5 sudo -u farzadb ls /home/farzadb/mounts/frontend 2>&1 | head -5 || echo mount_ls_timeout_or_fail
timeout 5 sudo -u farzadb ls /home/farzadb/mounts/backend 2>&1 | head -5 || echo mount_ls_timeout_or_fail
echo === WATCHDOG LOG ===
S ls -lah /home/farzadb/.claude* 2>/dev/null
S find /home/farzadb -name '*watch*' -o -name '*tunnel*' 2>/dev/null | head -20
S journalctl --user farzadb --since '2 days ago' 2>/dev/null | tail -40 || true
echo === HOSSEINB LAST ERRORS FROM BUF ===
S python3 - <<'PY'
from pathlib import Path
p=Path('/home/hosseinb/.claude/logs')
for f in sorted(p.glob('.connect-buf-*.tmp'), key=lambda x: x.stat().st_mtime, reverse=True)[:2]:
    print('FILE', f, 'size', f.stat().st_size)
    lines=f.read_text(errors='replace').splitlines()
    print('lines', len(lines), 'first', lines[0][:120] if lines else '')
    print('last5:')
    for L in lines[-5:]:
        print(L[:200])
    bad=[L for L in lines if any(k in L.upper() for k in ('ERROR','FAIL','TIMEOUT','DENIED','REFUSED','WARN','STATUS_'))]
    print('interesting', len(bad))
    for L in bad[-25:]:
        print(L[:220])
    print('---')
PY
echo === ALL USERS CONNECT CONF MTIME ===
S bash -c 'for u in /home/*; do n=$(basename "$u"); c="$u/.claude-connect.conf"; if [ -f "$c" ]; then echo "$n $(stat -c %y "$c" | cut -d. -f1) $(grep -E "TUNNEL|ACTIVE|GIT" "$c" | tr "\n" " ")"; fi; done'
echo === AUTH FAIL SUMMARY ===
S python3 - <<'PY'
import json
from collections import Counter
c=Counter(); last=None
for line in open('/var/log/claude-auth.log'):
    try: o=json.loads(line)
    except: continue
    if o.get('event')!='PROBE_FAIL': continue
    bp=o.get('body_preview','')
    if 'revoked' in bp: k='revoked'
    elif 'Invalid' in bp: k='invalid'
    else: k='other'
    c[k]+=1; last=o
print(dict(c))
print('last_ts', last.get('timestamp') if last else None)
# last success?
ok=None
for line in open('/var/log/claude-auth.log'):
    try: o=json.loads(line)
    except: continue
    if o.get('ok') is True or o.get('event') in ('PROBE_OK','OK'):
        ok=o
print('last_ok', ok.get('timestamp') if ok else None, ok.get('event') if ok else None)
PY
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'farzad-tunnel.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/fz2.sh && bash /tmp/fz2.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(180000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -ErrorAction SilentlyContinue)+'')
if(Test-Path ($out+'.err')){ $e=Get-Content ($out+'.err') -Raw -EA SilentlyContinue; if($e){Write-Host ERR:; Write-Host $e} }
