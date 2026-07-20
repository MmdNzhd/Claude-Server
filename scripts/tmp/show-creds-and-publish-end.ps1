$ErrorActionPreference='Continue'
Write-Output '==== Get-DeployCredentials.ps1 ===='
Get-Content 'publish\Get-DeployCredentials.ps1'
Write-Output '==== publish.ps1 deploy tail ===='
$c=Get-Content 'publish\publish.ps1'
$start = ($c | Select-String -Pattern 'deploy-client-bundles|SkipServerDeploy' | Select-Object -First 1).LineNumber
if ($start) { $c[([Math]::Max(0,$start-5))..($c.Count-1)] }
Write-Output '==== smart-deploy.local keys (no values) ===='
if (Test-Path 'publish\smart-deploy.local.ps1') {
  Get-Content 'publish\smart-deploy.local.ps1' | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { $_ }
    elseif ($_ -match '=') { ($_.Split('=')[0] + '=<redacted>') }
    else { $_ }
  }
}
if (Test-Path 'publish\sepidz-deploy.local.ps1') {
  Write-Output '==== sepidz-deploy.local keys ===='
  Get-Content 'publish\sepidz-deploy.local.ps1' | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { $_ }
    elseif ($_ -match '=') { ($_.Split('=')[0] + '=<redacted>') }
    else { $_ }
  }
}
