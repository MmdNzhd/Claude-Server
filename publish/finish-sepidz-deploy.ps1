#Requires -Version 5.1
# finish-sepidz-deploy.ps1 - upload + install Sepidz auto-update bundle only
param(
    [string]$ProjectRoot = '',
    [switch]$ForceUnfreeze
)
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Get-DeployCredentials.ps1')
$ErrorActionPreference = 'Stop'

$frozenMarker = Join-Path $PSScriptRoot 'SEPIDZ_PUBLISH_FROZEN'
if ((Test-Path -LiteralPath $frozenMarker) -and (-not $ForceUnfreeze)) {
    Write-Host ''
    Write-Host 'Sepidz server deploy is FROZEN (SEPIDZ_PUBLISH_FROZEN).' -ForegroundColor Red
    Write-Host 'To unfreeze: delete publish\SEPIDZ_PUBLISH_FROZEN and pass -ForceUnfreeze' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

if (-not $ProjectRoot) { $ProjectRoot = Split-Path $PSScriptRoot -Parent }

$OutBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$sepidDir = Get-Item -LiteralPath (Join-Path $OutBase 'claude-code-sepidz') -ErrorAction SilentlyContinue
if (-not $sepidDir) {
    $sepidDir = Get-ChildItem $OutBase -Directory -Filter 'claude-code-sepidz-*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
}
if (-not $sepidDir) { throw 'No Sepidz publish folder on Desktop. Run publish-sepidz.bat first.' }

Write-Host ''
Write-Host 'Finish Sepidz server bundle deploy' -ForegroundColor White
Write-Host ''

& (Join-Path $PSScriptRoot 'deploy-client-bundles.ps1') `
    -ProjectRoot $ProjectRoot `
    -SepidClientRoot (Join-Path $sepidDir.FullName 'claude-code') `
    -DeploySmart:$false `
    -DeploySepidz:$true `
    -ForceUnfreeze:$ForceUnfreeze
