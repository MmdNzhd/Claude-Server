# verify-perf-gates.ps1 - strict performance gate check for connect.log
param(
    [Parameter(Mandatory)][string]$LogPath,
    [switch]$AllowSnapshots
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $LogPath)) {
    Write-Error "Log not found: $LogPath"
    exit 1
}

$fail = 0
function Gate($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

$raw = Get-Content -LiteralPath $LogPath -Raw
$lines = @(Get-Content -LiteralPath $LogPath)

$version = if ($raw -match 'session start v([0-9.]+)') { $Matches[1] } else { 'unknown' }
$openingMs = @($lines | ForEach-Object {
    if ($_ -match 'STEP end: Opening Cursor ok ms=(\d+)') { [int]$Matches[1] }
}) | Select-Object -Last 1
$skipLaunch = @($lines | Where-Object { $_ -match 'LAUNCH_SKIP: already on correct folder' }).Count
$snapshots = @($lines | Where-Object { $_ -match 'SNAPSHOT\[' }).Count
$launchResultAfterOk = 0
$launchWasteAfterPoll = 0
$verboseBeforeSkip = 0
$falseDoubleLaunch = 0
$seenOk = $false
$inOpening = $false
$pollSuccess = $false
$launchBeginOnFolder = $false
$seenLaunchOkInOpening = $false
foreach ($ln in $lines) {
    if ($ln -match 'STEP begin: Opening Cursor') {
        $inOpening = $true
        $pollSuccess = $false
        $launchBeginOnFolder = $false
        $seenLaunchOkInOpening = $false
        continue
    }
    if ($ln -match 'STEP end: Opening Cursor') {
        $inOpening = $false
        $pollSuccess = $false
        $launchBeginOnFolder = $false
        $seenLaunchOkInOpening = $false
        continue
    }

    if ($inOpening) {
        if ($ln -match 'LAUNCH_BEGIN:.*on_folder=True') { $launchBeginOnFolder = $true }
        if ($launchBeginOnFolder -and $ln -match 'STATE\[BEGIN\]|SNAPSHOT\[BEGIN\]') { $verboseBeforeSkip++ }
        if ($ln -match 'LAUNCH_SKIP:') { $launchBeginOnFolder = $false }
        if ($ln -match 'LAUNCH_POLL:.*on_folder=True') { $pollSuccess = $true; continue }
        if ($pollSuccess -and $ln -notmatch 'LAUNCH_OK:' -and
            $ln -match 'LAUNCH_ATTEMPT_RESULT:|SNAPSHOT\[RESULT|STATE\[RESULT_') {
            $launchWasteAfterPoll++
        }
        if ($ln -match 'LAUNCH_OK:') { $pollSuccess = $false; $seenLaunchOkInOpening = $true }
        # WS3: a "not on target folder" relaunch after LAUNCH_OK within the same Opening step
        # is a false double-launch - the trust-path fix should suppress this entirely.
        if ($seenLaunchOkInOpening -and $ln -match 'SESSION: cursor not on target folder') {
            $falseDoubleLaunch++
        }
    }

    if ($ln -match 'LAUNCH_OK:') { $seenOk = $true; continue }
    if ($seenOk -and $ln -match 'LAUNCH_ATTEMPT_RESULT:') { $launchResultAfterOk++; $seenOk = $false }
}

$sessionSummary = @($lines | Where-Object { $_ -match 'PERF\[session_open_summary\]' }) | Select-Object -Last 1
$lightDiag = @($lines | Where-Object { $_ -match 'skipped=light_session_open' }).Count
$perfMarks = @($lines | Where-Object { $_ -match 'PERF\[' }).Count
$cimQueries = @($lines | Where-Object { $_ -match 'PERF\[cim_query\]' }).Count
$cimHits = @($lines | Where-Object { $_ -match 'PERF\[cim_query\].*cache_hit=1' }).Count
$launchTotal = @($lines | ForEach-Object {
    if ($_ -match 'PERF\[launch_total\] ms=(\d+)') { [int]$Matches[1] }
}) | Select-Object -Last 1

Write-Host ''
Write-Host '=== Perf gate verification ===' -ForegroundColor Cyan
Write-Host "Log: $LogPath"
Write-Host "Version: $version"
Write-Host ''

Gate ($version -match '^20260714\.[45]$') "client version is post-fix ($version)"
Gate ($perfMarks -gt 0) "PERF marks present ($perfMarks lines)"
Gate ($null -ne $openingMs) "Opening Cursor step recorded (ms=$openingMs)"

if ($skipLaunch -gt 0) {
    Gate ($openingMs -lt 1500) "skip path Opening Cursor < 1500 ms (got $openingMs)"
} else {
    Gate ($openingMs -lt 8000) "cold path Opening Cursor < 8000 ms (got $openingMs)"
}

if ($AllowSnapshots) {
    Gate $true 'SNAPSHOT check skipped (-AllowSnapshots)'
} else {
    Gate ($snapshots -eq 0) "SNAPSHOT count = 0 (got $snapshots)"
}

Gate ($launchResultAfterOk -eq 0) "no LAUNCH_ATTEMPT_RESULT after LAUNCH_OK (F2 tail, got $launchResultAfterOk)"
Gate ($launchWasteAfterPoll -eq 0) "no post-poll waste before LAUNCH_OK (F2, got $launchWasteAfterPoll)"
Gate ($verboseBeforeSkip -eq 0) "no verbose STATE/SNAPSHOT before skip when on_folder (F1, got $verboseBeforeSkip)"
Gate ($falseDoubleLaunch -eq 0) "no false double-launch relaunch after LAUNCH_OK within Opening step (WS3, got $falseDoubleLaunch)"
if ($null -ne $launchTotal) {
    Gate ($launchTotal -lt 8000) "launch_total < 8000 ms (got $launchTotal)"
}
if ($sessionSummary) {
    Gate $true 'session_open_summary present'
    if ($sessionSummary -match 'diag_ms=(\d+)') {
        $diagMs = [int]$Matches[1]
        Gate ($diagMs -lt 500) "diag_ms < 500 (got $diagMs)"
    }
}
if ($lightDiag -gt 0) {
    Gate $true 'light SESSION_OPEN diagnostic used (F7)'
}
if ($cimQueries -gt 0) {
    Write-Host "  INFO  CIM queries=$cimQueries cache_hits=$cimHits" -ForegroundColor DarkGray
    Gate ($cimQueries -le 20) "cim_query count reasonable <= 20 (got $cimQueries)"
}

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'All perf gates passed.' -ForegroundColor Green
    exit 0
}
Write-Host "$fail gate(s) failed." -ForegroundColor Red
exit 1
