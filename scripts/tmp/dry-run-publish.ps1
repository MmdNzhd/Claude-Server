$ErrorActionPreference = 'Stop'
Set-Location (Get-Location)
Write-Host '=== SmartOnly dry run ===' -ForegroundColor Cyan
& .\publish\publish.ps1 -SkipServerDeploy -SkipVersionBump -NoZip -SmartOnly
Write-Host '=== SepidzOnly dry run ===' -ForegroundColor Cyan
& .\publish\publish.ps1 -SkipServerDeploy -SkipVersionBump -NoZip -SepidzOnly
Write-Host 'Dry runs OK' -ForegroundColor Green
