$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','smart@192.168.250.70','bash -s') -NoNewWindow -Wait -PassThru -RedirectStandardInput (Join-Path $env:TEMP 'sepid-sim.sh') -RedirectStandardOutput "$env:TEMP\sim.out"
@'
set -e
cd ~/claude-client-bundle-deploy
rm -rf /tmp/bverify && mkdir /tmp/bverify
python3 - bundle.zip /tmp/bverify <<PY
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
grep -o "192.168.[0-9.]*" /tmp/bverify/connect.ps1 | head -1
tr -d "\r\n" < /tmp/bverify/connect-version.txt
test -f /tmp/bverify/mac/claude-mount.sh && bash -n /tmp/bverify/mac/claude-mount.sh && echo mount=OK
'@ | Set-Content (Join-Path $env:TEMP 'sepid-sim.sh') -Encoding ASCII
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','smart@192.168.250.70','bash -s') -NoNewWindow -Wait -PassThru -RedirectStandardInput (Join-Path $env:TEMP 'sepid-sim.sh') -RedirectStandardOutput "$env:TEMP\sim.out"
Get-Content "$env:TEMP\sim.out"
Write-Host "exit=$($p.ExitCode)"
