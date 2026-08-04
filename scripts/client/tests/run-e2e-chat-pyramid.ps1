#Requires -Version 5.1
# run-e2e-chat-pyramid.ps1
# Orchestrates Phase 1 (Connect signals) + Phase 2 (agent hello).
# TEST ONLY - never edits product connect.ps1 / versions.
#
# Contracts (default):
#   powershell -NoProfile -File scripts\client\tests\run-e2e-chat-pyramid.ps1
# Live shallow (serial):
#   powershell -NoProfile -File scripts\client\tests\run-e2e-chat-pyramid.ps1 -Live -Count 1
# Deep parallel + post-hoc day-log parse (preferred live):
#   powershell -NoProfile -File scripts\client\tests\run-e2e-chat-pyramid.ps1 -Deep -Parallel 3 -AlsoAgentHello
# Strict deep (AGENT_PATH + MOUNT_BG required on every worker):
#   powershell -NoProfile -File scripts\client\tests\run-e2e-chat-pyramid.ps1 -Deep -Strict -Parallel 3 -AlsoAgentHello
# Precise (Strict + WMCP=200 every worker + listen_conf + zero LOG_SYNC NRE):
#   powershell -NoProfile -File scripts\client\tests\run-e2e-chat-pyramid.ps1 -Deep -Precise -Parallel 3 -AlsoAgentHello
param(
    [switch]$Live,
    [switch]$Deep,
    [switch]$Strict,
    [switch]$Precise,
    [int]$Count = 1,
    [int]$Parallel = 3,
    [int]$ProjectSlot = 1,
    [string]$Workspace = '',
    [switch]$AlsoAgentHello,
    [switch]$SkipPhase1,
    [switch]$SkipPhase2
)
$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
Write-Host ''
Write-Host '=== E2E chat pyramid (Rank-1 signals + Rank-2 agent hello) ===' -ForegroundColor White
Write-Host 'Product files untouched. GUI Chat automation is intentionally NOT included.' -ForegroundColor DarkGray
Write-Host ''

$fail = 0
function Run-Phase([string]$Script, [string[]]$ExtraArgs) {
    $path = Join-Path $here $Script
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "MISS  $Script" -ForegroundColor Yellow
        $script:fail++
        return
    }
    Write-Host "--- $Script ---" -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path @ExtraArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAIL  $Script exit=$LASTEXITCODE" -ForegroundColor Red
        $script:fail++
    } else {
        Write-Host "PASS  $Script" -ForegroundColor Green
    }
    Write-Host ''
}

if ($Deep) {
    $a = @('-Parallel', "$Parallel", '-ProjectSlot', "$ProjectSlot")
    if ($Precise) { $a += '-Precise' }
    elseif ($Strict) { $a += '-Strict' }
    if ($AlsoAgentHello) { $a += '-AlsoAgentHello' }
    if ($Workspace) { $a += '-Workspace'; $a += $Workspace }
    Run-Phase 'test-e2e-connect-deep-parallel.ps1' $a
} else {
    if (-not $SkipPhase1) {
        $a = @()
        if ($Live) { $a += '-Live'; $a += '-Count'; $a += "$Count"; $a += '-ProjectSlot'; $a += "$ProjectSlot" }
        Run-Phase 'test-e2e-connect-signal-harness.ps1' $a
    }
    if (-not $SkipPhase2) {
        $a = @()
        if ($Live) { $a += '-Live' }
        if ($Workspace) { $a += '-Workspace'; $a += $Workspace }
        Run-Phase 'test-e2e-agent-hello.ps1' $a
    }
}

if ($fail -eq 0) {
    Write-Host 'E2E PYRAMID: ALL PASS' -ForegroundColor Green
    exit 0
}
Write-Host ("E2E PYRAMID: {0} FAILED" -f $fail) -ForegroundColor Red
exit 1
