#Requires -Version 5.1
# test-connect-heal-downloads-stale.ps1
# Product debt (docs/connect-fix-evidence/FLEET-PROBLEMS-20260801.md, "Product debt" /
# 2026-08-01 deep probe): heal/push only ever writes Desktop\Claude-Connect. A process
# still running out of a portable Downloads\Claude-Connect\{oldver}\ tree never picks up
# the push on its own. connect-heal.ps1 must detect ScriptDir under Downloads that is
# OLDER than the canonical Desktop install and force a handoff (exit 2 + relaunch marker),
# not just silently continue because the Downloads copy still has all its own files.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== connect-heal: stale Downloads runner forces handoff ===' -ForegroundColor White

$healPath = Get-ClientFile 'windows\connect-heal.ps1'
$heal = Get-Content -LiteralPath $healPath -Raw

# 1) Detection: ScriptDir under any Downloads subtree is recognized.
Assert (
    $heal -match '\$isUnderDownloads\s*=\s*\(\s*\$Here\s*-match\s*''\(\?i\)\[\\\\/\]Downloads\[\\\\/\]''\s*\)'
) 'isUnderDownloads detects any \Downloads\ path segment (case-insensitive)'

# 2) Staleness compares Here's own connect-version.txt against the canonical Desktop
#    install's resolved version - not just file presence/"goodness".
Assert (
    $heal -match '\$downloadsStale\s*=\s*\$false' -and
    $heal -match '\$hereVer\s*=\s*Get-ClientDirVersion\s+-Dir\s+\$Here' -and
    $heal -match '\$canonVerNow\s*=\s*Get-ClientDirVersion\s+-Dir\s+\$canonScript' -and
    $heal -match '\(Compare-ClientVersion\s+-A\s+\$hereVer\s+-B\s+\$canonVerNow\)\s+-lt\s+0\)\s*\{\s*\$downloadsStale\s*=\s*\$true\s*\}'
) 'downloadsStale is a real version compare (hereVer < canonVerNow), not a presence check'

# 3) A Downloads copy that still has every required file ("good") must still be forced to
#    redirect when stale - this is exactly the gap the fleet incident exposed (Aria /
#    amirhossein kept running a fully-intact old Downloads tree that never updated).
Assert (
    $heal -match 'elseif\s*\(\s*\$downloadsStale\s*\)\s*\{\s*\$shouldRedirect\s*=\s*\$true\s*\}'
) 'shouldRedirect fires on downloadsStale even when hereGood is true'

# 4) Handoff reuses the existing relaunch-marker + exit-2 contract (same mechanism as
#    legacy-dated / publish-tree redirects) so connect.bat HEAL_RELAUNCH picks it up.
Assert (
    $heal -match 'if\s*\(\s*\$shouldRedirect\s*\)\s*\{' -and
    ([regex]::Match($heal, '(?s)if\s*\(\s*\$shouldRedirect\s*\)\s*\{.*?exit 2').Value -match 'Set-Content -LiteralPath \$RelaunchMarker -Value \$CanonSmart')
) 'stale-Downloads redirect uses the same $RelaunchMarker / exit 2 handoff as other redirects'

# 5) Warning text names the actual problem (old Downloads copy) instead of the generic
#    "Old/publish folder" message, so a user staring at the console understands why.
Assert (
    $heal -match 'Older Downloads copy detected'
) 'user-facing warning distinguishes stale-Downloads case from generic old/publish redirect'

# 6) Log line carries enough evidence (both versions) to diagnose fleet-wide without asking
#    the user to reproduce.
Assert (
    $heal -match 'HEAL_REDIRECT from=\{0\} to=\{1\} legacy=\{2\} publish=\{3\} downloads_stale=\{4\} here_ver=\{5\} canon_ver=\{6\}'
) 'HEAL_REDIRECT log line records downloads_stale/here_ver/canon_ver'

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'All connect-heal Downloads-stale asserts passed.' -ForegroundColor Green
    exit 0
}
Write-Host "$fail assert(s) failed." -ForegroundColor Red
exit 1
