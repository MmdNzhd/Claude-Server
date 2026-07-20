$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
& scp -o BatchMode=yes -o ConnectTimeout=15 -q 'D:\Smart\Claude-Code-Server\scripts\tmp\farzad_fix_crlf_golden.py' 'sepidz@192.168.250.70:/tmp/farzad_fix_crlf_golden.py'
$nl = [char]10
$wrap = '#!/bin/bash' + $nl + 'set -e' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/farzad_fix_crlf_golden.py' + $nl
[System.IO.File]::WriteAllText((Join-Path $env:TEMP 'farzad_crlf_wrap.sh'), $wrap)
& scp -o BatchMode=yes -o ConnectTimeout=15 -q (Join-Path $env:TEMP 'farzad_crlf_wrap.sh') 'sepidz@192.168.250.70:/tmp/farzad_crlf_wrap.sh'
& ssh -o BatchMode=yes -o ConnectTimeout=180 sepidz@192.168.250.70 'bash /tmp/farzad_crlf_wrap.sh'
