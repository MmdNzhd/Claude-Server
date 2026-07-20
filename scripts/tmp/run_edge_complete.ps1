$ErrorActionPreference = 'Continue'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -q 'D:\Smart\Claude-Code-Server\scripts\tmp\edge_complete.py' 'sepidz@192.168.250.70:/tmp/edge_complete.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/edge_complete.py' + $nl + 'ec=$?; echo WRAPPER_EC=$ec; exit $ec' + $nl
[IO.File]::WriteAllText("$env:TEMP\ec.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\ec.sh" 'sepidz@192.168.250.70:/tmp/ec.sh'
$out = "$env:TEMP\ec_out.txt"
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/ec.sh') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
if (-not $p.WaitForExit(240000)) { try{$p.Kill()}catch{}; Write-Host 'TIMEOUT'; exit 1 }
$txt = Get-Content $out -Raw
Write-Host $txt
if ($txt -match 'EDGE_COMPLETE_GREEN') { exit 0 }
exit 1
