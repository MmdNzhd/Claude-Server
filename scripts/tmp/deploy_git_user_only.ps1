$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -q 'D:\Smart\Claude-Code-Server\scripts\server\claude-mount.sh' 'sepidz@192.168.250.70:/tmp/claude-mount.new'
scp -o BatchMode=yes -q 'D:\Smart\Claude-Code-Server\scripts\tmp\cleanup_ws_git.py' 'sepidz@192.168.250.70:/tmp/cleanup_ws_git.py'
$wrap = '#!/bin/bash' + $nl + 'set -e' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' cp /tmp/claude-mount.new /usr/local/lib/claude-mount' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' chmod 755 /usr/local/lib/claude-mount' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' sed -i ''s/\r$//'' /usr/local/lib/claude-mount' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' grep -q ''Only remote User settings'' /usr/local/lib/claude-mount' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/cleanup_ws_git.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\dguo.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\dguo.sh" 'sepidz@192.168.250.70:/tmp/dguo.sh'
ssh -o BatchMode=yes -o ConnectTimeout=90 sepidz@192.168.250.70 'bash /tmp/dguo.sh'
