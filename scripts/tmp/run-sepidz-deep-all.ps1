$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
& scp -o BatchMode=yes -o ConnectTimeout=20 -q 'D:\Smart\Claude-Code-Server\scripts\tmp\sepidz_deep_all_fix.py' 'sepidz@192.168.250.70:/tmp/sepidz_deep_all_fix.py'
$nl = [char]10
$wrap = '#!/bin/bash' + $nl + 'set -e' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/sepidz_deep_all_fix.py' + $nl + 'ec=$?' + $nl + 'echo DEEP_EXIT=$ec' + $nl + 'exit $ec' + $nl
[IO.File]::WriteAllText((Join-Path $env:TEMP 'sepidz_deep_wrap.sh'), $wrap)
& scp -o BatchMode=yes -q (Join-Path $env:TEMP 'sepidz_deep_wrap.sh') 'sepidz@192.168.250.70:/tmp/sepidz_deep_wrap.sh'
& ssh -o BatchMode=yes -o ConnectTimeout=300 sepidz@192.168.250.70 'bash /tmp/sepidz_deep_wrap.sh'
exit $LASTEXITCODE
