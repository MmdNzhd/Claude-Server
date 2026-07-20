$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -q 'D:\Smart\Claude-Code-Server\scripts\tmp\farzad_git_diag.py' 'sepidz@192.168.250.70:/tmp/farzad_git_diag.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/farzad_git_diag.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\fzd.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\fzd.sh" 'sepidz@192.168.250.70:/tmp/fzd.sh'
ssh -o BatchMode=yes -o ConnectTimeout=60 sepidz@192.168.250.70 'bash /tmp/fzd.sh'
