Set-Location D:\Smart\Claude-Code-Server
Write-Output "PRE=$(Get-Content .\scripts\client\windows\connect-version.txt -Raw)"
& .\publish\publish.ps1 -SepidzOnly *>&1 | Tee-Object .\scripts\tmp\publish-sepidz-27.log
Write-Output "PUBLISH_EXIT=$LASTEXITCODE"
Write-Output "POST=$(Get-Content .\scripts\client\windows\connect-version.txt -Raw)"
