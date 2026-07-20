$ErrorActionPreference='Stop'
$repo = 'D:\Smart\Claude-Code-Server'
scp -o BatchMode=yes -o ConnectTimeout=20 "$repo\scripts\client\editor-launch.ps1" 'smart@192.168.210.240:/tmp/editor-launch.ps1'
if ($LASTEXITCODE -ne 0) { throw 'scp editor-launch failed' }
scp -o BatchMode=yes -o ConnectTimeout=20 "$repo\scripts\client\windows\connect.ps1" 'smart@192.168.210.240:/tmp/connect.ps1'
scp -o BatchMode=yes -o ConnectTimeout=20 "$repo\scripts\client\windows\connect-version.txt" 'smart@192.168.210.240:/tmp/connect-version.txt'
$cmd = @'
set -e
# flat layout used by auto-update
sudo cp /tmp/editor-launch.ps1 /usr/local/share/claude-client/editor-launch.ps1
sudo cp /tmp/connect.ps1 /usr/local/share/claude-client/connect.ps1
sudo cp /tmp/connect-version.txt /usr/local/share/claude-client/connect-version.txt
# optional nested windows/ if present
if [ -d /usr/local/share/claude-client/windows ]; then
  sudo cp /tmp/editor-launch.ps1 /usr/local/share/claude-client/windows/editor-launch.ps1
  sudo cp /tmp/connect.ps1 /usr/local/share/claude-client/windows/connect.ps1
  sudo cp /tmp/connect-version.txt /usr/local/share/claude-client/windows/connect-version.txt
fi
echo VER=$(tr -d '\r\n' </usr/local/share/claude-client/connect-version.txt)
grep -c preserve_open_windows /usr/local/share/claude-client/editor-launch.ps1
'@
# write remote runner without sudo password issues - smart may have passwordless for some cmds
ssh -o BatchMode=yes -o ConnectTimeout=30 smart@192.168.210.240 $cmd
