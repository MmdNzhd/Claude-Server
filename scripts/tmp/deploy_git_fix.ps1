$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$nl = [char]10

# 1) push updated claude-mount to Sepidz
scp -o BatchMode=yes -q 'D:\Smart\Claude-Code-Server\scripts\server\claude-mount.sh' 'sepidz@192.168.250.70:/tmp/claude-mount.new'
scp -o BatchMode=yes -q 'D:\Smart\Claude-Code-Server\scripts\tmp\fix_git_now.py' 'sepidz@192.168.250.70:/tmp/fix_git_now.py'

$wrap = @"
#!/bin/bash
set -e
PW=`$(echo $pwB64 | base64 -d)
printf '%s\n' "`$PW" | sudo -S -p '' cp /tmp/claude-mount.new /usr/local/lib/claude-mount
printf '%s\n' "`$PW" | sudo -S -p '' chmod 755 /usr/local/lib/claude-mount
printf '%s\n' "`$PW" | sudo -S -p '' sed -i 's/\r`$//' /usr/local/lib/claude-mount
printf '%s\n' "`$PW" | sudo -S -p '' python3 /tmp/fix_git_now.py
"@
# Fix: pwB64 already expanded in @" "@ - need careful
$wrap = '#!/bin/bash' + $nl + 'set -e' + $nl + 'PW=$(echo ' + $pwB64 + ' | base64 -d)' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' cp /tmp/claude-mount.new /usr/local/lib/claude-mount' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' chmod 755 /usr/local/lib/claude-mount' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' sed -i ''s/\r$//'' /usr/local/lib/claude-mount' + $nl +
  'printf ''%s\n'' "$PW" | sudo -S -p '''' python3 /tmp/fix_git_now.py' + $nl

[IO.File]::WriteAllText("$env:TEMP\deploy_git_fix.sh", $wrap)
scp -o BatchMode=yes -q "$env:TEMP\deploy_git_fix.sh" 'sepidz@192.168.250.70:/tmp/deploy_git_fix.sh'
ssh -o BatchMode=yes -o ConnectTimeout=180 sepidz@192.168.250.70 'bash /tmp/deploy_git_fix.sh'
