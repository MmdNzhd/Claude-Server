#Requires -Version 5.1
# Source contracts: skip BgAuthStampProc.WaitForExit(5000) when stamp already known current.
# AUTH_STAMP_WAIT_SKIPPED reason=stamp_current (was local_ttl; mtime-only TTL removed for account rotation).
# Presence of WaitForExit alone is not enough — wait must be gated (cold path only).

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Auth stamp prefetch WaitForExit skip (source contracts) ===' -ForegroundColor White

$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw

Assert ($connect -match 'AUTH_STAMP_WAIT_SKIPPED') 'connect.ps1 logs AUTH_STAMP_WAIT_SKIPPED when stamp already current'
Assert ($connect -match 'WaitForExit\(5000\)') 'WaitForExit(5000) still present for cold prefetch path'
Assert ($connect -match 'AUTH_STAMP_WAIT_SKIPPED reason=stamp_current') 'skip log uses reason=stamp_current'

# Harvest block before Syncing Cursor auth.
$harvest = [regex]::Match(
    $connect,
    '(?ms)# Harvest the background stamp fetch.*?Step\s+"Syncing Cursor auth"'
).Value
if ($harvest.Length -lt 80) {
    $harvest = [regex]::Match(
        $connect,
        '(?ms)BgAuthStampProc.*?WaitForExit\(5000\).*?Step\s+"Syncing Cursor auth"'
    ).Value
}
Assert ($harvest.Length -gt 80) 'extracted auth-stamp harvest block before Syncing Cursor auth'
Assert ($harvest -match 'WaitForExit\(5000\)') 'harvest block contains WaitForExit(5000)'

# Gate must live in the harvest window (not a whole-file false positive on later "else").
$hasSkipMarker = [bool]($harvest -match 'AUTH_STAMP_WAIT_SKIPPED')
$hasLocalGate = [bool](
    ($harvest -match 'stampAlreadyCurrent') -or
    ($harvest -match 'local_ttl') -or
    ($harvest -match 'Test-CursorAuthStampCurrent')
)
$hasElseWait = [bool]($harvest -match '(?s)AUTH_STAMP_WAIT_SKIPPED.*?else[\s\S]{0,200}WaitForExit\(5000\)|(?s)if\s*\([^)]*stampAlreadyCurrent[^)]*\)[\s\S]{0,400}else[\s\S]{0,200}WaitForExit\(5000\)')
$gated = $hasSkipMarker -and ($hasLocalGate -or $hasElseWait)
Assert $gated 'WaitForExit(5000) is conditional (stampAlreadyCurrent / local_ttl / AUTH_STAMP_WAIT_SKIPPED in harvest)'

# Today's bug shape: WaitForExit immediately inside BgAuthStampProc try with no skip branch.
$unconditionalBare = [bool]($harvest -match '(?s)if\s*\(\s*\$script:BgAuthStampProc\s*\)\s*\{\s*try\s*\{\s*\$script:BgAuthStampProc\.WaitForExit\(5000\)')
Assert (-not $unconditionalBare) 'harvest must not bare-WaitForExit immediately inside BgAuthStampProc try (unconditional)'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
