$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
echo === AUTOMOUNT HEAD ===
S sed -n '1,50p' /usr/local/bin/claude-automount
echo === FARZAD BASHRC AUTOMOUNT ===
S grep -n -A6 'Claude Code auto-mount' /home/farzadb/.bashrc
echo === HOSSEINB BACKEND LS ===
S timeout 5 ls /home/hosseinb/mounts/backend | head -15
echo === NO ZOMBIES ===
S bash -c 'for u in farzadb hosseinb hosseinm nimaz; do for m in /home/$u/mounts/*; do [ -e "$m" ] || continue; if grep -q " $m " /proc/mounts; then timeout 2 ls "$m" >/dev/null 2>&1 && echo OK $m || echo ZOMBIE $m; fi; done; done'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'verify-heal.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/vh.sh && bash /tmp/vh.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(60000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -EA SilentlyContinue)+'')
