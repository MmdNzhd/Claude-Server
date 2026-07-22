$ErrorActionPreference = 'Stop'
& 'D:\Smart\Claude-Code-Server\publish\publish.ps1' -SmartOnly -SkipVersionBump
Write-Host "PUB_EXIT=$LASTEXITCODE"
