#Requires -Version 5.1
# RED contracts: honest MountOk + $script:EditorOpened + SESSION_OPEN / SCORECARD.
# Plan: docs/superpowers/plans/2026-07-25-connect-speed-stability-logging.md Task 5
# Asserts product source via Get-ClientFile — no product edits in this slice.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== EditorOpened script-scope + honest MountOk (Task 5) ===' -ForegroundColor White

$cp = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$ui = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw

# --- 1) $script:EditorOpened assigned true on open + cleared false ---
Assert ($cp -match '\$script:EditorOpened\s*=\s*\$true') `
    'connect.ps1 must assign $script:EditorOpened = $true on open'
Assert ($cp -match '\$script:EditorOpened\s*=\s*\$false') `
    'connect.ps1 must clear $script:EditorOpened = $false on closed / reset path'

# Local $editorOpened alone is not enough for SCORECARD (script-scope unwired today).
$localOpenOnly = ($cp -match '\$editorOpened\s*=\s*\$true') -and ($cp -notmatch '\$script:EditorOpened\s*=\s*\$true')
Assert (-not $localOpenOnly) `
    'must not rely only on local $editorOpened = $true (script scope required)'

# --- 2) SESSION_OPEN passes live $mountOk (not hardcoded $true) ---
# Single-quoted regex: double-quotes expand $true/$mountOk before -match.
Assert ($cp -match 'Write-SessionDiagnosticReport\s+-Phase\s+''SESSION_OPEN''\s+-MountOk\s+\$mountOk\b') `
    'SESSION_OPEN must pass -MountOk $mountOk (live)'
Assert ($cp -notmatch 'Write-SessionDiagnosticReport\s+-Phase\s+''SESSION_OPEN''\s+-MountOk\s+\$true\b') `
    'SESSION_OPEN must not hardcode -MountOk $true'

# --- 3) Complete-PostTunnelRecovery uses live $mountOk ---
Assert ($cp -match 'Complete-PostTunnelRecovery\s+-MountOk\s+\$mountOk\b') `
    'Complete-PostTunnelRecovery must pass -MountOk $mountOk'
Assert ($cp -notmatch 'Complete-PostTunnelRecovery\s+-MountOk\s+\$true\b') `
    'Complete-PostTunnelRecovery must not hardcode -MountOk $true'

# $mountOk must be derived from mount result (present today; guard against delete)
Assert ($cp -match '\$mountOk\s*=\s*\$mountResult\.Ok') `
    '$mountOk is derived from $mountResult.Ok'

# --- 4) SCORECARD prefers $script:EditorOpened (Scope-1 secondary only) ---
$sc = [regex]::Match($ui, '(?ms)function\s+Write-ConnectScorecard\s*\{.*?^\}').Value
Assert ($sc.Length -gt 80) 'Write-ConnectScorecard function extracted from connect-ui.ps1'
Assert ($sc -match '\$script:EditorOpened') `
    'Write-ConnectScorecard references $script:EditorOpened'

# Sticky EditorSeenOpen must not be equal-primary OR for SCORECARD editor= (false-green)
Assert ($sc -notmatch '\$script:EditorOpened\s*-or\s*\$script:EditorSeenOpen') `
    'SCORECARD must not OR $script:EditorSeenOpen as equal-primary editor signal'

# Prefer script scope; Scope-1 editorOpened only as secondary fallback (plan Task 5)
$readsScriptFirst = [bool]($sc -match '\$null\s*-ne\s*\$script:EditorOpened')
$scope1Secondary = [bool]($sc -match 'Get-Variable\s+-Name\s+editorOpened\s+-Scope\s+1')
Assert ($readsScriptFirst) `
    'SCORECARD prefers $script:EditorOpened via null-check (not sticky OR alone)'
Assert ($scope1Secondary) `
    'SCORECARD keeps Scope-1 editorOpened as secondary fallback only'

if ($readsScriptFirst -and $scope1Secondary) {
    $scriptIdx = $sc.IndexOf('$script:EditorOpened')
    $scopeIdx = $sc.IndexOf('Get-Variable -Name editorOpened -Scope 1')
    Assert ($scriptIdx -ge 0 -and $scopeIdx -gt $scriptIdx) `
        'SCORECARD reads $script:EditorOpened before Scope-1 fallback'
}

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
