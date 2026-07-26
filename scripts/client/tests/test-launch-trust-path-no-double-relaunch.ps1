#Requires -Version 5.1
# RED/GREEN contracts: trust path after successful launch must skip re-probe
# (avoids double relaunch). Plan Task 6.
# Asserts product source via Get-ClientFile — no product edits in this slice.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Launch trust path (no double relaunch) — Task 6 ===' -ForegroundColor White

$cp = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw

# --- 1) Trust marker must remain ---
Assert ($cp -match 'SESSION: trusting launch result') `
    "trust path still has 'SESSION: trusting launch result'"

# --- 2) Trust gated on didLaunch + launchOk ---
Assert ($cp -match '(?ms)if\s*\(\s*\$didLaunch\s*-and\s*\$launchOk\s*\)\s*\{[^}]*SESSION:\s*trusting launch result') `
    'trust log sits inside if ($didLaunch -and $launchOk)'

# --- 3) Skip re-probe / skip relaunch check (do NOT remove) ---
Assert ($cp -match 'skip relaunch check') `
    'trust path keeps skip-reprobe (skip relaunch check)'
Assert ($cp -match '(?ms)didLaunch\+launchOk\)\s*-\s*skip relaunch check') `
    'trust log documents didLaunch+launchOk skip relaunch check'

# --- 4) On trust: set onFolderNow=$true without immediate Test-RemoteEditorOnCorrectFolder ---
$trustBlock = [regex]::Match(
    $cp,
    '(?ms)if\s*\(\s*\$didLaunch\s*-and\s*\$launchOk\s*\)\s*\{.*?Write-ConnectLog\s+''SESSION: trusting launch result[^'']*''.*?\}'
).Value
Assert ($trustBlock.Length -gt 40) 'extracted didLaunch+launchOk trust block'
Assert ($trustBlock -match '\$onFolderNow\s*=\s*\$true') `
    'trust block sets $onFolderNow = $true'
Assert ($trustBlock -notmatch 'Test-RemoteEditorOnCorrectFolder') `
    'trust block must not re-probe with Test-RemoteEditorOnCorrectFolder (double-launch risk)'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
