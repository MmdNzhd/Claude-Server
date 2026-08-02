#Requires -Version 5.1
# test-bundle-deploy-cohesion.ps1 - P1.1/P1.2 structural deploy + co-origination gates
# Covers: refuse silent server-fallback, post-swap checksum verify, retired ad-hoc ship
# helpers, ConnectBuildId/GitModeBuildId co-origination, same-version content drift refuse.
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== bundle deploy cohesion (P1.1 / P1.2 residual) ==='
Write-Host ''

$dcbPath = Join-Path $RepoRoot 'scripts\server\commands\deploy-client-bundle.sh'
$dcb = Get-Content $dcbPath -Raw
$ship = Get-Content (Join-Path $RepoRoot 'scripts\client\tests\_ship-update-files.sh') -Raw
$fixSum = Get-Content (Join-Path $RepoRoot 'scripts\client\tests\_fix-bundle-checksums.sh') -Raw
$bump = Get-Content (Join-Path $RepoRoot 'publish\bump-connect-version.ps1') -Raw
$cps1 = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect.ps1') -Raw
$gm = Get-Content (Join-Path $RepoRoot 'scripts\client\git-mode.ps1') -Raw
$bat = Get-Content (Join-Path $RepoRoot 'scripts\client\windows\connect.bat') -Raw

# --- Bug 1: server-fallback must not silently promote ---
Assert ($dcb -match 'ALLOW_STALE_SERVER_FALLBACK') `
    'deploy documents ALLOW_STALE_SERVER_FALLBACK override'
Assert ($dcb -match 'refuse server-fallback|refuse.*server-fallback|server-fallback.*refuse') `
    'deploy hard-fails server-fallback by default (no silent stale ship)'
Assert ($dcb -match 'BUNDLE_SOURCE_KIND="server-fallback"') `
    'deploy still records server-fallback kind when override is used'
Assert ($dcb -match 'STALE SERVER FALLBACK|loud.*fallback|FALLBACK_SOURCE') `
    'override path emits a loud impossible-to-miss banner'
Assert ($dcb -match '_assert_fallback_not_staler_than_live|_fallback_freshness') `
    'override path compares fallback freshness vs live share'

# --- Bug 1: post-swap sha256sum -c ---
Assert ($dcb -match 'sha256sum -c|shasum -a 256 -c') `
    'deploy post-swap verifies checksums.txt against live tree'
Assert ($dcb -match 'post-swap checksum|_verify_live_bundle_checksums') `
    'deploy names the post-swap checksum gate'

# --- Bug 1: same-version content drift refuse ---
Assert ($dcb -match '_refuse_same_version_content_drift|same.version.*content.*drift|content drift') `
    'deploy refuses same-version / different-content promote'

# --- Bug 1: stamp source kind into bundle ---
Assert ($dcb -match 'bundle-origin\.txt') `
    'deploy writes bundle-origin.txt (version + build_id + source_kind)'

# --- Bug 1: ad-hoc ship helpers retired or find-aligned ---
Assert ($ship -match 'RETIRED|deploy-client-bundle') `
    '_ship-update-files.sh retired / redirects to deploy-client-bundle'
Assert ($ship -notmatch '(?m)^install -m 644 "\$STAGE/connect-update') `
    '_ship-update-files.sh no longer mutates live share in-place'
Assert ($fixSum -match 'RETIRED|deploy-client-bundle') `
    '_fix-bundle-checksums.sh retired / redirects to deploy-client-bundle'
Assert ($fixSum -notmatch '(?m)^install -m 644 "\$tmp" checksums\.txt') `
    '_fix-bundle-checksums.sh no longer rewrites checksums from manifest'

# --- Bug 2: co-origination stamps ---
Assert ($cps1 -match "ConnectBuildId = '[0-9a-fA-F-]{36}'") `
    'connect.ps1 has ConnectBuildId GUID'
Assert ($gm -match "GitModeBuildId = '[0-9a-fA-F-]{36}'") `
    'git-mode.ps1 has GitModeBuildId GUID (co-origination stamp)'
$cpBid = if ($cps1 -match "ConnectBuildId = '([^']+)'") { $Matches[1] } else { '' }
$gmBid = if ($gm -match "GitModeBuildId = '([^']+)'") { $Matches[1] } else { '' }
Assert (($cpBid.Length -gt 0) -and ($cpBid -eq $gmBid)) `
    ("connect.ps1 ConnectBuildId == git-mode.ps1 GitModeBuildId (got cp=$cpBid gm=$gmBid)")
Assert ($cps1 -match 'GitModeBuildId|ConnectBundleCohesion|split-generation|co-origination') `
    'connect.ps1 asserts build-id cohesion after sourcing git-mode'
Assert ($bat -match 'GitModeBuildId|ConnectBuildId|BUNDLE_COHESION|cohesion') `
    'connect.bat OUTDATED path also checks build-id co-origination'
Assert ($bump -match 'GitModeBuildId') `
    'bump-connect-version.ps1 stamps GitModeBuildId alongside ConnectBuildId'

# --- Behavioral: mixed-generation detection would fail ---
function Get-Ps1BuildId([string]$Text, [string]$VarName) {
    if ($Text -match "$VarName = '([^']+)'") { return $Matches[1] }
    return ''
}
function Test-BundleCohesionPair([string]$ConnectText, [string]$GitModeText) {
    $a = Get-Ps1BuildId $ConnectText 'ConnectBuildId'
    $b = Get-Ps1BuildId $GitModeText 'GitModeBuildId'
    if (-not $a -or -not $b) { return $false }
    return ($a -eq $b)
}
$mixedGm = $gm -replace "GitModeBuildId = '[^']+'", "GitModeBuildId = '00000000-0000-0000-0000-000000000099'"
Assert (Test-BundleCohesionPair $cps1 $gm) 'cohesion helper accepts matched pair'
Assert (-not (Test-BundleCohesionPair $cps1 $mixedGm)) `
    'cohesion helper rejects mixed-generation pair (would have caught 20260801.10 split ship)'

# --- Behavioral: post-swap checksum verify catches inconsistency (git bash) ---
$bash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path $bash)) { $bash = 'bash' }
$tmpRoot = Join-Path $env:TEMP ("cc-bundle-cohesion-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
try {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $tmpRoot 'a.txt'), "hello`n", $utf8)
    [System.IO.File]::WriteAllText((Join-Path $tmpRoot 'b.txt'), "world`n", $utf8)
    $mkSum = @'
set -euo pipefail
cd "$1"
if command -v sha256sum >/dev/null 2>&1; then
  find . -type f ! -name checksums.txt -print0 | sort -z | xargs -0 sha256sum | sed 's|  \./|  |' > checksums.txt
else
  find . -type f ! -name checksums.txt -print0 | sort -z | xargs -0 shasum -a 256 | sed 's|  \./|  |' > checksums.txt
fi
'@
    $mkPath = Join-Path $tmpRoot 'mk.sh'
    [System.IO.File]::WriteAllText($mkPath, $mkSum, $utf8)
    & $bash $mkPath $tmpRoot
    Assert ($LASTEXITCODE -eq 0) 'simulated find-based checksums.txt write ok'

    $verifyOk = @'
set -euo pipefail
cd "$1"
if command -v sha256sum >/dev/null 2>&1; then sha256sum -c checksums.txt --status
else shasum -a 256 -c checksums.txt >/dev/null
fi
'@
    $vPath = Join-Path $tmpRoot 'v.sh'
    [System.IO.File]::WriteAllText($vPath, $verifyOk, $utf8)
    & $bash $vPath $tmpRoot
    Assert ($LASTEXITCODE -eq 0) 'post-swap style verify passes on consistent tree'

    [System.IO.File]::WriteAllText((Join-Path $tmpRoot 'a.txt'), "TAMPERED`n", $utf8)
    & $bash $vPath $tmpRoot
    Assert ($LASTEXITCODE -ne 0) 'post-swap style verify fails on inconsistent tree (P1.1 class)'
} finally {
    Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Behavioral: stale-fallback decision (mini bash mirror of refuse-by-default) ---
$fbScript = @'
set -euo pipefail
BUNDLE_SOURCE_KIND="server-fallback"
if [ "${ALLOW_STALE_SERVER_FALLBACK:-0}" != "1" ]; then
  echo "REFUSE_STALE_FALLBACK"
  exit 9
fi
echo "ALLOW_OVERRIDE"
exit 0
'@
$fbPath = Join-Path $env:TEMP ("cc-fb-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".sh")
try {
    [System.IO.File]::WriteAllText($fbPath, $fbScript, (New-Object System.Text.UTF8Encoding $false))
    & $bash $fbPath
    Assert ($LASTEXITCODE -eq 9) 'stale-fallback refuses without ALLOW override (exit 9)'
    $env:ALLOW_STALE_SERVER_FALLBACK = '1'
    & $bash $fbPath
    Assert ($LASTEXITCODE -eq 0) 'stale-fallback allows only with ALLOW_STALE_SERVER_FALLBACK=1'
} finally {
    Remove-Item Env:ALLOW_STALE_SERVER_FALLBACK -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fbPath -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All {0} cohesion contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
