$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$cfg = Get-Content 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1' -Raw
if ($cfg -notmatch "SepidzSudoPassword\s*=\s*'([^']+)'") { throw 'no pw' }
$pwJson = ConvertTo-Json $Matches[1]
$bash = @"
set +e
PW=$pwJson
PW=`${PW#\"}; PW=`${PW%\"}
run() { printf '%s\n' \"`$PW\" | sudo -S -p '' bash -c \"`$1\"; }
echo '=== ls share ==='
run 'ls -la /usr/local/share/ 2>&1 | head -30'
echo '=== claude-client ==='
run 'ls -la /usr/local/share/claude-client 2>&1 | head -40'
echo '=== which claude-server ==='
run 'which claude-server; type claude-server; claude-server 2>&1 | head -20'
echo '=== opt repo ==='
run 'ls /opt/claude-code-server/scripts/client/windows/connect-version.txt 2>&1; cat /opt/claude-code-server/scripts/client/windows/connect-version.txt 2>&1'
echo '=== smart mounts on sepidz? ==='
run 'ls /home/smart/mounts/claude-code-server/scripts/client/windows/connect-version.txt 2>&1'
echo '=== sepidz-web git ==='
run 'ls -la /home/hosseinm/mounts/sepidz-web/.git 2>&1; ls /home/hosseinm/mounts/ 2>&1 | head'
echo '=== done ==='
"@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
& ssh -i $key -o BatchMode=yes -o ConnectTimeout=15 sepidz@192.168.250.70 "echo $b64 | base64 -d | bash"
