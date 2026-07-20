$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
S bash -c '
u=nimaz
mp=/home/nimaz/mounts/sepidzwebapp
echo before:
grep " $mp " /proc/mounts || echo not_in_proc
pkill -u $u -f "sshfs .*sepidzwebapp" 2>/dev/null || true
timeout 5 fusermount -uz "$mp" 2>/dev/null || timeout 5 umount -l "$mp" 2>/dev/null || true
sleep 1
sudo -u $u -H /usr/local/bin/claude-self-heal 2>&1 | tail -20
sudo -u $u -H /usr/local/bin/claude-mount up sepidzwebapp 2>&1 | tail -20
echo after:
if grep -q " $mp " /proc/mounts; then
  if timeout 3 ls "$mp" >/dev/null 2>&1; then echo MOUNT_OK; ls "$mp" | head -8; else echo STILL_ZOMBIE; fi
else echo NOT_MOUNTED; fi
# also ensure hosseinb still ok
timeout 3 ls /home/hosseinb/mounts/backend >/dev/null && echo hosseinb_ok
# farzadb clean
grep farzadb /proc/mounts || echo farzadb_clean
# cron exists
ls -la /etc/cron.d/claude-self-heal
grep -c _heal_active_remount /usr/local/bin/claude-self-heal
'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'fix-nimaz.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/fn.sh && bash /tmp/fn.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(120000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -EA SilentlyContinue)+'')
