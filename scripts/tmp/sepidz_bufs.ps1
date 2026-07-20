$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
echo === STUCK BUFFERS ===
S find /home -type f -name '.connect-buf-*.tmp' -printf '%p %s %TY-%Tm-%Td %TH:%TM\n' 2>/dev/null
echo
echo === HOSSEINB BUF ERRORS ===
for f in /home/hosseinb/.claude/logs/.connect-buf-*.tmp; do
  [ -f "$f" ] || continue
  echo "#### $f ####"
  S grep -E 'ERROR|WARN|FAIL|failed|UNHANDLED|timeout|denied|auth|mount|SSH_|Update|version|session end|session begin' "$f" 2>/dev/null | tail -n 80
  echo ---- tail 50 ----
  S tail -n 50 "$f"
  echo
done
echo === MOUNT HEALTH ===
S bash -c '
for u in alit aminb designer farzadb hosseinb hosseinm nimaz zahrak; do
  echo -- $u --
  for m in /home/$u/mounts/*; do
    [ -e "$m" ] || continue
    name=$(basename "$m")
    if mountpoint -q "$m" 2>/dev/null || grep -q " $m " /proc/mounts; then
      echo "MOUNTED $name"
    else
      echo "NOT_MOUNTED $name"
    fi
  done
done
'
echo === CLIENT BUNDLE VER ===
cat /usr/local/share/claude-client/connect-version.txt
echo
echo === WHO COMPLAINED STYLE: recent ssh sessions ===
S last -n 30 | head -40
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'sep-bufs.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/rb.sh && bash /tmp/rb.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(180000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -ErrorAction SilentlyContinue)+'')
