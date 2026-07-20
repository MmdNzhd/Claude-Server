$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
echo === claude-automount script ===
S head -n 80 /usr/local/bin/claude-automount
echo
echo === time automount as farzadb ===
S timeout 20 sudo -u farzadb -H bash -lc 'echo start; /usr/local/bin/claude-automount; echo done' 2>&1 || echo EXIT:$?
echo
echo === time bash login as farzadb ===
S timeout 20 sudo -u farzadb -H bash -lc 'echo OK' 2>&1 || echo EXIT:$?
echo
echo === time bash login as hosseinb ===
S timeout 20 sudo -u hosseinb -H bash -lc 'echo OK' 2>&1 || echo EXIT:$?
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'auto-hang.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/ah.sh && bash /tmp/ah.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(90000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -ErrorAction SilentlyContinue)+'')
if(Test-Path ($out+'.err')){ $e=Get-Content ($out+'.err') -Raw -EA SilentlyContinue; if($e){Write-Host ERR:; Write-Host $e} }
