Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$Server = 'smart@192.168.250.70'
$RemoteDir = 'claude-client-bundle-deploy'

Write-Host "=== Sepidz deploy completion ===" -ForegroundColor White

# 1. Current state
Write-Host "`n[1] Current bundle state..." -ForegroundColor Cyan
& ssh -o BatchMode=yes -o ConnectTimeout=10 $Server @'
if [ -d /usr/local/share/claude-client ]; then
  echo installed=1
  tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt 2>/dev/null
  grep -o "192.168.[0-9.]*" /usr/local/share/claude-client/connect.ps1 2>/dev/null | head -1
else
  echo installed=0
fi
ls -la ~/' + $RemoteDir + '/ 2>/dev/null | tail -5
'@

# 2. Try install (interactive sudo via ssh -t)
Write-Host "`n[2] Running sudo install..." -ForegroundColor Cyan
$installCmd = "chmod +x ~/$RemoteDir/install-client-bundle.sh && sudo bash ~/$RemoteDir/install-client-bundle.sh ~/$RemoteDir/bundle.zip"
$p = Start-Process -FilePath 'ssh' -ArgumentList @('-t','-o','ConnectTimeout=15',$Server,$installCmd) -NoNewWindow -Wait -PassThru
Write-Host "install exit=$($p.ExitCode)"

# 3. Verify after install
Write-Host "`n[3] Post-install verify..." -ForegroundColor Cyan
& ssh -o BatchMode=yes -o ConnectTimeout=10 $Server @'
if [ ! -d /usr/local/share/claude-client ]; then echo FAIL=no-bundle; exit 1; fi
ver=$(tr -d "\r\n" < /usr/local/share/claude-client/connect-version.txt)
ip=$(grep -o "192.168.[0-9.]*" /usr/local/share/claude-client/connect.ps1 | head -1)
bash -n /usr/local/share/claude-client/mac/claude-mount.sh && m=OK || m=FAIL
echo version=$ver
echo ip=$ip
echo mount=$m
test "$ip" = "192.168.250.70" && echo ip_ok=1 || echo ip_ok=0
'@
