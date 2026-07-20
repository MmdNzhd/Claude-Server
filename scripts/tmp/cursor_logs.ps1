$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
echo === FARZADB CURSOR TREE ===
S find /home/farzadb/.cursor-server /home/farzadb/.cursor /home/farzadb/.vscode-server -maxdepth 3 -type d 2>/dev/null | head -80
echo === FARZADB CURSOR LOG FILES ===
S find /home/farzadb -path '*cursor*' \( -name '*.log' -o -name '*log*' \) 2>/dev/null | head -60
S find /home/farzadb/.cursor-server -type f \( -name '*.log' -o -name '*Log*' \) 2>/dev/null | head -40
S find /home/farzadb/.vscode-server -type f \( -name '*.log' -o -name '*Log*' \) 2>/dev/null | head -40
echo === FARZADB RECENT LOG MTIMES ===
S find /home/farzadb/.cursor-server /home/farzadb/.vscode-server /home/farzadb/.cursor -type f \( -name '*.log' -o -name '*log' \) -printf '%T@ %TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort -nr | head -40
echo === HOSSEINB CURSOR LOGS ===
S find /home/hosseinb/.cursor-server /home/hosseinb/.vscode-server -type f -name '*.log' -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort -r | head -20
echo === ALL USERS CURSOR LOG DIRS ===
S bash -c 'for u in /home/*; do n=$(basename "$u"); for d in .cursor-server .vscode-server .cursor; do if [ -d "$u/$d" ]; then echo "$n/$d $(stat -c %y "$u/$d" | cut -d. -f1)"; fi; done; done'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'cursor-logs.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/cl.sh && bash /tmp/cl.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(120000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -ErrorAction SilentlyContinue)+'')
if(Test-Path ($out+'.err')){ $e=Get-Content ($out+'.err') -Raw -EA SilentlyContinue; if($e){Write-Host ERR:; Write-Host $e} }
