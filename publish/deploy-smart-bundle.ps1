#Requires -Version 5.1
# deploy-smart-bundle.ps1 - upload + install Smart auto-update bundle only
param(
    [string]$ProjectRoot = '',
    [string]$SmartClientRoot = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) { $ProjectRoot = Split-Path $PSScriptRoot -Parent }
if (-not $SmartClientRoot) {
    $OutBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
    $smartDir = Get-ChildItem $OutBase -Directory -Filter 'claude-code-client-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $smartDir) { throw 'No Smart publish folder on Desktop. Run publish.bat or publish-smart.bat first.' }
    $SmartClientRoot = $smartDir.FullName
}

Write-Host ''
Write-Host 'Deploy Smart server bundle only' -ForegroundColor White
Write-Host ''

& (Join-Path $PSScriptRoot 'deploy-client-bundles.ps1') `
    -ProjectRoot $ProjectRoot `
    -SmartClientRoot $SmartClientRoot `
    -DeploySmart:$true `
    -DeploySepidz:$false
