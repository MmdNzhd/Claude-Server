$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
echo === bash -ilc farzadb timed ===
S timeout 25 sudo -u farzadb -H env -u VSCODE_IPC_HOOK_CLI -u CURSOR_AGENT -u TERM_PROGRAM bash -ilc 'echo OK; date' 2>&1 || echo EXIT:$?
echo === bash -ilc hosseinb timed ===
S timeout 25 sudo -u hosseinb -H env -u VSCODE_IPC_HOOK_CLI -u CURSOR_AGENT -u TERM_PROGRAM bash -ilc 'echo OK; date' 2>&1 || echo EXIT:$?
echo === which auth sync might hang ===
S timeout 10 sudo -u farzadb -H /usr/local/bin/claude-auth-sync 2>&1; echo auth:$?
S timeout 10 sudo -u farzadb -H /usr/local/bin/cursor-auth-sync 2>&1; echo cursorauth:$?
S timeout 15 sudo -u farzadb -H /usr/local/bin/claude-self-heal --quiet 2>&1; echo heal:$?
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'bash-il.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/bi.sh && bash /tmp/bi.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(120000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -ErrorAction SilentlyContinue)+'')
if(Test-Path ($out+'.err')){ $e=Get-Content ($out+'.err') -Raw -EA SilentlyContinue; if($e){Write-Host ERR:; Write-Host $e} }
