$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
printf '%s\n' "$PW" | sudo -S -p '' bash -c '
echo "=== find command scripts ==="
find /usr/local/lib/claude-server -type f -name "*.sh" 2>/dev/null | sort
echo "=== claude-server binary ==="
readlink -f /usr/local/bin/claude-server; head -40 /usr/local/bin/claude-server
'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'fc.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','sepidz@192.168.250.70',("echo $b64 | base64 -d | bash")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(60000)
Get-Content $out -Raw
