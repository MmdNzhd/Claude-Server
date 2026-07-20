$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
cat >/tmp/sepidz-matrix-inner.sh <<'INNER'
#!/bin/bash
for u in alit aminb farzadb hosseinb hosseinm nimaz zahrak; do
  conf=/home/$u/.claude-connect.conf
  [ -f "$conf" ] || continue
  port=$(grep ^TUNNEL_PORT= "$conf"|cut -d= -f2|tr -d '\r')
  active=$(grep ^ACTIVE_MOUNT= "$conf"|cut -d= -f2|tr -d '\r')
  if [ -n "$port" ] && timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then t=UP; else t=DOWN; fi
  wd=$(pgrep -u "$u" -f claude-watchdog >/dev/null 2>&1 && echo y || echo n)
  ms=""
  for m in /home/$u/mounts/*; do
    [ -e "$m" ] || continue
    n=$(basename "$m")
    if grep -q " $m " /proc/mounts 2>/dev/null; then
      if timeout 2 ls "$m" >/dev/null 2>&1; then ms="${ms}${n}=OK "; else ms="${ms}${n}=ZOMBIE "; fi
    fi
  done
  ra=$(ls -1dt /home/$u/.cursor-server/data/logs/*/remoteagent.log 2>/dev/null|head -1)
  cl=-; sf=0
  if [ -n "$ra" ]; then
    cl=$(stat -c %y "$ra"|cut -d. -f1)
    sf=$(grep -c "Unable to resolve your shell environment" "$ra" 2>/dev/null || true); sf=${sf:-0}
  fi
  buf=$(find /home/$u/.claude/logs -name '.connect-buf-*.tmp' 2>/dev/null|wc -l)
  echo "$u|tun=$t|port=$port|act=${active:-E}|wd=$wd|mounts=${ms:--}|cursor=$cl|shellfail=$sf|buf=$buf"
done
echo -n "PORTS:"
ss -tln 2>/dev/null | awk '/127\.0\.0\.1:2/{split($4,a,":"); printf "%s ", a[2]}'
echo
INNER
chmod +x /tmp/sepidz-matrix-inner.sh
printf '%s\n' "$PW" | sudo -S -p '' bash /tmp/sepidz-matrix-inner.sh
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'matrix.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/mx.sh && bash /tmp/mx.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(120000)){ try{$p.Kill()}catch{} }
Get-Content $out -Raw -EA SilentlyContinue
