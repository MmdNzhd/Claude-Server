#Requires -Version 5.1
# finish-sepidz-deploy.ps1 - upload + install Sepidz auto-update bundle only
param([string]$ProjectRoot = '')
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Get-DeployCredentials.ps1')
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) { $ProjectRoot = Split-Path $PSScriptRoot -Parent }

$OutBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$sepidDir = Get-ChildItem $OutBase -Directory -Filter 'claude-code-sepidz-*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $sepidDir) { throw 'No Sepidz publish folder on Desktop. Run publish-sepidz.bat first.' }

Write-Host ''
Write-Host 'Finish Sepidz server bundle deploy' -ForegroundColor White
Write-Host ''

& (Join-Path $PSScriptRoot 'deploy-client-bundles.ps1') `
    -ProjectRoot $ProjectRoot `
    -SepidClientRoot (Join-Path $sepidDir.FullName 'claude-code') `
    -DeploySmart:$false `
    -DeploySepidz:$true
