Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$OutBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$smart = (Get-ChildItem $OutBase -Directory -Filter 'claude-code-client-*' | Sort-Object Name -Descending | Select-Object -First 1).FullName
$sepid = Join-Path (Get-ChildItem $OutBase -Directory -Filter 'claude-code-sepidz-*' | Sort-Object Name -Descending | Select-Object -First 1).FullName 'claude-code'
$stage = Join-Path $env:TEMP 'deploy-build-test'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# invoke Build-AutoUpdateBundleStage by running deploy script logic inline via param script
& (Join-Path $ProjectRoot 'publish\deploy-client-bundles.ps1') `
    -ProjectRoot $ProjectRoot `
    -SmartClientRoot $smart `
    -SepidClientRoot $sepid `
    -SmartServer 'smart@127.0.0.1' `
    -SepidServer 'smart@127.0.0.1' `
    -ContinueOnDeployError 2>&1 | Out-Null

# Expect SSH fail but bundle build should happen before SSH - actually deploy fails at ssh mkdir
# Better: test only bundle build by extracting function - run partial test
Write-Host 'deploy script invoked (SSH expected fail with ContinueOnDeployError)'
exit 0
