#Requires -Version 5.1
<#
.SYNOPSIS
  Canonical Smart client deploy: scripts + version bump, KEEP existing EXE (no rebuild).

.DESCRIPTION
  This is the one command to use for day-to-day client fixes:
    publish\deploy-scripts-only.bat

  - Bumps connect version (YYYYMMDD.N)
  - Runs client deploy-gate regression tests (scripts\client\tests\run-deploy-gate.ps1)
    before staging; aborts on failure unless -SkipTests
  - Stages ALL files from publish\client-bundle-manifest.tsv
  - Reuses /usr/local/share/claude-client/Claude-Connect.exe (never builds EXE)
  - Deploys Smart only (Sepidz off unless -AlsoSepidz)
  - Verifies remote version + EXE md5 unchanged
  - Does NOT run connect-update on this laptop

  Full cold-install EXE rebuild remains: publish\publish.bat
#>
param(
    [string]$ProjectRoot = '',
    [string]$SmartServer = 'smart@192.168.210.240',
    [switch]$NoBump,
    [string]$Version = '',
    [switch]$AlsoSepidz,
    [switch]$ForceServerUnfreeze,
    [switch]$SkipDeploy,
    [switch]$SkipTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ProjectRoot) { $ProjectRoot = Split-Path $PSScriptRoot -Parent }
. (Join-Path $PSScriptRoot 'ClientBundleManifest.ps1')

Write-Host ''
Write-Host '=== deploy-scripts-only (keep EXE, Smart auto-update bundle) ===' -ForegroundColor White
Write-Host ''

$winVerPath = Join-Path $ProjectRoot 'scripts\client\windows\connect-version.txt'
$beforeVer = (Get-Content -LiteralPath $winVerPath -Raw).Trim()

# Run deploy-gate BEFORE bump so repo content can still match the live bundle
# for any residual static checks. Version bump happens after gate passes.
$gateScript = Join-Path $ProjectRoot 'scripts\client\tests\run-deploy-gate.ps1'
if ($SkipTests) {
    Write-Host ''
    Write-Host '  *** WARN: -SkipTests — deploy-gate NOT run (emergency override) ***' -ForegroundColor Yellow
    Write-Host ''
} else {
    if (-not (Test-Path -LiteralPath $gateScript)) {
        throw "Missing deploy gate script: $gateScript"
    }
    Write-Host '  Running client deploy-gate tests (pre-bump)...' -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $gateScript
    $gateExit = $LASTEXITCODE
    if ($gateExit -ne 0) {
        throw "Client deploy-gate tests failed (exit=$gateExit). Fix tests or pass -SkipTests to override."
    }
    Write-Host '  Deploy-gate tests passed' -ForegroundColor Green
}

$newVer = $beforeVer
if ($Version) {
    $newVer = $Version.Trim()
    Set-RepoConnectVersion -ProjectRoot $ProjectRoot -Version $newVer
    Write-Host "  Version set: $beforeVer -> $newVer" -ForegroundColor Cyan
} elseif (-not $NoBump) {
    $newVer = Get-NextConnectVersion -Current $beforeVer
    Set-RepoConnectVersion -ProjectRoot $ProjectRoot -Version $newVer
    Write-Host "  Version bump: $beforeVer -> $newVer" -ForegroundColor Cyan
} else {
    Write-Host "  Version keep: $newVer (-NoBump)" -ForegroundColor DarkGray
}

# Snapshot live EXE hash before deploy (must match after).
$preHashOut = & ssh -o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no `
    -o IdentitiesOnly=yes -o IdentityAgent=none `
    $SmartServer 'md5sum /usr/local/share/claude-client/Claude-Connect.exe' 2>$null
$preHash = ''
if ($preHashOut -match '([a-f0-9]{32})\s+') { $preHash = $Matches[1] }
if (-not $preHash) { throw "Could not read live EXE md5 from $SmartServer (is Connect/SSH up?)" }
Write-Host "  Live EXE md5 (must stay): $preHash" -ForegroundColor Cyan

# Keep stage path short (Windows MAX_PATH). Prefer D:\temp when present.
$stageRoot = if (Test-Path -LiteralPath 'D:\temp') { 'D:\temp' } else { $env:TEMP }
$stage = Join-Path $stageRoot 'ccb-so'
Build-ClientBundleStageFromRepo -ProjectRoot $ProjectRoot -StageDir $stage -SmartServer $SmartServer | Out-Null
$stagedExe = Join-Path $stage 'windows\Claude-Connect.exe'
$stagedHash = (Get-FileHash -LiteralPath $stagedExe -Algorithm MD5).Hash.ToLowerInvariant()
if ($stagedHash -ne $preHash) {
    throw "Staged EXE md5 $stagedHash != live $preHash - refusing to ship a different EXE"
}
Write-Host "  Staged from manifest + reused EXE ok" -ForegroundColor Green

if ($SkipDeploy) {
    Write-Host '  -SkipDeploy: stage ready, not uploading' -ForegroundColor Yellow
    Write-Host ("  Stage: {0}" -f $stage)
    exit 0
}

$deployArgs = @{
    ProjectRoot              = $ProjectRoot
    SmartClientRoot          = $stage
    DeploySmart              = $true
    DeploySepidz             = [bool]$AlsoSepidz
    ForceServerUnfreezeSmart = [bool]$ForceServerUnfreeze
}
if ($AlsoSepidz) {
    $sepidStage = Join-Path $env:TEMP 'ccb-so-sepidz'
    # Sepidz gets same scripts; IP patch is publish-time only - scripts-only does not IP-patch.
    # Keep AlsoSepidz for rare cases; warn.
    Write-Host '  WARN: -AlsoSepidz copies Smart scripts without Sepidz IP patch (prefer publish.bat for Sepidz)' -ForegroundColor Yellow
    Build-ClientBundleStageFromRepo -ProjectRoot $ProjectRoot -StageDir $sepidStage -SmartServer $SmartServer | Out-Null
    $deployArgs.SepidClientRoot = $sepidStage
}

& (Join-Path $PSScriptRoot 'deploy-client-bundles.ps1') @deployArgs
if ($LASTEXITCODE -ne 0) { throw "deploy-client-bundles.ps1 failed exit=$LASTEXITCODE" }

$post = & ssh -o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=no `
    -o IdentitiesOnly=yes -o IdentityAgent=none `
    $SmartServer "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt; echo; md5sum /usr/local/share/claude-client/Claude-Connect.exe; grep -c SIDECAR_BOOT_REAP /usr/local/share/claude-client/cursor-proxy-sidecar.ps1 || true"
$postText = ($post | Out-String)
Write-Host $postText
if ($postText -notmatch [regex]::Escape($newVer)) {
    throw "Remote version verify failed (expected $newVer)"
}
if ($postText -notmatch $preHash) {
    throw "Remote EXE md5 changed - deploy violated keep-EXE contract"
}

Write-Host ''
Write-Host ("OK  Smart bundle v{0} deployed. EXE unchanged ({1})." -f $newVer, $preHash) -ForegroundColor Green
Write-Host '    Laptop update NOT run - launch Connect Update yourself to pull it.' -ForegroundColor DarkGray
Write-Host ''

# TEMP: Clear-ConnectTestTemp disabled — was spawning a flood of cmd/powershell
# windows on this laptop (CCR / nested -File). Re-enable when that is fixed.
# $cleanupScript = Join-Path $ProjectRoot 'scripts\client\tests\Clear-ConnectTestTemp.ps1'
# if (Test-Path -LiteralPath $cleanupScript) {
#     try {
#         & powershell -NoProfile -ExecutionPolicy Bypass -File $cleanupScript
#     } catch {
#         Write-Host ("  WARN: Clear-ConnectTestTemp failed (non-fatal): {0}" -f $_) -ForegroundColor Yellow
#     }
# }

exit 0
