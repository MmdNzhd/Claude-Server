$ErrorActionPreference = 'Continue'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
scp -o BatchMode=yes -q 'D:\Smart\Claude-Code-Server\scripts\tmp\edge_cases_audit.py' 'sepidz@192.168.250.70:/tmp/edge_cases_audit.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/edge_cases_audit.py' + $nl + 'ec=$?; echo WRAPPER_EC=$ec; exit $ec' + $nl
[IO.File]::WriteAllText("$env:TEMP\ea.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\ea.sh" 'sepidz@192.168.250.70:/tmp/ea.sh'
$out = "$env:TEMP\ea_out.txt"
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/ea.sh') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
if (-not $p.WaitForExit(180000)) { try{$p.Kill()}catch{}; Write-Host 'TIMEOUT'; exit 1 }
$txt = Get-Content $out -Raw
Write-Host $txt
if (Test-Path "$out.err") { $e=Get-Content "$out.err" -Raw; if($e){Write-Host $e} }
if ($txt -match 'EDGE_GREEN' -and $txt -match 'fail=0') { Write-Host 'ALL_EDGE_GREEN'; exit 0 }
Write-Host 'ALL_EDGE_RED'; exit 1
