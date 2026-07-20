$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$cfg = Get-Content 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1' -Raw
if ($cfg -notmatch "SepidzSudoPassword\s*=\s*'([^']+)'") { throw 'no pw' }
$pwJson = ConvertTo-Json $Matches[1]
$bash = @"
set +e
PW=$pwJson
PW=`${PW#\"}; PW=`${PW%\"}
echo '=== sepidz client bundle ==='
printf '%s\n' \"`$PW\" | sudo -S -p '' cat /usr/local/share/claude-client/connect-version.txt 2>/dev/null || echo MISSING
printf '%s\n' \"`$PW\" | sudo -S -p '' wc -l /usr/local/share/claude-client/manifest.txt 2>/dev/null
printf '%s\n' \"`$PW\" | sudo -S -p '' ls /usr/local/share/claude-client 2>/dev/null | head -25
echo '=== hosseinm ==='
printf '%s\n' \"`$PW\" | sudo -S -p '' cat /home/hosseinm/.claude-connect.conf 2>/dev/null
echo '=== done ==='
"@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
& ssh -i $key -o BatchMode=yes -o ConnectTimeout=15 sepidz@192.168.250.70 "echo $b64 | base64 -d | bash"
