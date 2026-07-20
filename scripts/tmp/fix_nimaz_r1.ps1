$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
printf '%s\n' "$PW" | sudo -S -p '' bash <<'INNER'
set -x
u=nimaz
act=sepidzwebapp
mp=/home/$u/mounts/$act
echo BEFORE:
grep " $mp " /proc/mounts || echo not_mounted
timeout 1 bash -c 'exec 3<>/dev/tcp/127.0.0.1/21009' && echo tunnel_21009_UP || echo tunnel_DOWN
# conf may say 21009
cat /home/$u/.claude-connect.conf
sudo -u $u -H /usr/local/bin/claude-self-heal 2>&1 | tail -20
sudo -u $u -H /usr/local/bin/claude-mount up $act 2>&1 | tail -20
echo AFTER:
if grep -q " $mp " /proc/mounts; then
  if timeout 3 ls "$mp" >/dev/null 2>&1; then echo MOUNT_OK; ls "$mp"|head -5; else echo ZOMBIE; fi
else echo STILL_NOT; fi
pgrep -u $u -af claude-watchdog || (sudo -u $u -H bash -c 'nohup /usr/local/bin/claude-watchdog >/dev/null 2>&1 &' ; echo wd_started)
INNER
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'fn.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/fn.sh && bash /tmp/fn.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(180000)
Get-Content $out -Raw
if(Test-Path ($out+'.err')){ Get-Content ($out+'.err') -Raw }
