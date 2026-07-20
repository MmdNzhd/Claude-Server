$ErrorActionPreference = "Stop"
. "D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1"
$pw = Get-SepidzSudoPassword
$script = @"
export SUDO_PW='$pw'
set -e
echo HOST=`$(hostname)
echo IP=`$(hostname -I | awk '{print `$1}')
echo VER=`$(tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt)
echo '=== farzadb logs ==='
echo "`$SUDO_PW" | sudo -S -p '' ls -lah /home/farzadb/.claude/logs/ 2>&1 | tail -40
echo '=== conf ==='
echo "`$SUDO_PW" | sudo -S -p '' cat /home/farzadb/.claude-connect.conf 2>&1 | head -80
echo '=== find ==='
echo "`$SUDO_PW" | sudo -S -p '' find /home/farzadb/.claude -name 'connect*' -type f 2>/dev/null
latest=`$(echo "`$SUDO_PW" | sudo -S -p '' bash -lc 'ls -1t /home/farzadb/.claude/logs/connect*.log 2>/dev/null | head -1')
echo LATEST=`$latest
if [ -n "`$latest" ]; then
  echo "`$SUDO_PW" | sudo -S -p '' wc -l "`$latest"
  echo "`$SUDO_PW" | sudo -S -p '' tail -n 100 "`$latest" | cut -c1-220
fi
"@
$out = $script | ssh -o BatchMode=yes -o ConnectTimeout=15 -o IdentityAgent=none smart@192.168.250.70 "bash -s"
Write-Output $out
