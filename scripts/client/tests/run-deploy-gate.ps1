#Requires -Version 5.1
# run-deploy-gate.ps1 - non-live client tests for deploy / CI gate
$ErrorActionPreference = 'Stop'
$TestsDir = $PSScriptRoot
$RunAllPath = Join-Path $TestsDir 'run-all.ps1'

# Scripts that must run when present (even if absent from run-all.ps1).
$CriticalScripts = @(
    'test-exe-spaced-path-launch.ps1'
    'test-exe-promote-launch-dir-hard.ps1'
    'test-client-update-policy-optional.ps1'
    'test-empty-menu-manual-update.ps1'
    'test-connect-update-hardening.ps1'
    'test-exe-atomic-swap.ps1'
    'test-update-no-defer-prompt.ps1'
    'test-update-kill-self-contract.ps1'
    'test-exe-promote-dirs-contract.ps1'
    'test-mount-skew-align-hard-batch.ps1'
    'test-orphan-reclaim-hard-batch.ps1'
    'test-keep-tunnel-marker-hard-batch.ps1'
    'test-cleanup-user-hard-batch.ps1'
    'test-editor-launch-strategies.ps1'
    'test-harder-live-mount-skew-gate.ps1'  # L7 static skew gate (safe non-live)
    'test-verdir-content-integrity.ps1'
    'test-setup-launch-exe-integrity.ps1'
    'test-no-stale-shadow-in-ship.ps1'
)

# windows-mcp LIVE storm/chaos/brutal suites take many minutes and stall
# publish\deploy.bat / deploy-scripts-only. They are commented out in run-all.ps1
# too; run the .ps1 files directly when changing windows-mcp-laptop.ps1.
# Static windows-mcp-* batch/ports suites stay in the gate (fast).
$SkipDeployScripts = @(
    'test-harder-live-windows-mcp-storm.ps1'
    'test-hardest-live-windows-mcp-chaos.ps1'
    'test-brutal-live-windows-mcp-abuse.ps1'
)

function Get-SuitesFromRunAll {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "run-all.ps1 not found: $Path"
    }

    $content = Get-Content -LiteralPath $Path -Raw
    $pattern = "@\{ Name = '([^']+)'\s*;\s*Script = '([^']+)'\s*\}"
    $matches = [regex]::Matches($content, $pattern)

    $suites = [System.Collections.Generic.List[hashtable]]::new()
    $seen = @{}

    foreach ($m in $matches) {
        $name = $m.Groups[1].Value
        $script = $m.Groups[2].Value
        if ($script -match '-live\.ps1$') { continue }
        if ($SkipDeployScripts -contains $script) { continue }
        if ($seen.ContainsKey($script)) { continue }
        $seen[$script] = $true
        $suites.Add(@{ Name = $name; Script = $script })
    }

    foreach ($script in $CriticalScripts) {
        $scriptPath = Join-Path $TestsDir $script
        if (-not (Test-Path -LiteralPath $scriptPath)) { continue }
        if ($seen.ContainsKey($script)) { continue }
        $seen[$script] = $true
        $name = ([System.IO.Path]::GetFileNameWithoutExtension($script) -replace '^test-', '')
        $suites.Add(@{ Name = $name; Script = $script })
    }

    return ,@($suites.ToArray())
}

$suites = Get-SuitesFromRunAll -Path $RunAllPath
$fail = 0
$passed = 0
$failedNames = [System.Collections.Generic.List[string]]::new()

Write-Host ''
Write-Host "=== Deploy gate (non-live suites, $($suites.Count) total) ===" -ForegroundColor White
Write-Host "Source: run-all.ps1 minus *-live.ps1, plus critical deploy scripts" -ForegroundColor DarkGray
Write-Host "Skipped (slow): windows-mcp live storm/chaos/brutal - run .ps1 directly when needed" -ForegroundColor DarkGray
Write-Host ''

foreach ($suite in $suites) {
    $path = Join-Path $TestsDir $suite.Script
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "--- $($suite.Name) ---" -ForegroundColor Cyan
        Write-Host "  SKIP missing: $($suite.Script)" -ForegroundColor DarkYellow
        Write-Host ''
        continue
    }

    Write-Host "--- $($suite.Name) ---" -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $path
    $suiteExit = $LASTEXITCODE
    if ($suiteExit -ne 0) {
        $fail++
        $failedNames.Add($suite.Name) | Out-Null
        Write-Host ("  FAIL ({0} exit={1})" -f $suite.Script, $suiteExit) -ForegroundColor Red
    }
    else {
        $passed++
        Write-Host '  PASS' -ForegroundColor Green
    }
    Write-Host ''
}

Write-Host '=== Deploy gate summary ===' -ForegroundColor White
Write-Host "  Passed: $passed" -ForegroundColor Green
$failColor = if ($fail -eq 0) { 'Green' } else { 'Red' }
Write-Host "  Failed: $fail" -ForegroundColor $failColor
Write-Host '  Skipped live: *-live.ps1 (not run)' -ForegroundColor DarkGray
Write-Host '  Skipped slow MCP: storm / chaos / brutal (not run on deploy gate)' -ForegroundColor DarkGray

if ($fail -gt 0) {
    Write-Host ''
    Write-Host 'Failed suites:' -ForegroundColor Red
    foreach ($n in $failedNames) {
        Write-Host ("  - {0}" -f $n) -ForegroundColor Red
    }
    exit 1
}

Write-Host ''
Write-Host 'Deploy gate passed.' -ForegroundColor Green
exit 0
