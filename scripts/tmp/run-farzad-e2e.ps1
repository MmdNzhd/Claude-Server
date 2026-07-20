$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))

& scp -o BatchMode=yes -o ConnectTimeout=15 -q 'D:\Smart\Claude-Code-Server\scripts\tmp\farzad_e2e_test.py' 'sepidz@192.168.250.70:/tmp/farzad_e2e_test.py'
if ($LASTEXITCODE -ne 0) { throw 'scp failed' }

$nl = [char]10
$wrap = '#!/bin/bash' + $nl + 'set -e' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/farzad_e2e_test.py' + $nl + 'ec=$?' + $nl + 'echo E2E_EXIT=$ec' + $nl + 'exit $ec' + $nl
$wrapPath = Join-Path $env:TEMP 'farzad_e2e_wrap.sh'
[System.IO.File]::WriteAllText($wrapPath, $wrap)
& scp -o BatchMode=yes -o ConnectTimeout=15 -q $wrapPath 'sepidz@192.168.250.70:/tmp/farzad_e2e_wrap.sh'
& ssh -o BatchMode=yes -o ConnectTimeout=120 sepidz@192.168.250.70 'bash /tmp/farzad_e2e_wrap.sh'
Write-Host "ssh_exit=$LASTEXITCODE"
exit $LASTEXITCODE
