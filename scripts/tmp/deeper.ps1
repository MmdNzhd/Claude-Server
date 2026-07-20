$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }

echo "######## 1. DEPLOYED BINARY FINGERPRINTS ########"
S bash -c '
for f in /usr/local/bin/claude-automount /usr/local/bin/claude-self-heal /usr/local/bin/claude-watchdog /usr/local/lib/claude-mount; do
  echo "-- $f --"
  ls -la "$f"
  sha256sum "$f" | awk "{print \$1}"
  # key markers
  grep -cE "VSCODE_RESOLVING|_heal_active_remount|need_remount|claude-last-active|_heal_connect_log|timeout 4|timeout 8|_ppargs" "$f" 2>/dev/null || true
done
ls -la /etc/cron.d/claude-self-heal
cat /etc/cron.d/claude-self-heal
'

echo "######## 2. LIVE MATRIX + WATCHDOG PIDS ########"
S bash -c '
date -u
for u in alit aminb farzadb hosseinb hosseinm nimaz zahrak sepidz; do
  conf=/home/$u/.claude-connect.conf
  [ -f "$conf" ] || continue
  port=$(grep ^TUNNEL_PORT= "$conf"|cut -d= -f2|tr -d "\r")
  active=$(grep ^ACTIVE_MOUNT= "$conf"|cut -d= -f2|tr -d "\r")
  last=$(cat /home/$u/.cache/claude-last-active-mount 2>/dev/null|tr -d "\r\n")
  if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then t=UP; else t=DOWN; fi
  wd=$(pgrep -u $u -af claude-watchdog 2>/dev/null | head -1)
  echo "USER=$u tunnel=$t port=$port active=${active:-EMPTY} last=${last:-NONE}"
  echo "  wd=${wd:-NONE}"
  for m in /home/$u/mounts/*; do
    [ -e "$m" ] || continue
    n=$(basename "$m")
    if grep -q " $m " /proc/mounts; then
      src=$(awk -v p="$m" "$2==p{print $1}" /proc/mounts)
      if timeout 2 ls "$m" >/dev/null 2>&1; then st=OK; else st=ZOMBIE; fi
      echo "  mount $n=$st src=$src"
    fi
  done
  # cursor last session age
  ra=$(ls -1dt /home/$u/.cursor-server/data/logs/*/remoteagent.log 2>/dev/null|head -1)
  if [ -n "$ra" ]; then
    echo "  cursor=$(stat -c %y "$ra"|cut -d. -f1) shellfail=$(grep -c "Unable to resolve your shell environment" "$ra" 2>/dev/null||echo 0)"
  fi
done
'

echo "######## 3. HOSSEINB FINALIZED CONNECT LOG (deep) ########"
S bash -c '
ls -lah /home/hosseinb/.claude/logs/
for f in /home/hosseinb/.claude/logs/connect-*.log; do
  [ -f "$f" ] || continue
  echo "==== $f bytes=$(wc -c <"$f") lines=$(wc -l <"$f") ===="
  # extract structured events
  grep -E "STATUS_|ERROR|WARN|VERSION|ACTIVE_MOUNT|TUNNEL|MOUNT|CURSOR|EDITOR|FAIL|TIMEOUT|ssh|Launch|PROC_" "$f" | tail -60
  echo "--- first 5 ---"
  head -5 "$f"
  echo "--- last 10 ---"
  tail -10 "$f"
done
'

echo "######## 4. TIME BUDGET BREAKDOWN (no skip vs skip) ########"
S bash -c '
u=hosseinb
echo "WITH VSCODE_RESOLVING:"
/usr/bin/time -f "real=%e" timeout 20 sudo -u $u -H env VSCODE_RESOLVING_ENVIRONMENT=1 bash -ilc "echo OK" 2>&1 | tail -3
echo "WITH parent-like skip via CURSOR_AGENT:"
/usr/bin/time -f "real=%e" timeout 20 sudo -u $u -H env CURSOR_AGENT=1 bash -ilc "echo OK" 2>&1 | tail -3
echo "WITHOUT skip (full login path) timed:"
/usr/bin/time -f "real=%e" timeout 35 sudo -u $u -H env -u VSCODE_RESOLVING_ENVIRONMENT -u VSCODE_PID -u CURSOR_AGENT -u TERM_PROGRAM -u VSCODE_IPC_HOOK_CLI bash -ilc "echo OK" 2>&1 | tail -5
'

echo "######## 5. SELF-HEAL DRY RUN FARZAD (tunnel down path) ########"
S bash -c 'sudo -u farzadb -H /usr/local/bin/claude-self-heal 2>&1; echo exit:$?; grep farzadb /proc/mounts || echo no_mounts; pgrep -u farzadb -af sshfs || echo no_sshfs'

echo "######## 6. WATCHDOG LOCKS / ORPHANS ########"
S bash -c '
ls -la /tmp/claude-watchdog-*.pid 2>/dev/null || echo no_locks
for f in /tmp/claude-watchdog-*.pid; do
  [ -f "$f" ] || continue
  pid=$(cat "$f")
  echo "$f pid=$pid alive=$(kill -0 $pid 2>/dev/null && echo yes || echo no)"
done
# old orphan watchdogs?
ps -eo user,pid,etime,cmd | grep -E "claude-watchdog|claude-automount" | grep -v grep
'

echo "######## 7. SSHD TUNNEL OWNERSHIP + FORWARD ########"
S bash -c '
ss -tlnp | grep 127.0.0.1:2
for pid in 3984521 3705727 3989890 3825454; do
  if [ -d /proc/$pid ]; then
    echo "pid=$pid user=$(ps -p $pid -o user=) cmd=$(ps -p $pid -o args= | head -c 120)"
    # try to see env for SSH_CONNECTION
    tr "\0" "\n" < /proc/$pid/environ 2>/dev/null | grep -E "SSH_|USER=" | head -10
  fi
done
'

echo "######## 8. REMAINING RISK SCAN ########"
S bash -c '
# bashrc without timeout
echo "-- bashrc missing timeout --"
for br in /home/*/.bashrc; do
  grep -q claude-automount "$br" 2>/dev/null || continue
  grep -qE "timeout[[:space:]]+10" "$br" || echo "MISSING_TIMEOUT $br"
done
# automount in bashrc still calls without .local fallback?
echo "-- bashrc automount lines --"
for u in farzadb hosseinb nimaz; do
  echo USER=$u
  sed -n "/Claude Code auto-mount/,/end Claude/p" /home/$u/.bashrc
done
# users with tunnel up but no watchdog
echo "-- tunnel up no watchdog --"
for u in hosseinb hosseinm nimaz sepidz; do
  conf=/home/$u/.claude-connect.conf
  port=$(grep ^TUNNEL_PORT= "$conf"|cut -d= -f2|tr -d "\r")
  if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then
    pgrep -u $u -f claude-watchdog >/dev/null || echo "NO_WD $u"
  fi
done
# stale vscode agent hosts (noise)
echo "-- long-lived vscode agents --"
ps -eo user,pid,etime,cmd | grep "vscode-server/code-" | grep -v grep | awk "{print \$1,\$2,\$3}" | head -20
'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'deeper.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/deep2.sh && bash /tmp/deep2.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(300000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -EA SilentlyContinue)+'')
