#Requires -Version 5.1
# RED contracts: Server setup MOUNT_HASH must seed ClaudeMountSyncVerifiedHash
# so Prepare-ServerSessionParallel can skip the sha256sum SshX round trip.
# Plan: docs/superpowers/plans/2026-07-25-connect-speed-stability-logging.md Task 3

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$failed = 0; $passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failed++ }
}

Write-Host ''
Write-Host '=== Mount hash seed from Server setup MOUNT_HASH ===' -ForegroundColor White

$c = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$g = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw

# --- connect.ps1: Initialize-ServerSession must seed verified hash from MOUNT_HASH ---
Assert ($c -match 'function\s+Initialize-ServerSession\b') 'Initialize-ServerSession present in connect.ps1'
Assert ($c -match 'MOUNT_HASH') 'Server setup batch emits / parses MOUNT_HASH'
Assert ($c -match '\$script:ClaudeMountSyncVerifiedHash\s*=') `
    'setup must seed $script:ClaudeMountSyncVerifiedHash (from MOUNT_HASH parse)'

# Seed must live inside Initialize-ServerSession (not a stray assignment elsewhere).
$initFn = ''
if (Get-Command Get-FunctionSource -ErrorAction SilentlyContinue) {
    $initFn = Get-FunctionSource -Content $c -Name 'Initialize-ServerSession'
}
if (-not $initFn) {
    $initFn = [regex]::Match(
        $c,
        '(?ms)function\s+Initialize-ServerSession\b.*?^function\s+\w+'
    ).Value
}
Assert ($initFn.Length -gt 200) 'extracted Initialize-ServerSession body'
Assert ($initFn -match '\$script:ClaudeMountSyncVerifiedHash\s*=') `
    'Initialize-ServerSession assigns $script:ClaudeMountSyncVerifiedHash'
Assert ($initFn -match 'MOUNT_HASH') `
    'Initialize-ServerSession seed path is tied to MOUNT_HASH parse'

# --- git-mode.ps1: Prepare must honor seeded hash (skip sha256 SshX) ---
Assert ($g -match 'function\s+Prepare-ServerSessionParallel\b') 'Prepare-ServerSessionParallel present'
Assert ($g -match 'ClaudeMountSyncVerifiedHash') 'Prepare must honor seeded hash'

$prepFn = ''
if (Get-Command Get-FunctionSource -ErrorAction SilentlyContinue) {
    $prepFn = Get-FunctionSource -Content $g -Name 'Prepare-ServerSessionParallel'
}
if (-not $prepFn) {
    $prepFn = [regex]::Match(
        $g,
        '(?ms)function\s+Prepare-ServerSessionParallel\b.*?^function\s+\w+'
    ).Value
}
Assert ($prepFn.Length -gt 200) 'extracted Prepare-ServerSessionParallel body'
Assert ($prepFn -match '\$script:ClaudeMountSyncVerifiedHash') `
    'Prepare-ServerSessionParallel references ClaudeMountSyncVerifiedHash'
Assert ($prepFn -match 'skip_verified|ClaudeMountSyncVerifiedHash\s*-eq') `
    'Prepare skips sha256 SshX when ClaudeMountSyncVerifiedHash already matches localHash'

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
exit 0
