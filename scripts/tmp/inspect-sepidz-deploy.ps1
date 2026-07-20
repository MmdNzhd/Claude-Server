$ErrorActionPreference='Continue'
Write-Host '=== versions ==='
Get-Content scripts/client/windows/connect-version.txt
Get-Content scripts/client/mac/connect-version.txt
Write-Host '=== finish/deploy scripts ==='
Get-ChildItem publish/*sepidz* | Select-Object Name,Length,LastWriteTime
Write-Host '=== deploy-client-bundles params ==='
Select-String -Path publish/deploy-client-bundles.ps1 -Pattern 'param\(|Password|Identity|Sepidz|ServerTarget|Get-Deploy' | Select-Object -First 40 | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
Write-Host '=== finish-sepidz-deploy.ps1 head ==='
Get-Content publish/finish-sepidz-deploy.ps1 -TotalCount 80
Write-Host '=== local.ps1 example keys (no secrets) ==='
if (Test-Path publish/sepidz-deploy.local.ps1) {
  Select-String -Path publish/sepidz-deploy.local.ps1 -Pattern '^[\$A-Za-z].*=' | ForEach-Object { ($_.Line -replace '=.*','=***') }
} else { Write-Host 'NO sepidz-deploy.local.ps1' }
Write-Host '=== package on desktop ==='
Get-ChildItem "$env:USERPROFILE\Desktop\claude-publish\claude-code-sepidz-20260719*" | Select-Object FullName,Length,LastWriteTime
