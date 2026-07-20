$ErrorActionPreference = 'Continue'
Set-Location D:\Smart\Claude-Code-Server
Write-Output "VERSION=$(Get-Content .\scripts\client\windows\connect-version.txt -Raw)"
& .\publish\publish.ps1 -SepidzOnly *>&1 | Tee-Object .\scripts\tmp\publish-sepidz-25.log
Write-Output "PUBLISH_EXIT=$LASTEXITCODE"
