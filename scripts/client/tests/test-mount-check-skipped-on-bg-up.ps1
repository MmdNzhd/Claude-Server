#Requires -Version 5.1
# RED contracts: BG mount "up" path must skip sync mount health check.
# Plan: docs/superpowers/plans/2026-07-25-connect-speed-stability-logging.md Task 1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Mount check skipped on BG up ===' -ForegroundColor White

$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw

# --- Mandatory: BG up path logs skip marker ---
Assert ($connect -match 'MOUNT_CHECK_SKIPPED reason=bg_up') `
    'BG up path must log MOUNT_CHECK_SKIPPED reason=bg_up'

# Extract cold-BG else branch (Mounting files -> Start-MountProjectBackground -> mountResult)
$bgBranch = [regex]::Match(
    $connect,
    '(?ms)# User request \(2026-07-24\): don''t block.*?Start-MountProjectBackground.*?\$mountResult\s*=\s*\[pscustomobject\]@\{[^}]+\}'
).Value
if ($bgBranch.Length -lt 80) {
    $bgBranch = [regex]::Match(
        $connect,
        '(?ms)\} else \{\s*# User request.*?Start-MountProjectBackground.*?\$mountResult\s*=\s*\[pscustomobject\]@\{[^}]+\}'
    ).Value
}
if ($bgBranch.Length -lt 80) {
    $bgBranch = [regex]::Match(
        $connect,
        '(?ms)Step\s+"Mounting files".*?Start-MountProjectBackground.*?\$mountResult\s*=\s*\[pscustomobject\]@\{[^}]+\}'
    ).Value
}
Assert ($bgBranch.Length -gt 80) 'Extracted BG else-branch that kicks Start-MountProjectBackground'

# Structural skip: BG kick branch itself must not call recover/check
$bgCallsRecoverOrCheck = ($bgBranch -match 'Invoke-RecoverIfNeeded') -or ($bgBranch -match 'Test-ProjectMountHealthy')
Assert (-not $bgCallsRecoverOrCheck) `
    'BG kick branch body must not call Invoke-RecoverIfNeeded / Test-ProjectMountHealthy'

# Skip log must sit on the BG kick path (not merely somewhere else in the file)
Assert ($bgBranch -match 'MOUNT_CHECK_SKIPPED reason=bg_up') `
    'MOUNT_CHECK_SKIPPED reason=bg_up must appear inside the BG kick branch'

# --- Structural: recover call site must be inside GIT_MODE=off / $gitModeOff guard ---
# A regression that puts Invoke-RecoverIfNeeded back on the shared hide/server cold path must FAIL.
Assert ($connect -match '(?ms)\$gitModeOff\s*=\s*\(\(Get-GitMode\)\s*-eq\s*''off''\)') `
    '$gitModeOff is derived from Get-GitMode -eq ''off'''
# Recover stays under gitModeOff; optional session_mount_ok TTL may precede the call.
$gatedRecover = [regex]::Match(
    $connect,
    '(?ms)if\s*\(\s*\$gitModeOff\s*\)\s*\{.*?\$recoverCheckOk\s*=\s*Invoke-RecoverIfNeeded'
)
Assert ($gatedRecover.Success) `
    'Invoke-RecoverIfNeeded call site must be structurally inside if ($gitModeOff) { ... }'

# Every recoverCheckOk = Invoke-RecoverIfNeeded assignment must sit under that guard
# (no ungated shared-path recover before BG kick).
$recoverAssigns = [regex]::Matches($connect, '(?m)^\s*\$recoverCheckOk\s*=\s*Invoke-RecoverIfNeeded\b')
Assert ($recoverAssigns.Count -ge 1) 'at least one $recoverCheckOk = Invoke-RecoverIfNeeded call site'
foreach ($m in $recoverAssigns) {
    $lookbackLen = [Math]::Min(1200, $m.Index)
    $before = $connect.Substring($m.Index - $lookbackLen, $lookbackLen)
    Assert ($before -match 'if\s*\(\s*\$gitModeOff\s*\)\s*\{') `
        'each $recoverCheckOk = Invoke-RecoverIfNeeded must be preceded by if ($gitModeOff) { in nearby scope'
}

# --- BG result honesty: BOTH Ok=$false AND Pending=$true (plan preferred) ---
$bgResultLine = [regex]::Match(
    $bgBranch,
    '(?ms)\$mountResult\s*=\s*\[pscustomobject\]@\{[^}]+\}'
).Value
if ($bgResultLine.Length -lt 20) {
    $bgResultLine = [regex]::Match(
        $connect,
        '(?ms)Start-MountProjectBackground.*?\$mountResult\s*=\s*\[pscustomobject\]@\{[^}]+\}'
    ).Value
}
Assert ($bgResultLine.Length -gt 20) 'BG path assigns $mountResult pscustomobject'

$okFalse = $bgResultLine -match 'Ok\s*=\s*\$false'
$pendingTrue = $bgResultLine -match 'Pending\s*=\s*\$true'
Assert ($okFalse -and $pendingTrue) `
    'BG mountResult must set Ok=$false AND Pending=$true (not false-green MountOk)'

# Guard: skipRemount healthy path is allowed to keep recover — do not forbid recover globally
$skipRemountBranch = [regex]::Match(
    $connect,
    '(?ms)if\s*\(\s*\$skipRemount\s*\).*?\$mountResult\s*=\s*\[pscustomobject\]@\{[^}]+\}'
).Value
Assert ($skipRemountBranch.Length -gt 40 -or ($connect -match '\$skipRemount')) `
    'skipRemount path still present (may call Invoke-RecoverIfNeeded — allowed)'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
