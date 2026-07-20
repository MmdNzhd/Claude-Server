$ErrorActionPreference = 'Continue'
Set-Location D:\Smart\Claude-Code-Server
Write-Output "LOCAL_VER=$(Get-Content .\scripts\client\windows\connect-version.txt -Raw)"
Write-Output "REMOTE_BEFORE="
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none sepidz@192.168.250.70 "cat /usr/local/share/claude-client/connect-version.txt; hostname"
& .\publish\publish.ps1 -SepidzOnly *>&1 | Tee-Object .\scripts\tmp\publish-sepidz-now.log
Write-Output "PUBLISH_EXIT=$LASTEXITCODE"
Write-Output "LOCAL_AFTER=$(Get-Content .\scripts\client\windows\connect-version.txt -Raw)"
Write-Output "REMOTE_AFTER="
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none sepidz@192.168.250.70 "cat /usr/local/share/claude-client/connect-version.txt; hostname"
Write-Output "SMART_CHECK="
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none smart@192.168.210.240 "hostname; cat /usr/local/share/claude-client/connect-version.txt"
