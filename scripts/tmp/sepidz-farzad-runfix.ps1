$ErrorActionPreference = 'Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pw = Get-SepidzSudoPassword
$local = 'D:\Smart\Claude-Code-Server\scripts\tmp\farzad-fix-remote.sh'
& scp -o BatchMode=yes -o ConnectTimeout=15 -q $local 'sepidz@192.168.250.70:/tmp/farzad-fix-remote.sh'
if ($LASTEXITCODE -ne 0) { throw 'scp failed' }
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
# Build remote command without PowerShell $(...) expansion
$remoteCmd = 'tr -d ''\r'' < /tmp/farzad-fix-remote.sh > /tmp/farzad-fix-remote.lf.sh && chmod +x /tmp/farzad-fix-remote.lf.sh && bash /tmp/farzad-fix-remote.lf.sh "$(echo ' + $pwB64 + ' | base64 -d)"'
Write-Host 'running remote fix...'
& ssh -o BatchMode=yes -o ConnectTimeout=90 sepidz@192.168.250.70 $remoteCmd
Write-Host "ssh_exit=$LASTEXITCODE"
