$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
& scp -o BatchMode=yes -o ControlMaster=no 'D:\Smart\Claude-Code-Server\scripts\server\claude-connect-logs-cleanup.sh' 'sepidz@192.168.250.70:/tmp/claude-connect-logs-cleanup.sh'
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
printf '%s\n' "$PW" | sudo -S -p '' bash -c '
install -m 755 /tmp/claude-connect-logs-cleanup.sh /usr/local/bin/claude-connect-logs-cleanup
grep mtime /usr/local/bin/claude-connect-logs-cleanup
# also fix live sync strings in any already-deployed? client comes via publish
echo OK
'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'dc.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','sepidz@192.168.250.70',("echo $b64 | base64 -d | bash")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(60000)
Get-Content $out -Raw
