#Requires -Version 5.1
# RED contracts: Opening Cursor / launch-not-ok must clear sticky editor-open.
# Plan: docs/superpowers/plans/2026-07-25-connect-speed-stability-logging.md Task 6
# Asserts product source via Get-ClientFile — no product edits in this slice.
# Expected RED today: missing EDITOR_SEEN_CLEAR reason=opening_step_fail on fail path.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Opening fail clears EditorSeenOpen (Task 6) ===' -ForegroundColor White

$cp = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw

# --- 1) Mandatory clear marker on Opening / launch fail ---
Assert ($cp -match 'EDITOR_SEEN_CLEAR reason=opening_step_fail') `
    'fail path must log EDITOR_SEEN_CLEAR reason=opening_step_fail'

# --- 2) Launch-not-ok branch must clear script sticky flags when window not proven ---
# Prefer structural proximity to StepFail after Launch-RemoteEditor.
$launchFailNear = [regex]::Match(
    $cp,
    '(?ms)if\s*\(\s*-not\s*\$launchOk\s*\)\s*\{.*?StepFail.*?\}'
).Value
if ($launchFailNear.Length -lt 40) {
    $launchFailNear = [regex]::Match(
        $cp,
        '(?ms)\$launchOk\s*=\s*\[bool\]\(Launch-RemoteEditor.*?if\s*\(\s*-not\s*\$launchOk\s*\).*?StepFail[^\n]+'
    ).Value
}
Assert ($launchFailNear.Length -gt 20) `
    'found Launch-RemoteEditor / -not $launchOk StepFail region'

# After GREEN: clear sticky when window not proven open (plan snippet)
$hasOpeningClear = $cp -match 'EDITOR_SEEN_CLEAR reason=opening_step_fail'
$clearsSeen = $cp -match '(?ms)EDITOR_SEEN_CLEAR reason=opening_step_fail.*?\$script:EditorSeenOpen\s*=\s*\$false|\$script:EditorSeenOpen\s*=\s*\$false.*?EDITOR_SEEN_CLEAR reason=opening_step_fail'
$clearsOpened = $cp -match '(?ms)EDITOR_SEEN_CLEAR reason=opening_step_fail.*?\$script:EditorOpened\s*=\s*\$false|\$script:EditorOpened\s*=\s*\$false.*?EDITOR_SEEN_CLEAR reason=opening_step_fail'
# Also accept plan order: clear flags then log, or log then clear, in same -not $launchOk block
$failClearBlock = [regex]::Match(
    $cp,
    '(?ms)if\s*\(\s*-not\s*\$launchOk\s*\)\s*\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*EDITOR_SEEN_CLEAR reason=opening_step_fail(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}'
).Value
if ($failClearBlock.Length -lt 30) {
    # Fallback: windowOpenInit-gated clear near opening_step_fail (plan shape)
    $failClearBlock = [regex]::Match(
        $cp,
        '(?ms)if\s*\(\s*-not\s*\$launchOk\s*\)\s*\{.*?if\s*\(\s*-not\s*\$windowOpenInit\s*\)\s*\{.*?EDITOR_SEEN_CLEAR reason=opening_step_fail.*?\}'
    ).Value
}
Assert ($hasOpeningClear) `
    'EDITOR_SEEN_CLEAR reason=opening_step_fail present (sticky clear on Opening fail)'
Assert (($failClearBlock.Length -gt 30) -or ($clearsSeen -and $clearsOpened)) `
    'on launch not ok + window not proven: clear $script:EditorSeenOpen and $script:EditorOpened with opening_step_fail'

if ($failClearBlock.Length -gt 30) {
    Assert ($failClearBlock -match '\$script:EditorSeenOpen\s*=\s*\$false') `
        'opening_step_fail block clears $script:EditorSeenOpen = $false'
    Assert ($failClearBlock -match '\$script:EditorOpened\s*=\s*\$false') `
        'opening_step_fail block clears $script:EditorOpened = $false'
}

# --- 3) Must not rely only on editor_closed phase=session_open for Opening fail ---
# That path clears after the fact; Opening StepFail needs its own reason.
Assert ($cp -match 'EDITOR_SEEN_CLEAR reason=opening_step_fail') `
    'Opening fail clear must use reason=opening_step_fail (not only editor_closed phase=session_open)'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
