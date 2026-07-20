$ErrorActionPreference = 'Stop'
$repo = 'D:\Smart\Claude-Code-Server'
$server = 'smart@192.168.210.240'

# upload fixed files
scp -o BatchMode=yes -o ConnectTimeout=20 "$repo\scripts\client\editor-launch.ps1" "${server}:/tmp/editor-launch.ps1"
scp -o BatchMode=yes -o ConnectTimeout=20 "$repo\scripts\client\windows\connect.ps1" "${server}:/tmp/connect.ps1"
scp -o BatchMode=yes -o ConnectTimeout=20 "$repo\scripts\client\windows\connect-version.txt" "${server}:/tmp/connect-version.txt"
scp -o BatchMode=yes -o ConnectTimeout=20 "$repo\scripts\client\windows\connect-version.txt" "${server}:/tmp/connect-version.txt"

$remoteScript = @'
#!/bin/bash
set -euo pipefail
DEST=/usr/local/share/claude-client
cp /tmp/editor-launch.ps1 "$DEST/editor-launch.ps1"
cp /tmp/connect.ps1 "$DEST/connect.ps1"
cp /tmp/connect-version.txt "$DEST/connect-version.txt"
chmod 644 "$DEST/editor-launch.ps1" "$DEST/connect.ps1" "$DEST/connect-version.txt"
if [ -d "$DEST/windows" ]; then
  cp /tmp/editor-launch.ps1 "$DEST/windows/editor-launch.ps1"
  cp /tmp/connect.ps1 "$DEST/windows/connect.ps1"
  cp /tmp/connect-version.txt "$DEST/windows/connect-version.txt"
fi
grep -q preserve_open_windows "$DEST/editor-launch.ps1"
grep -q 20260715.18 "$DEST/connect-version.txt"
if grep -q pre_launch_agent_or_new_window "$DEST/editor-launch.ps1"; then
  echo STILL_HAS_FORCE
  exit 1
fi
echo SMART_BUNDLE_OK
echo VER=$(tr -d '\r\n' < "$DEST/connect-version.txt")
'@ -replace "`r`n","`n"
$localRunner = Join-Path $env:TEMP 'smart-bundle-kill-fix.sh'
[System.IO.File]::WriteAllText($localRunner, $remoteScript)
scp -o BatchMode=yes -o ConnectTimeout=20 $localRunner "${server}:/tmp/smart-bundle-kill-fix.sh"

# Try passwordless first
$prev = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
ssh -o BatchMode=yes -o ConnectTimeout=20 $server "chmod +x /tmp/smart-bundle-kill-fix.sh && sudo -n bash /tmp/smart-bundle-kill-fix.sh"
$rc = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($rc -eq 0) {
  Write-Host 'Smart bundle updated (passwordless sudo)' -ForegroundColor Green
  exit 0
}

Write-Host 'Opening terminal for Smart sudo password...' -ForegroundColor Yellow
Start-Process cmd.exe -ArgumentList @('/c', "title Claude Smart bundle fix && ssh -t -o ConnectTimeout=30 $server `"chmod +x /tmp/smart-bundle-kill-fix.sh && sudo bash /tmp/smart-bundle-kill-fix.sh && echo DONE && sleep 2`"")

$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 4
  $ver = (ssh -o BatchMode=yes -o ConnectTimeout=10 $server "tr -d '\r\n' </usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
  $pres = (ssh -o BatchMode=yes -o ConnectTimeout=10 $server "grep -c preserve_open_windows /usr/local/share/claude-client/editor-launch.ps1 2>/dev/null").Trim()
  Write-Host "  poll ver=$ver preserve=$pres"
  if ($ver -eq '20260715.18' -and $pres -match '^[1-9]') {
    Write-Host 'Smart bundle updated OK' -ForegroundColor Green
    exit 0
  }
}
Write-Host 'Timed out waiting for Smart sudo - enter password in the opened window then re-check' -ForegroundColor Red
exit 1
