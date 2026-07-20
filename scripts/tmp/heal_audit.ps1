$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
echo === LIVE PORTS ===
S ss -tlnp | grep -E '127.0.0.1:21|127.0.0.1:22' || true
echo === USERS STATE ===
S bash -c '
for u in alit aminb farzadb hosseinb hosseinm nimaz zahrak; do
  echo "-- $u --"
  conf=/home/$u/.claude-connect.conf
  port=""; active=""
  if [ -f "$conf" ]; then
    port=$(grep ^TUNNEL_PORT= "$conf" | cut -d= -f2 | tr -d "\r")
    active=$(grep ^ACTIVE_MOUNT= "$conf" | cut -d= -f2 | tr -d "\r")
    echo "port=$port active=$active"
    if [ -n "$port" ]; then
      if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then echo TUNNEL_UP; else echo TUNNEL_DOWN; fi
    fi
  fi
  for m in /home/$u/mounts/*; do
    [ -e "$m" ] || continue
    name=$(basename "$m")
    if grep -q " $m " /proc/mounts; then
      # zombie check
      if timeout 2 ls "$m" >/dev/null 2>&1; then echo "MOUNT_OK $name"; else echo "MOUNT_ZOMBIE $name"; fi
    else
      echo "NOT_MOUNTED $name"
    fi
  done
  # cursor last log
  last=$(ls -1dt /home/$u/.cursor-server/data/logs/*/remoteagent.log 2>/dev/null | head -1)
  if [ -n "$last" ]; then echo "cursor_last=$(stat -c %y "$last" | cut -d. -f1) $(dirname "$last" | xargs basename)"; fi
done
'
echo === AUTOMOUNT SKIP CHECK ===
S grep -n 'VSCODE\|CURSOR\|TERM_PROGRAM' /usr/local/bin/claude-automount | head -20
echo === SELF HEAL BIN ===
S ls -la /usr/local/bin/claude-self-heal /usr/local/bin/claude-automount /usr/local/bin/claude-mount 2>&1
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'heal-audit.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/ha.sh && bash /tmp/ha.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(120000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -ErrorAction SilentlyContinue)+'')
