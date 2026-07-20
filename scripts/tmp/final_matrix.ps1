$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
printf '%s\n' "$PW" | sudo -S -p '' bash -c '
echo LIVE=$(cat /usr/local/share/claude-client/connect-version.txt)
echo -n RESOLVE_IN_BUNDLE=
grep -c Resolve-UpdateEndpoint /usr/local/share/claude-client/connect-update.ps1
echo -n KEYS=
wc -l </home/sepidz/.ssh/authorized_keys
printf "%-10s %-8s %-12s %-10s %s\n" USER PORT TUNNEL MOUNT ACTIVE
for u in alit aminb farzadb hosseinb hosseinm nimaz zahrak; do
  conf=/home/$u/.claude-connect.conf
  [ -f "$conf" ] || continue
  port=$(grep ^TUNNEL_PORT= "$conf" | cut -d= -f2 | tr -d "\r")
  am=$(grep ^ACTIVE_MOUNT= "$conf" | cut -d= -f2 | tr -d "\r")
  if [ -n "$port" ] && ss -lntp | grep -qE ":${port}\\b"; then t=UP; else t=DOWN; fi
  mp=/home/$u/mounts/$am
  if [ -n "$am" ] && mountpoint -q "$mp" 2>/dev/null; then m=MOUNTED
  elif [ -n "$am" ] && [ -d "$mp" ]; then m=DIR
  else m=-; fi
  printf "%-10s %-8s %-12s %-10s %s\n" "$u" "$port" "$t" "$m" "$am"
done
'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'fm.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','sepidz@192.168.250.70',("echo $b64 | base64 -d | bash")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(60000)
Get-Content $out -Raw
