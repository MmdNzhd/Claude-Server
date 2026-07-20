$r = & ssh -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 smart@192.168.250.70 "echo ok" 2>&1
"ssh_exit=$LASTEXITCODE"
if ($LASTEXITCODE -eq 0) {
  & ssh -o BatchMode=yes -o ConnectTimeout=5 smart@192.168.250.70 @'
ver=$(tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null)
ip=$(grep -o '192.168.[0-9.]*' /usr/local/share/claude-client/connect.ps1 2>/dev/null | head -1)
bash -n /usr/local/share/claude-client/mac/claude-mount.sh >/dev/null 2>&1 && m=OK || m=FAIL
echo version=$ver
echo ip=$ip
echo mount=$m
'@
} else {
  'SSH_FAILED'
  $r
}
