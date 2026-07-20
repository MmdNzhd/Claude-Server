$ErrorActionPreference='Continue'
function Check-Server([string]$Label,[string]$Target) {
  Write-Host "==== $Label ($Target) ===="
  $cmd = @'
set +e
echo VER=$(tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null || echo MISSING)
echo MANIFEST_LINES=$(wc -l < /usr/local/share/claude-client/manifest.txt 2>/dev/null || echo 0)
echo HAS_UPDATE=$(test -f /usr/local/share/claude-client/connect-update.ps1 && echo yes || echo no)
echo HAS_MAC_CONNECT=$(test -f /usr/local/share/claude-client/mac/connect.sh && echo yes || echo no)
echo HAS_INSTALLER=$(test -x /usr/local/lib/claude-server/commands/install-client-bundle.sh && echo yes || echo no)
echo SUDOERS=$(test -f /etc/sudoers.d/claude-client-deploy && echo yes || echo no)
if [ -f /etc/sudoers.d/claude-client-deploy ]; then
  echo '--- sudoers ---'
  cat /etc/sudoers.d/claude-client-deploy
fi
echo SUDO_N_INSTALL=$(sudo -n /usr/bin/bash -c 'echo ok' 2>/dev/null || echo fail_general)
# test the exact alias path if possible
if sudo -n true 2>/dev/null; then echo SUDO_N_TRUE=yes; else echo SUDO_N_TRUE=no; fi
echo '--- manifest head ---'
head -20 /usr/local/share/claude-client/manifest.txt 2>/dev/null
echo '--- missing required ---'
for f in connect.bat connect.ps1 connect-update.ps1 connect-version.txt connect-ui.ps1 git-mode.ps1 editor-launch.ps1 cursor-auth-laptop.ps1 mac/connect.sh mac/connect-update.sh mac/git-mode.sh server/claude-mount.sh server/laptop-exec.sh; do
  if [ ! -f "/usr/local/share/claude-client/$f" ]; then echo MISSING:$f; fi
done
echo DONE
'@
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($cmd))
  & ssh -o BatchMode=yes -o ConnectTimeout=15 $Target "echo $b64 | base64 -d | bash"
}
Check-Server 'Smart' 'smart@192.168.210.240'
Check-Server 'Sepidz' 'sepidz@192.168.250.70'
Write-Host '==== local repo version ===='
Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt'
