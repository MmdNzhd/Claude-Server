$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
echo === FARZAD remoteagent LAST 80 ===
S tail -n 80 /home/farzadb/.cursor-server/data/logs/20260718T115406/remoteagent.log
echo
echo === FARZAD remoteagent ERRORS ===
S grep -nEi 'error|fail|timeout|EIO|ENOENT|unavailable|disconnect|refused|stale|mount|Transport' /home/farzadb/.cursor-server/data/logs/20260718T115406/remoteagent.log | tail -40
echo
echo === FARZAD vscode agent-host LAST 60 ===
S tail -n 60 /home/farzadb/.vscode-server/cli/agent-host-stable.log
echo
echo === HOSSEINB remoteagent LAST 100 ===
S tail -n 100 /home/hosseinb/.cursor-server/data/logs/20260719T071051/remoteagent.log
echo
echo === HOSSEINB remoteagent ERRORS ===
S grep -nEi 'error|fail|timeout|EIO|ENOENT|unavailable|disconnect|refused|stale|mount|Transport|CodeExpectedError' /home/hosseinb/.cursor-server/data/logs/20260719T071051/remoteagent.log | tail -50
echo
echo === HOSSEINB remoteexthost ERRORS ===
S grep -nEi 'error|fail|EIO|ENOENT|mount|Transport|unavailable' /home/hosseinb/.cursor-server/data/logs/20260719T071051/exthost1/remoteexthost.log | tail -40
echo
echo === HOSSEINB ptyhost ===
S tail -n 40 /home/hosseinb/.cursor-server/data/logs/20260719T071051/ptyhost.log
echo
echo === FARZAD exthost ERRORS last session ===
S grep -nEi 'error|fail|EIO|ENOENT|mount|Transport|unavailable|Input.output' /home/farzadb/.cursor-server/data/logs/20260718T115406/exthost1/remoteexthost.log | tail -40
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'cursor-read.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/cr.sh && bash /tmp/cr.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(120000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -ErrorAction SilentlyContinue)+'')
if(Test-Path ($out+'.err')){ $e=Get-Content ($out+'.err') -Raw -EA SilentlyContinue; if($e){Write-Host ERR:; Write-Host $e} }
