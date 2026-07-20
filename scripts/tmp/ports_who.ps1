$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
cat >/tmp/who.sh <<'INNER'
#!/bin/bash
echo "=== conf ports ==="
for u in alit aminb farzadb hosseinb hosseinm nimaz zahrak sepidz; do
  c=/home/$u/.claude-connect.conf
  [ -f "$c" ] || continue
  echo -n "$u: "; grep -E 'TUNNEL_PORT|LAPTOP_USER|ACTIVE_MOUNT' "$c" | tr '\n' ' '; echo
done
echo "=== listeners ==="
ss -tlnp | grep 127.0.0.1:2
echo "=== pid owners ==="
for port in 21004 21005 21006 21009 21010 22000; do
  line=$(ss -tlnp | grep ":$port " || true)
  pid=$(echo "$line" | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -1)
  if [ -n "$pid" ]; then
    echo "port=$port pid=$pid user=$(ps -p $pid -o user=) cmd=$(ps -p $pid -o args= | head -c 100)"
  else
    echo "port=$port CLOSED"
  fi
done
echo "=== nimaz mount probe both ports ==="
# what does claude-mount check for 'another laptop'?
grep -n "another laptop\|stale TUNNEL\|LAPTOP_USER" /usr/local/lib/claude-mount | head -20
INNER
printf '%s\n' "$PW" | sudo -S -p '' bash /tmp/who.sh
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'who.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/w.sh && bash /tmp/w.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(60000)
Get-Content $out -Raw
