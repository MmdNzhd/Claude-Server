$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
cat >/tmp/nm-fix.sh <<'INNER'
#!/bin/bash
u=nimaz
act=$(grep ^ACTIVE_MOUNT= /home/$u/.claude-connect.conf|cut -d= -f2|tr -d '\r')
port=$(grep ^TUNNEL_PORT= /home/$u/.claude-connect.conf|cut -d= -f2|tr -d '\r')
echo "act=$act port=$port"
timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" && echo TUN_UP || echo TUN_DOWN
mp=/home/$u/mounts/$act
echo "mp=$mp"
grep " $mp " /proc/mounts || echo not_in_proc
# heal + mount as user
sudo -u $u -H /usr/local/bin/claude-self-heal 2>&1 | tail -15
sudo -u $u -H /usr/local/bin/claude-mount up "$act" 2>&1 | tail -25
if grep -q " $mp " /proc/mounts; then
  if timeout 3 ls "$mp" >/dev/null 2>&1; then echo RESULT=MOUNT_OK; ls "$mp"|head -6; else echo RESULT=ZOMBIE; fi
else echo RESULT=NOT_MOUNTED; fi
pgrep -u $u -af claude-watchdog || true
INNER
printf '%s\n' "$PW" | sudo -S -p '' bash /tmp/nm-fix.sh
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'nm2.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/nm2.sh && bash /tmp/nm2.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(180000)
Write-Host (Get-Content $out -Raw)
if(Test-Path ($out+'.err')){ $e=Get-Content ($out+'.err') -Raw; if($e){Write-Host ERR:; Write-Host $e} }
