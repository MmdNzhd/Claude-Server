$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }

echo "######## A. FARZAD CURSOR LAST SESSION FULL ERRORS ########"
S grep -nE '\[error\]|\[warning\]|disconnect|ManagementConnection|ExtensionHost|shell environment|extensions control' /home/farzadb/.cursor-server/data/logs/20260718T115406/remoteagent.log

echo
echo "######## B. FARZAD EXTHOST KEY ########"
S grep -nE 'error|fail|EIO|ENOENT|mount|Canceled|workspace|folder' /home/farzadb/.cursor-server/data/logs/20260718T115406/exthost1/remoteexthost.log | head -60

echo
echo "######## C. HOSSEINB TODAY SESSION FULL ########"
S cat /home/hosseinb/.cursor-server/data/logs/20260719T071051/remoteagent.log

echo
echo "######## D. HOSSEINB CONNECT BUFS (tail interesting) ########"
S python3 - <<'PY'
from pathlib import Path
import re
p=Path('/home/hosseinb/.claude/logs')
for f in sorted(p.iterdir(), key=lambda x: x.stat().st_mtime, reverse=True):
    if not f.is_file(): continue
    print('FILE', f.name, 'bytes', f.stat().st_size, 'mtime', f.stat().st_mtime)
    text=f.read_text(errors='replace')
    lines=text.splitlines()
    print('  lines', len(lines))
    print('  FIRST3:')
    for L in lines[:3]: print('   ', L[:220])
    print('  LAST8:')
    for L in lines[-8:]: print('   ', L[:220])
    keys=('ERROR','WARN','FAIL','TIMEOUT','STATUS_','TUNNEL','MOUNT','SSH','ACTIVE','VERSION','CURSOR','shell')
    hit=[L for L in lines if any(k in L.upper() for k in keys)]
    print('  interesting', len(hit))
    for L in hit[-40:]:
        print('   ', L[:240])
    print('---')
PY

echo
echo "######## E. HOSSEINB MOUNT CONFS + CONNECT CONF ########"
S cat /home/hosseinb/.claude-connect.conf
echo '---'
S bash -c 'for f in /home/hosseinb/.claude-mounts.d/*.conf; do echo ==$f==; cat "$f"; done'

echo
echo "######## F. FARZAD MOUNT CONFS + CONNECT CONF ########"
S cat /home/farzadb/.claude-connect.conf
echo '---'
S bash -c 'for f in /home/farzadb/.claude-mounts.d/*.conf; do echo ==$f==; cat "$f"; done'
S ls -la /home/farzadb/.ssh/
S cat /home/farzadb/.ssh/authorized_keys 2>/dev/null | awk '{print NF, substr($0,1,80)}'

echo
echo "######## G. NIMAZ SUCCESS CONTRAST (today after fix) ########"
S ls -1dt /home/nimaz/.cursor-server/data/logs/*/remoteagent.log | head -3
S bash -c 'f=$(ls -1dt /home/nimaz/.cursor-server/data/logs/*/remoteagent.log | head -1); echo FILE=$f; grep -nE "\[error\]|shell environment|ManagementConnection|ExtensionHost" "$f" | head -40'

echo
echo "######## H. SSHD FARZAD 3d + FAILED ########"
S journalctl -u ssh --since "3 days ago" 2>/dev/null | grep -iE 'farzadb|21006|Failed|Invalid' | tail -50

echo
echo "######## I. WHICH SSHD OWNS TUNNELS ########"
S ss -tlnp | grep 127.0.0.1:2
S bash -c 'for p in 21004 21005 21006 21010 22000; do echo -n "port $p: "; ss -tlnp | grep -q ":$p " && echo LISTEN || echo CLOSED; done'
S bash -c 'for pid in $(ss -tlnp | sed -n "s/.*pid=\\([0-9]*\\).*/\\1/p" | sort -u); do
  cmd=$(ps -p $pid -o user=,args= 2>/dev/null)
  [ -n "$cmd" ] && echo "pid=$pid $cmd"
done' | head -40

echo
echo "######## J. BASHRC FARZAD FULL AUTOMOUNT BLOCK + PROFILE ########"
S sed -n '100,140p' /home/farzadb/.bashrc
S cat /home/farzadb/.profile

echo
echo "######## K. TIME BUDGET WITHOUT SKIP (hosseinb) ########"
S bash -c '
export HOME=/home/hosseinb
# time each piece as hosseinb without IDE skip vars
for step in auth cursorauth setup heal automount_full; do
  case $step in
    auth) cmd="timeout 15 /usr/local/bin/claude-auth-sync";;
    cursorauth) cmd="timeout 15 /usr/local/bin/cursor-auth-sync";;
    setup) cmd="timeout 15 /usr/local/bin/laptop-exec-setup --user";;
    heal) cmd="timeout 20 /usr/local/bin/claude-self-heal --quiet";;
    automount_full) cmd="timeout 25 /usr/local/bin/claude-automount";;
  esac
  t0=$(date +%s%N)
  sudo -u hosseinb -H env -u VSCODE_IPC_HOOK_CLI -u CURSOR_AGENT -u TERM_PROGRAM -u VSCODE_RESOLVING_ENVIRONMENT -u VSCODE_PID bash -c "$cmd" >/tmp/step.out 2>/tmp/step.err
  rc=$?
  t1=$(date +%s%N)
  ms=$(( (t1-t0)/1000000 ))
  echo "STEP $step rc=$rc ms=$ms"
  head -c 200 /tmp/step.err; echo
done
'

echo
echo "######## L. WATCHDOG FARZAD ########"
S ps -u farzadb -o pid,etime,cmd --no-headers | head -20
S ls -la /home/farzadb/.local/bin/ 2>/dev/null | head -30
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'deep.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/dd.sh && bash /tmp/dd.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(240000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -EA SilentlyContinue)+'')
if(Test-Path ($out+'.err')){ $e=Get-Content ($out+'.err') -Raw -EA SilentlyContinue; if($e -and $e.Trim()){ Write-Host '---STDERR---'; Write-Host $e } }
