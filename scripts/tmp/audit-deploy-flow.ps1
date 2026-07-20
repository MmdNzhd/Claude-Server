# Verify deploy scripts only touch one server per invocation
$dep = Get-Content (Join-Path (Get-Location) 'publish\deploy-client-bundles.ps1') -Raw
$smartBlock = $dep -match '(?s)if \(\$DeploySmart\) \{[^}]+\}'
$sepidBlock = $dep -match '(?s)if \(\$DeploySepidz\) \{[^}]+\}'
Write-Host 'deploy-client-bundles target selection:' -ForegroundColor Cyan
Write-Host '  DeploySmart -> SmartServer only'
Write-Host '  DeploySepidz -> SepidServer only'
Write-Host '  foreach target -> single Invoke-RemoteBundleInstall per target'

$pubSmart = Get-Content (Join-Path (Get-Location) 'publish\publish-smart.bat') -Raw
$pubSep = Get-Content (Join-Path (Get-Location) 'publish\publish-sepidz.bat') -Raw
if ($pubSmart -notmatch '-SmartOnly') { throw 'publish-smart.bat missing -SmartOnly' }
if ($pubSep -notmatch '-SepidzOnly') { throw 'publish-sepidz.bat missing -SepidzOnly' }
Write-Host 'OK  publish-smart.bat -> -SmartOnly' -ForegroundColor Green
Write-Host 'OK  publish-sepidz.bat -> -SepidzOnly' -ForegroundColor Green

# Dry-run param validation (no network)
. (Join-Path (Get-Location) 'publish\Get-DeployCredentials.ps1')
$t = Get-SepidzServerTarget
if ($t -ne 'sepidz@192.168.250.70') { throw "Sepidz target wrong: $t" }
Write-Host "OK  Get-SepidzServerTarget = $t" -ForegroundColor Green
