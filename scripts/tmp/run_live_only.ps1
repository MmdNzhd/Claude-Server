$ErrorActionPreference = 'Continue'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10
# versions via Start-Process
function Ver([string]$target) {
  $out = "$env:TEMP\ver_$($target.GetHashCode()).txt"
  $p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=4','-o','ConnectionAttempts=1',$target,'cat /usr/local/share/claude-client/connect-version.txt') -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError "$out.err"
  if (-not $p.WaitForExit(8000)) { try{$p.Kill()}catch{}; return 'TIMEOUT' }
  if (Test-Path $out) { return (Get-Content $out -Raw).Trim() }
  return 'EMPTY'
}
Write-Host "SMART=$(Ver 'smart@192.168.210.240')"
Write-Host "SEPIDZ=$(Ver 'sepidz@192.168.250.70')"
Write-Host "REPO=$((Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt' -Raw).Trim())"

scp -o BatchMode=yes -o ConnectTimeout=8 -q 'D:\Smart\Claude-Code-Server\scripts\tmp\deep_final.py' 'sepidz@192.168.250.70:/tmp/deep_final.py'
$wrap = '#!/bin/bash' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl + 'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/deep_final.py' + $nl
[IO.File]::WriteAllText("$env:TEMP\live4.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\live4.sh" 'sepidz@192.168.250.70:/tmp/live4.sh'
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','sepidz@192.168.250.70','bash /tmp/live4.sh') -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\live4_out.txt" -RedirectStandardError "$env:TEMP\live4_err.txt"
if (-not $p.WaitForExit(240000)) { try{$p.Kill()}catch{}; Write-Host 'TIMEOUT'; exit 1 }
Get-Content "$env:TEMP\live4_out.txt" | Write-Host
Get-Content "$env:TEMP\live4_err.txt" -ErrorAction SilentlyContinue | Write-Host
exit $p.ExitCode
