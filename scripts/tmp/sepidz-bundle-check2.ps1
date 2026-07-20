$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'sepidz@192.168.250.70'
$cfg = Get-Content 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1' -Raw
if ($cfg -notmatch "SepidzSudoPassword\s*=\s*'([^']+)'") { throw 'no pw' }
$pwJson = ConvertTo-Json $Matches[1]

$bash = @'
#!/bin/bash
set +e
PW_JSON=PW_PLACEHOLDER
PW=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]))' "$PW_JSON")
sudo_run() {
  printf '%s\n' "$PW" | sudo -S -p '' bash -c "$1" 2>/dev/null
}
echo "=== share ==="
sudo_run 'ls -la /usr/local/share | head -30'
echo "=== claude-client ==="
sudo_run 'ls -la /usr/local/share/claude-client 2>&1 | head -40; echo VER=$(cat /usr/local/share/claude-client/connect-version.txt 2>/dev/null || echo MISSING)'
echo "=== claude-server ==="
sudo_run 'command -v claude-server; head -5 $(command -v claude-server) 2>/dev/null'
echo "=== opt version ==="
sudo_run 'cat /opt/claude-code-server/scripts/client/windows/connect-version.txt 2>&1'
echo "=== smart mount version ==="
sudo_run 'cat /home/smart/mounts/claude-code-server/scripts/client/windows/connect-version.txt 2>&1'
echo "=== hosseinm mounts ==="
sudo_run 'ls /home/hosseinm/mounts 2>&1; ls -la /home/hosseinm/mounts/sepidz-web/.git 2>&1; ls -la /home/hosseinm/mounts/sepidz-web/.git.server-session 2>&1'
echo "=== hosseinm conf ==="
sudo_run 'cat /home/hosseinm/.claude-connect.conf 2>&1'
echo DONE
'@
$bash = $bash.Replace('PW_PLACEHOLDER', $pwJson)
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
& ssh -i $key -o BatchMode=yes -o ConnectTimeout=20 $target "echo $b64 | base64 -d > /tmp/bcheck.sh && bash /tmp/bcheck.sh"
