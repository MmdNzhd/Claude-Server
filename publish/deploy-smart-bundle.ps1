#Requires -Version 5.1
# deploy-smart-bundle.ps1 - thin wrapper → deploy-scripts-only.ps1 (canonical path).
# Prefer: publish\deploy-scripts-only.bat
param(
    [string]$ProjectRoot = '',
    [string]$SmartClientRoot = '',
    [switch]$ForceServerUnfreeze,
    [switch]$LegacyPublishFolder
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) { $ProjectRoot = Split-Path $PSScriptRoot -Parent }

# Default: scripts-only from repo (bump + keep EXE). Legacy path only if explicitly requested
# with an already-published Desktop folder (includes whatever EXE that folder has).
if ($LegacyPublishFolder -or $SmartClientRoot) {
    if (-not $SmartClientRoot) {
        $OutBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
        $smartDir = Get-ChildItem $OutBase -Directory -Filter 'claude-code-client*' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $smartDir) { throw 'No Smart publish folder on Desktop. Use deploy-scripts-only.bat instead.' }
        $SmartClientRoot = $smartDir.FullName
    }
    Write-Host 'WARN: legacy publish-folder deploy (may ship folder EXE). Prefer deploy-scripts-only.bat' -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot 'deploy-client-bundles.ps1') `
        -ProjectRoot $ProjectRoot `
        -SmartClientRoot $SmartClientRoot `
        -DeploySmart `
        -DeploySepidz:$false `
        -ForceServerUnfreezeSmart:$ForceServerUnfreeze
    exit $LASTEXITCODE
}

& (Join-Path $PSScriptRoot 'deploy-scripts-only.ps1') `
    -ProjectRoot $ProjectRoot `
    -ForceServerUnfreeze:$ForceServerUnfreeze
exit $LASTEXITCODE
