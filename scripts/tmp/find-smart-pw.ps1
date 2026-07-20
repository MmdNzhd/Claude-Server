$ErrorActionPreference='SilentlyContinue'
$cands=@(
  'D:\Smart\Claude-Code-Server\publish\smart-deploy.local.ps1',
  (Join-Path $env:USERPROFILE '.config\claude-connect\smart-deploy.local.ps1'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\smart-deploy.local.ps1')
)
foreach($c in $cands){ Write-Output ("exists={0} path={1}" -f (Test-Path $c), $c) }
# Can smart user sudo via echo from known env? Don't print.
# Try ssh key as root? 
ssh -o BatchMode=yes -o ConnectTimeout=8 smart@192.168.210.240 "id; ls /usr/local/share/claude-client/connect-version.txt 2>/dev/null; cat /usr/local/share/claude-client/connect-version.txt 2>/dev/null"
