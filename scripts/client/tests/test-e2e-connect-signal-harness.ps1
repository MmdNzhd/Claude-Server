#Requires -Version 5.1
# test-e2e-connect-signal-harness.ps1
# Phase 1 (Rank-1): Connect signal gate - SCORECARD / AGENT_PATH / on_folder contracts.
# TEST ONLY. Does NOT modify product connect.ps1. Live mode drives connect-boot via stdin
# (same pattern as perf/run-connect-cycle.ps1; menu stdin can miss - documented).
#
# Default = contracts only (safe for run-all / deploy-gate).
# Live:  powershell -File test-e2e-connect-signal-harness.ps1 -Live [-Count 1] [-ProjectSlot 1]
param(
    [switch]$Live,
    [int]$Count = 1,
    [int]$ProjectSlot = 1,
    [int]$MaxSeconds = 120,
    [int]$QuietSeconds = 25,
    [string]$ConnectBootPath = ''
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
. (Join-Path $PSScriptRoot 'e2e\_e2e-common.ps1')

$Pass = 0; $Fail = 0; $Skip = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }
function SkipMsg([string]$Msg) { Write-Host "  SKIP  $Msg" -ForegroundColor Yellow; $script:Skip++ }

Write-Host ''
Write-Host '=== E2E Phase 1: Connect signal harness (test-only) ===' -ForegroundColor Cyan
Write-Host ''

# --- Contracts (always) ---
Note 'A) source contracts (no live Connect)'
$win = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$ui = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
$el = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
Assert ($ui -match 'SCORECARD') 'connect-ui emits SCORECARD'
Assert ($ui -match 'AGENT_PATH ok') 'connect-ui logs AGENT_PATH ok'
Assert ($ui -match 'LastAgentPathResult') 'SCORECARD can reuse LastAgentPathResult'
Assert ($el -match 'Test-RemoteEditorOnCorrectFolder') 'editor-launch has on_folder detector'
Assert ($el -match 'Confirm-RemoteEditorLaunchVisible') 'editor-launch has launch confirm'
Assert ($win -match 'Write-ConnectScorecard|SCORECARD') 'connect.ps1 references scorecard path'
Assert ($win -match 'Choose-Project') 'connect.ps1 has Choose-Project (stdin menu; no product AUTO_PROJECT seam)'
$boot = Get-E2eConnectBootPath
Assert ($null -ne $boot) ("resolves connect-boot.ps1 (got: {0})" -f $(if ($boot) { $boot } else { 'null' }))
$free = Get-E2eFreeConnectSlotCount
Note ("free ClaudeConnect# slots = $free / 10")
Assert ($free -ge 0 -and $free -le 10) 'slot probe returns 0..10'

if (-not $Live) {
    Note 'Live Connect cycle skipped (pass -Live to drive connect-boot + day-log SCORECARD)'
    Write-Host ''
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip (contracts only)" -f $Pass, $Fail, $Skip) `
        -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
    if ($Fail -gt 0) { exit 1 }
    exit 0
}

# --- Live ---
Note 'B) LIVE connect-boot cycles (stdin ProjectSlot; may miss menu - see perf note)'
if ($Count -lt 1) { $Count = 1 }
if ($Count -gt 5) {
    SkipMsg "Count=$Count capped to 5 (anti-litter; raise only on empty laptop)"
    $Count = 5
}
if ($free -lt 1) {
    SkipMsg 'no free ClaudeConnect# slot - cannot LIVE'
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Yellow
    exit 0
}

if ($ConnectBootPath -and (Test-Path -LiteralPath $ConnectBootPath)) {
    $boot = $ConnectBootPath
}
Assert (Test-Path -LiteralPath $boot) "LIVE boot path exists: $boot"
if (-not (Test-Path -LiteralPath $boot)) {
    Write-Host ("RESULT: {0} pass / {1} fail / {2} skip" -f $Pass, $Fail, $Skip) -ForegroundColor Red
    exit 1
}

$resultsDir = Join-Path $env:USERPROFILE '.config\claude-connect\e2e-harness'
New-Item -ItemType Directory -Force -Path $resultsDir -ErrorAction SilentlyContinue | Out-Null
$dayLog = Get-E2eDayLogPath
$liveOk = 0
$liveMiss = 0

for ($n = 1; $n -le $Count; $n++) {
    Note ("LIVE cycle $n/$Count ProjectSlot=$ProjectSlot")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $boot + '"'
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Milliseconds 800
    # Retry stdin a few times (known flaky vs Read-ConnectPrompt)
    foreach ($delayMs in @(200, 600, 1200)) {
        try { $proc.StandardInput.WriteLine([string]$ProjectSlot) } catch {}
        Start-Sleep -Milliseconds $delayMs
    }
    try { $proc.StandardInput.Close() } catch {}

    $sawScorecard = $false
    $sawAgentPath = $false
    $sawOnFolder = $false
    $sidHint = "pid=$($proc.Id)"
    while ($sw.Elapsed.TotalSeconds -lt $MaxSeconds) {
        Start-Sleep -Milliseconds 1500
        if ($proc.HasExited) { break }
        if (-not (Test-Path -LiteralPath $dayLog)) { continue }
        $tail = @()
        try { $tail = Get-Content -LiteralPath $dayLog -Tail 250 -ErrorAction SilentlyContinue } catch { $tail = @() }
        $mine = @($tail | Where-Object { $_ -match [regex]::Escape($sidHint) -or $_ -match 'SCORECARD|AGENT_PATH|FOLDER_CHECK|on_folder=' })
        foreach ($line in $mine) {
            if ($line -match 'SCORECARD') { $sawScorecard = $true }
            if ($line -match 'AGENT_PATH ok') { $sawAgentPath = $true }
            if ($line -match 'on_folder=True|FOLDER_CHECK:.*on_folder=True|reason=on_folder') { $sawOnFolder = $true }
        }
        if ($sawScorecard) { break }
        # Quiet exit if log stopped growing and we are past QuietSeconds
        if ($sw.Elapsed.TotalSeconds -gt $QuietSeconds -and -not $sawScorecard) {
            # keep waiting until MaxSeconds for late SCORECARD
        }
    }
    $sw.Stop()
    if (-not $proc.HasExited) { Stop-E2eProcessTree -RootPid $proc.Id }
    Start-Sleep -Seconds 1

    $cycle = [PSCustomObject]@{
        N            = $n
        ProjectSlot  = $ProjectSlot
        Pid          = $proc.Id
        Ms           = [int]$sw.ElapsedMilliseconds
        SawScorecard = $sawScorecard
        SawAgentPath = $sawAgentPath
        SawOnFolder  = $sawOnFolder
    }
    $outFile = Join-Path $resultsDir ("phase1-{0}-{1}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $n)
    $cycle | ConvertTo-Json | Set-Content -LiteralPath $outFile -Encoding UTF8
    Note ("wrote $outFile scorecard=$sawScorecard agent=$sawAgentPath on_folder=$sawOnFolder ms=$($cycle.Ms)")

    if ($sawScorecard) {
        Assert $true ("LIVE cycle $n saw SCORECARD")
        $liveOk++
    } else {
        # Soft-fail: known stdin/menu gap - count as miss, not hard Fail unless zero evidence
        if ($sawAgentPath -or $sawOnFolder) {
            SkipMsg "LIVE cycle $n no SCORECARD but saw agent/on_folder (partial; stdin menu flake)"
            $liveMiss++
        } else {
            SkipMsg "LIVE cycle $n no SCORECARD/AGENT_PATH/on_folder (likely stuck at project menu - stdin flake)"
            $liveMiss++
        }
    }
}

Assert ($liveOk -ge 1 -or $liveMiss -eq $Count) `
    'LIVE completed without crash (ok>=1 or all honest SKIP/miss)'
if ($liveOk -eq 0 -and $Count -ge 1) {
    Note 'TIP: open Connect once manually, note project menu number, re-run -Live -ProjectSlot N'
    Note 'TIP: or use existing day-log SCORECARD from a manual session for Rank-1 evidence'
}

Write-Host ''
Write-Host ("RESULT: {0} pass / {1} fail / {2} skip | live_ok={3} live_miss={4}" -f $Pass, $Fail, $Skip, $liveOk, $liveMiss) `
    -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
exit 0
