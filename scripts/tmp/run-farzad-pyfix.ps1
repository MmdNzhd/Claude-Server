$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))

& scp -o BatchMode=yes -o ConnectTimeout=15 -q 'D:\Smart\Claude-Code-Server\scripts\tmp\farzad_fix.py' 'sepidz@192.168.250.70:/tmp/farzad_fix.py'
if ($LASTEXITCODE -ne 0) { throw 'scp py failed' }

$nl = [char]10
$wrap = '#!/bin/bash' + $nl + 'set -e' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/farzad_fix.py' + $nl
$wrapPath = Join-Path $env:TEMP 'farzad_wrap.sh'
[System.IO.File]::WriteAllText($wrapPath, $wrap)
Write-Host 'wrap bytes:' ([System.IO.File]::ReadAllBytes($wrapPath).Length)

& scp -o BatchMode=yes -o ConnectTimeout=15 -q $wrapPath 'sepidz@192.168.250.70:/tmp/farzad_wrap.sh'
if ($LASTEXITCODE -ne 0) { throw 'scp wrap failed' }

& ssh -o BatchMode=yes -o ConnectTimeout=120 sepidz@192.168.250.70 'bash /tmp/farzad_wrap.sh'
Write-Host "exit=$LASTEXITCODE"
