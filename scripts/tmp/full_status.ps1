$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
echo "=== TIME_UTC ==="
date -u '+%Y-%m-%dT%H:%M:%SZ'
echo "=== BUNDLE ==="
cat /usr/local/share/claude-client/connect-version.txt 2>/dev/null || echo none
echo "=== AUTOMOUNT_MARKERS ==="
S grep -nE 'VSCODE_RESOLVING|_ppargs|timeout [0-9]+' /usr/local/bin/claude-automount | head -30
echo "=== LISTEN_TUNNELS ==="
S ss -tlnp | grep -E '127.0.0.1:2[12]' || true
echo "=== PER_USER ==="
S bash -c '
for u in alit aminb farzadb hosseinb hosseinm nimaz zahrak sepidz; do
  home=/home/$u
  [ -d "$home" ] || continue
  echo "---- $u ----"
  conf=$home/.claude-connect.conf
  if [ -f "$conf" ]; then
    port=$(grep -E "^TUNNEL_PORT=" "$conf" | tail -1 | cut -d= -f2 | tr -d "\r")
    active=$(grep -E "^ACTIVE_MOUNT=" "$conf" | tail -1 | cut -d= -f2 | tr -d "\r")
    gitm=$(grep -E "^GIT_MODE=" "$conf" | tail -1 | cut -d= -f2 | tr -d "\r")
    lap=$(grep -E "^LAPTOP_USER=" "$conf" | tail -1 | cut -d= -f2 | tr -d "\r")
    os=$(grep -E "^LAPTOP_OS=" "$conf" | tail -1 | cut -d= -f2 | tr -d "\r")
    if [ -n "$port" ] && timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then tun=UP; else tun=DOWN; fi
    echo "laptop=$lap os=$os port=$port tunnel=$tun active=${active:-(empty)} git=$gitm"
  else
    echo "no_connect_conf"
  fi
  # mounts
  if [ -d "$home/mounts" ]; then
    for m in "$home"/mounts/*; do
      [ -e "$m" ] || continue
      name=$(basename "$m")
      if grep -q " $m " /proc/mounts; then
        if timeout 2 ls "$m" >/dev/null 2>&1; then echo "  mount $name = OK"; else echo "  mount $name = ZOMBIE"; fi
      else
        echo "  mount $name = NOT_MOUNTED"
      fi
    done
  else
    echo "  no mounts dir"
  fi
  # cursor last
  last=$(ls -1dt "$home"/.cursor-server/data/logs/*/remoteagent.log 2>/dev/null | head -1)
  if [ -n "$last" ]; then
    echo "  cursor_last=$(stat -c %y "$last" | cut -d. -f1) session=$(basename $(dirname "$last"))"
    # last errors summary
    errs=$(grep -c '\[error\]' "$last" 2>/dev/null || echo 0)
    shellfail=$(grep -c "Unable to resolve your shell environment" "$last" 2>/dev/null || echo 0)
    echo "  cursor_errors_in_last_log=$errs shell_env_fail=$shellfail"
  else
    echo "  cursor_last=none"
  fi
  # bashrc timeout
  if grep -q "timeout 10 .*claude-automount" "$home/.bashrc" 2>/dev/null; then echo "  bashrc_automount=timeout10"; else echo "  bashrc_automount=NO_TIMEOUT_OR_MISSING"; fi
  # connect logs
  if [ -d "$home/.claude/logs" ]; then
    n=$(find "$home/.claude/logs" -type f | wc -l)
    echo "  connect_log_files=$n"
    ls -1 "$home/.claude/logs" 2>/dev/null | tail -5 | sed "s/^/    /"
  else
    echo "  connect_log_files=0 (no dir)"
  fi
done
'
echo "=== FARZAD_SSH_LAST ==="
S journalctl -u ssh --since "3 days ago" 2>/dev/null | grep -i "farzadb" | tail -8 || true
echo "=== HOSSEINB_SSH_TODAY ==="
S journalctl -u ssh --since "today" 2>/dev/null | grep -i "hosseinb" | tail -10 || true
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'full-status.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/fs.sh && bash /tmp/fs.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(180000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -EA SilentlyContinue)+'')
if(Test-Path ($out+'.err')){ $e=Get-Content ($out+'.err') -Raw -EA SilentlyContinue; if($e){Write-Host ERR:; Write-Host $e} }
