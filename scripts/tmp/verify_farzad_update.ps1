$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
printf '%s\n' "$PW" | sudo -S -p '' bash -c '
echo "LIVE_VER=$(cat /usr/local/share/claude-client/connect-version.txt)"
echo -n "UPDATE_USES_REMOTE_USER="
grep -c Get-RemoteUserFromConf /usr/local/share/claude-client/connect-update.ps1 || true
echo -n "FARZAD_KEY_IN_SEPIDZ="
fk=$(awk "{print \$2}" /home/farzadb/.ssh/authorized_keys | head -1)
grep -q "$fk" /home/sepidz/.ssh/authorized_keys && echo YES || echo NO
ss -lntp | grep -E ":21006\b" >/dev/null && echo TUNNEL_21006=UP || echo TUNNEL_21006=DOWN
'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'vf.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d | bash")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(60000)
Get-Content $out -Raw
