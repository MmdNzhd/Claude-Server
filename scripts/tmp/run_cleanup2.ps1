$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -q 'D:\Smart\Claude-Code-Server\scripts\tmp\cleanup_ws_git2.py' 'sepidz@192.168.250.70:/tmp/cleanup_ws_git2.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/cleanup_ws_git2.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\c2.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\c2.sh" 'sepidz@192.168.250.70:/tmp/c2.sh'
ssh -o BatchMode=yes -o ConnectTimeout=60 sepidz@192.168.250.70 'bash /tmp/c2.sh'
