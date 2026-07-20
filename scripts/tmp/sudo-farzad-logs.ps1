. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pw = Get-SepidzSudoPassword
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
$remote = @'
PW=$(printf '%s' '"'$b64'"' | base64 -d)
echo "$PW" | sudo -S -p '' bash -lc '
ls -la /home/farzadb/.claude/logs/ 2>/dev/null || echo NO_SERVER_LOGS
ls -la /home/farzadb/.config/claude-connect/logs/ 2>/dev/null || echo NO_LOCAL_STYLE
find /home/farzadb -name "connect*.log" 2>/dev/null | head -20
if ls /home/farzadb/.claude/logs/connect-*.log >/dev/null 2>&1; then
  echo === VERSIONS ===
  grep -h "session start\|UPDATE:\|CONNECT_VERSION=\|20260719.24" /home/farzadb/.claude/logs/connect-*.log | tail -40
fi
'
'@
# simpler approach
$cmd = @"
echo $pw | sudo -S -p '' ls -la /home/farzadb/.claude/logs/ 2>&1 | head -30
echo $pw | sudo -S -p '' bash -c 'grep -h "session start\|UPDATE:\|20260719.24\|CONNECT_VERSION=" /home/farzadb/.claude/logs/connect-*.log 2>/dev/null | tail -60'
"@
$ssh=@('-o','BatchMode=yes','-o','ConnectTimeout=20','-o','IdentitiesOnly=yes','-o','IdentityAgent=none','claude-server-sepidz',$cmd)
& ssh @ssh
