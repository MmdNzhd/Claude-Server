#Requires -Version 5.1
# run-harder-battery.ps1 - HARD+++ suite (stricter than the previous hard battery).
$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
$tests = @(
    'test-never-again-ship-gates.ps1',
    'test-smartscreen-docs-contract.ps1',
    'test-exe-launch-slot-gate.ps1',
    'test-exe-spaced-path-launch.ps1',
    'test-exe-preboot-update-live.ps1',
    'test-exe-promote-launch-dir-hard.ps1',
    'test-hard-cmd-flash-fleet-push.ps1',
    'test-connect-update-hardening.ps1',
    'test-hard-connect-ux-20260723.ps1',
    'test-hard-multi-agent-regressions.ps1',
    'test-windows-shadow-canon.ps1',
    'test-update-kill-self-contract.ps1',
    'test-sidecar-front-flap.ps1',
    'test-windows-mcp-ports.ps1',
    'test-setup-debounce-bounded-live.ps1',
    'test-agent-home-launch-gate.ps1',
    'test-harder-adversarial.ps1',
    'test-versioned-layout.ps1',
    'test-versioned-layout-deep-live.ps1',
    # Multi-Connect KEEP / skew HARDER (L1–L7)
    'test-harder-live-keep-reclaim.ps1',
    'test-harder-live-keep-soft-race.ps1',
    'test-harder-live-pin-before-reclaim.ps1',
    'test-harder-live-acquire-keep-split.ps1',
    'test-harder-live-slot-storm-keep.ps1',
    'test-harder-adversarial-keep-mount.ps1',
    'test-harder-live-mount-skew-gate.ps1',
    # E2E pyramid contracts (no -Live)
    'test-e2e-connect-signal-harness.ps1',
    'test-e2e-agent-hello.ps1'
)
Write-Host ''
Write-Host '=== HARD+++ BATTERY ===' -ForegroundColor White
$fail = 0
foreach ($t in $tests) {
    $path = Join-Path $here $t
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "MISS  $t" -ForegroundColor Yellow
        $fail++
        continue
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAIL  $t" -ForegroundColor Red
        $fail++
    } else {
        Write-Host "PASS  $t" -ForegroundColor Green
    }
}
Write-Host ''
if ($fail -eq 0) {
    Write-Host 'HARD+++ BATTERY: ALL PASS' -ForegroundColor Green
    exit 0
}
Write-Host ("HARD+++ BATTERY: {0} FAILED" -f $fail) -ForegroundColor Red
exit 1
