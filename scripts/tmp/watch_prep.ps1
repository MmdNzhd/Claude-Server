$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
printf '%s\n' "$PW" | sudo -S -p '' bash -c '
echo BUNDLE=$(cat /usr/local/share/claude-client/connect-version.txt)
echo DAY=$(date +%Y%m%d)
for u in farzadb hosseinb hosseinm nimaz alit aminb zahrak; do
  conf=/home/$u/.claude-connect.conf
  [ -f "$conf" ] || continue
  port=$(grep ^TUNNEL_PORT= "$conf" | cut -d= -f2 | tr -d "\r")
  am=$(grep ^ACTIVE_MOUNT= "$conf" | cut -d= -f2 | tr -d "\r")
  if [ -n "$port" ] && ss -lntp 2>/dev/null | grep -qE ":${port}\\b"; then t=UP; else t=DOWN; fi
  lg=/home/$u/.claude/logs/connect-$(date +%Y%m%d).log
  if [ -f "$lg" ]; then sz=$(wc -c <"$lg"); mt=$(stat -c %y "$lg" | cut -d. -f1); else sz=0; mt=-; fi
  echo "$u|tun=$t|port=$port|act=$am|logbytes=$sz|logmtime=$mt"
done
'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'wp.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','sepidz@192.168.250.70',("echo $b64 | base64 -d | bash")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(60000)
Get-Content $out -Raw
