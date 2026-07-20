$ErrorActionPreference='Stop'
$root='D:\Smart\Claude-Code-Server'
foreach ($f in @(
  'publish\publish-smart.bat',
  'publish\publish-sepidz.bat',
  'publish\publish.bat',
  'publish\finish-smart-deploy.bat',
  'publish\finish-sepidz-deploy.bat',
  'publish\bump-connect-version.ps1'
)) {
  Write-Output "===== $f ====="
  Get-Content (Join-Path $root $f) -TotalCount 80
  Write-Output ''
}
Write-Output '===== deploy-client-bundles verify section ====='
$d=Join-Path $root 'publish\deploy-client-bundles.ps1'
Select-String -Path $d -Pattern 'connect-version|expected|Verify|Write-Host.*deployed' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
Write-Output '--- around 190-240 ---'
(Get-Content $d)[189..239]
