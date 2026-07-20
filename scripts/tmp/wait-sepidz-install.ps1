$Server = 'smart@192.168.250.70'
for ($i = 1; $i -le 18; $i++) {
    Start-Sleep -Seconds 5
    $out = & ssh -o BatchMode=yes -o ConnectTimeout=8 $Server @'
if [ -d /usr/local/share/claude-client/connect.ps1 ]; then
  ver=$(tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt)
  ip=$(grep -o "192.168.[0-9.]*" /usr/local/share/claude-client/connect.ps1 | head -1)
  bash -n /usr/local/share/claude-client/mac/claude-mount.sh && m=OK || m=FAIL
  echo READY version=$ver ip=$ip mount=$m
else
  echo WAITING
fi
'@ 2>$null
    Write-Host "[$i] $out"
    if ($out -match 'READY') { exit 0 }
}
exit 1
