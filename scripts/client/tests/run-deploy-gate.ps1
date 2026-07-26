#Requires -Version 5.1
# run-deploy-gate.ps1 - non-live client tests for deploy / CI gate
$ErrorActionPreference = 'Stop'
$TestsDir = $PSScriptRoot
$RunAllPath = Join-Path $TestsDir 'run-all.ps1'

# Scripts that must run when present (even if absent from run-all.ps1).
$CriticalScripts = @(
    'test-exe-promote-launch-dir-hard.ps1'
    'test-client-update-policy-optional.ps1'
    'test-empty-menu-manual-update.ps1'
    'test-connect-update-hardening.ps1'
    'test-exe-atomic-swap.ps1'
    'test-update-no-defer-prompt.ps1'
    'test-update-kill-self-contract.ps1'
    'test-exe-promote-dirs-contract.ps1'
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
    if ($LASTEXITCODE -ne 0) {
        $fail++
        $failedNames.Add($suite.Name) | Out-Null
        Write-Host "  FAIL ($($suite.Script) exit=$LASTEXITCODE)" -ForegroundColor Red
    }
    else {
        $passed++
        Write-Host "  PASS" -ForegroundColor Green
    }
    Write-Host ''
}

Write-Host '=== Deploy gate summary ===' -ForegroundColor White
Write-Host "  Passed: $passed" -ForegroundColor Green
Write-Host "  Failed: $fail" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host "  Skipped live: *-live.ps1 (not run)" -ForegroundColor DarkGray

if ($fail -gt 0) {
    Write-Host ''
    Write-Host 'Failed suites:' -ForegroundColor Red
    foreach ($n in $failedNames) {
        Write-Host "  - $n" -ForegroundColor Red
    }
    exit 1
}

Write-Host ''
Write-Host 'Deploy gate passed.' -ForegroundColor Green
exit 0
