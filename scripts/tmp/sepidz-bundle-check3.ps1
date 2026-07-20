$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'sepidz@192.168.250.70'
$cfg = Get-Content 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1' -Raw
if ($cfg -notmatch "SepidzSudoPassword\s*=\s*'([^']+)'") { throw 'no pw' }
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Matches[1]))

$bash = @"
#!/bin/bash
set +e
PW=`$(printf '%s' '$pwB64' | base64 -d)
sudo_run() {
  printf '%s\n' "`$PW" | sudo -S -p '' bash -lc "`$1"
}
echo "=== share ==="
sudo_run 'ls -la /usr/local/share | head -30'
echo "=== claude-client ==="
sudo_run 'ls -la /usr/local/share/claude-client 2>&1 | head -40; echo VER=`$(cat /usr/local/share/claude-client/connect-version.txt 2>/dev/null || echo MISSING)'
echo "=== claude-server ==="
sudo_run 'command -v claude-server; claude-server 2>&1 | head -15'
echo "=== opt version ==="
sudo_run 'cat /opt/claude-code-server/scripts/client/windows/connect-version.txt 2>&1 || echo no-opt'
echo "=== hosseinm mounts ==="
sudo_run 'ls /home/hosseinm/mounts 2>&1; ls -la /home/hosseinm/mounts/*/  2>&1 | head -40'
sudo_run 'for d in /home/hosseinm/mounts/*; do echo DIR=`$d; ls -ld `$d/.git `$d/.git.server-session 2>&1; done'
echo "=== hosseinm conf ==="
sudo_run 'cat /home/hosseinm/.claude-connect.conf 2>&1'
echo DONE
"@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
& ssh -i $key -o BatchMode=yes -o ConnectTimeout=20 $target "echo $b64 | base64 -d > /tmp/bcheck.sh && bash /tmp/bcheck.sh"
