$ErrorActionPreference='Stop'
$root='D:\Smart\Claude-Code-Server'
Write-Output '=== deploy-client-bundles.ps1 PARAM BLOCK ==='
(Get-Content (Join-Path $root 'publish\deploy-client-bundles.ps1') -TotalCount 80)
Write-Output ''
Write-Output '=== publish.ps1 deploy call sites ==='
Select-String -Path (Join-Path $root 'publish\publish.ps1') -Pattern 'deploy-client|DeploySmart|DeploySepidz|Expected|ConnectVersion' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
Write-Output ''
Write-Output '=== bump remaining replacements ==='
(Get-Content (Join-Path $root 'publish\bump-connect-version.ps1') | Select-Object -Skip 80)
Write-Output ''
Write-Output '=== Test-TunnelUp ==='
Select-String -Path (Join-Path $root 'scripts\client\git-mode.ps1') -Pattern 'function Test-TunnelUp|banner|3\s*\*|Cache' -Context 0,2 |
  ForEach-Object { "$($_.LineNumber):$($_.Line)" }
