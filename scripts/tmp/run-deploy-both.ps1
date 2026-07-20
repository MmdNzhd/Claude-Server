$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
$desk = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$smart = Join-Path $desk 'claude-code-client-20260717'
$sepid = Join-Path $desk 'claude-code-sepidz-20260717\claude-code'

Write-Host '=== VERIFY LOCAL PACKS ===' -ForegroundColor White
foreach ($p in @(
  (Join-Path $smart 'windows\connect-version.txt'),
  (Join-Path $sepid 'windows\connect-version.txt')
)) {
  Write-Host ("{0} = {1}" -f $p, (Get-Content $p -Raw).Trim())
}
$auth = Join-Path $sepid 'windows\cursor-auth-laptop.ps1'
Write-Host ("auth helpers: " + [bool](Select-String -Path $auth -Pattern 'Get-CursorAuthTempRoot' -Quiet))

Write-Host ''
Write-Host '=== DEPLOY SEPIDZ ===' -ForegroundColor White
& (Join-Path $root 'publish\deploy-client-bundles.ps1') `
  -ProjectRoot $root `
  -SepidClientRoot $sepid `
  -DeploySmart:$false `
  -DeploySepidz:$true
if ($LASTEXITCODE -ne 0) { throw "Sepidz deploy failed exit=$LASTEXITCODE" }

Write-Host ''
Write-Host '=== DEPLOY SMART ===' -ForegroundColor White
& (Join-Path $root 'publish\deploy-client-bundles.ps1') `
  -ProjectRoot $root `
  -SmartClientRoot $smart `
  -DeploySmart:$true `
  -DeploySepidz:$false
if ($LASTEXITCODE -ne 0) { throw "Smart deploy failed exit=$LASTEXITCODE" }

Write-Host 'ALL DEPLOYS OK' -ForegroundColor Green
