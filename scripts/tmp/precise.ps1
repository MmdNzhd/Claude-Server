$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }

echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "BUNDLE=$(cat /usr/local/share/claude-client/connect-version.txt 2>/dev/null)"
echo
echo "BIN"
S bash -c '
for f in /usr/local/bin/claude-automount /usr/local/bin/claude-self-heal /usr/local/bin/claude-watchdog; do
  printf "%s size=%s sha256=%s mtime=%s\n" "$f" "$(stat -c%s "$f")" "$(sha256sum "$f"|awk "{print \$1}")" "$(stat -c %y "$f"|cut -d. -f1)"
done
'
echo
echo "PORTS"
S ss -tlnp | awk '/127.0.0.1:2/{print}'
echo
echo "MATRIX"
S bash -c '
printf "%-10s %-6s %-6s %-16s %-16s %-8s %-10s %s\n" USER TUN PORT ACTIVE LAST WD MOUNTS CURSOR_LAST
for u in alit aminb farzadb hosseinb hosseinm nimaz zahrak; do
  conf=/home/$u/.claude-connect.conf
  [ -f "$conf" ] || continue
  port=$(grep ^TUNNEL_PORT= "$conf"|cut -d= -f2|tr -d "\r")
  active=$(grep ^ACTIVE_MOUNT= "$conf"|cut -d= -f2|tr -d "\r")
  last=$(cat /home/$u/.cache/claude-last-active-mount 2>/dev/null|tr -d "\r\n")
  if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then t=UP; else t=DOWN; fi
  wd=$(pgrep -u $u -f "/usr/local/bin/claude-watchdog" >/dev/null && echo yes || echo no)
  ms=""
  for m in /home/$u/mounts/*; do
    [ -e "$m" ] || continue
    n=$(basename "$m")
    if grep -q " $m " /proc/mounts; then
      if timeout 2 ls "$m" >/dev/null 2>&1; then ms="${ms}${n}=OK "; else ms="${ms}${n}=ZOMBIE "; fi
    fi
  done
  [ -z "$ms" ] && ms="-"
  ra=$(ls -1dt /home/$u/.cursor-server/data/logs/*/remoteagent.log 2>/dev/null|head -1)
  if [ -n "$ra" ]; then cl=$(stat -c %y "$ra"|cut -d. -f1); else cl=-; fi
  printf "%-10s %-6s %-6s %-16s %-16s %-8s %-10s %s\n" "$u" "$t" "$port" "${active:--}" "${last:--}" "$wd" "$ms" "$cl"
done
'

echo
echo "HOSSEINB_SMOKING_GUN_LINES"
S bash -c '
f=/home/hosseinb/.claude/logs/connect-20260719.log
# exact lines with ACTIVE_MOUNT empty printf and CLEAR_MOUNT and version
grep -n "ACTIVE_MOUNT=%s" "$f" | head -5
grep -n "out=ACTIVE_MOUNT=" "$f" | head -5
grep -n "CLEAR_MOUNT project" "$f" | head -5
grep -n "CONNECT_VERSION=" "$f" | head -3
grep -n "ScriptDir=" "$f" | head -3
grep -n "STATUS_OK\|STATUS:" "$f" | tail -5
# count
echo "counts: CLEAR_MOUNT=$(grep -c CLEAR_MOUNT "$f") ACTIVE_EMPTY_OUT=$(grep -c "out=ACTIVE_MOUNT=$" "$f") VERSION_LINES=$(grep -c CONNECT_VERSION "$f")"
echo "file_bytes=$(stat -c%s "$f") file_lines=$(wc -l <"$f")"
'

echo
echo "FARZAD_CURSOR_EXACT"
S bash -c '
f=/home/farzadb/.cursor-server/data/logs/20260718T115406/remoteagent.log
echo "file=$f bytes=$(stat -c%s "$f") lines=$(wc -l <"$f")"
grep -n "Extension host agent started\|ManagementConnection\|shell environment\|disconnected\|shutting down" "$f"
echo "---"
echo "exthost workspace:"
grep -n "cwd:" /home/farzadb/.cursor-server/data/logs/20260718T115406/exthost1/remoteexthost.log | head -3
'

echo
echo "HOSSEINB_CURSOR_EXACT"
S cat /home/hosseinb/.cursor-server/data/logs/20260719T071051/remoteagent.log | nl -ba | sed -n "1,25p"

echo
echo "TIMING_MS"
S bash -c '
u=hosseinb
for label envflag in "skip_resolving:VSCODE_RESOLVING_ENVIRONMENT=1" "skip_agent:CURSOR_AGENT=1" "noskip:CLEAR"; do
  name=${label%%:*}; flag=${label#*:}
  if [ "$flag" = CLEAR ]; then
    envcmd="env -u VSCODE_RESOLVING_ENVIRONMENT -u VSCODE_PID -u CURSOR_AGENT -u TERM_PROGRAM -u VSCODE_IPC_HOOK_CLI"
  else
    envcmd="env $flag"
  fi
  t0=$(date +%s%N)
  timeout 35 sudo -u $u -H $envcmd bash -ilc "echo OK" >/dev/null 2>&1
  t1=$(date +%s%N)
  echo "$name ms=$(( (t1-t0)/1000000 ))"
done
'

echo
echo "CRON"
S cat /etc/cron.d/claude-self-heal
S ls -la /etc/cron.d/claude-self-heal
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'precise.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/pr.sh && bash /tmp/pr.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(180000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -EA SilentlyContinue)+'')
