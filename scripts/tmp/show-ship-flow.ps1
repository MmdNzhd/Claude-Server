$ErrorActionPreference='Continue'
Write-Output '==== publish.ps1 params/top ===='
Get-Content 'publish\publish.ps1' -TotalCount 80
Write-Output '==== finish-smart-deploy.ps1 ===='
Get-Content 'publish\finish-smart-deploy.ps1' -TotalCount 80
Write-Output '==== finish-sepidz-deploy.ps1 ===='
Get-Content 'publish\finish-sepidz-deploy.ps1' -TotalCount 80
Write-Output '==== deploy-smart-bundle.ps1 head ===='
Get-Content 'publish\deploy-smart-bundle.ps1' -TotalCount 60
# local files exist but don't print secrets
Write-Output '==== local deploy files (keys only) ===='
foreach ($f in @('publish\smart-deploy.local.ps1','publish\sepidz-deploy.local.ps1')) {
  if (Test-Path $f) {
    Select-String -Path $f -Pattern '^[A-Za-z_][A-Za-z0-9_]*\s*=' |
      ForEach-Object { ($_.Line -split '=',2)[0].Trim() }
  } else { "missing $f" }
}
