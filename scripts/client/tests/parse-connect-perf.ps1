# parse-connect-perf.ps1 - summarize connect.log STEP + PERF timings
param(
    [Parameter(Mandatory)][string]$LogPath
)

if (-not (Test-Path -LiteralPath $LogPath)) {
    Write-Error "Log not found: $LogPath"
    exit 1
}

$steps = @()
$perf = @()
$launch = @()
$snapshots = 0

Get-Content -LiteralPath $LogPath | ForEach-Object {
    if ($_ -match 'STEP end: (.+?) ok ms=(\d+)') {
        $steps += [PSCustomObject]@{ Step = $Matches[1]; Ms = [int]$Matches[2] }
    }
    elseif ($_ -match 'PERF\[([^\]]+)\] ms=(\d+)(.*)$') {
        $perf += [PSCustomObject]@{ Mark = $Matches[1]; Ms = [int]$Matches[2]; Extra = $Matches[3].Trim() }
    }
    elseif ($_ -match 'LAUNCH_(BEGIN|SKIP|OK|FAIL)') {
        $launch += $_.Trim()
    }
    elseif ($_ -match 'SNAPSHOT\[') {
        $script:snapshots++
    }
}

Write-Host ""
Write-Host "=== Connect perf summary ===" -ForegroundColor Cyan
Write-Host "Log: $LogPath"
Write-Host ""

if ($steps.Count -gt 0) {
    Write-Host "Steps:" -ForegroundColor Yellow
    foreach ($s in $steps) {
        Write-Host ("  {0,-28} {1,6} ms" -f $s.Step, $s.Ms)
    }
    $open = $steps | Where-Object { $_.Step -match 'Opening' } | Select-Object -Last 1
    if ($open) {
        Write-Host ""
        Write-Host ("Opening Cursor gate: {0} ms (target cold <8000, skip <1500)" -f $open.Ms) -ForegroundColor $(if ($open.Ms -lt 8000) { 'Green' } else { 'Red' })
    }
}

$summary = $perf | Where-Object { $_.Mark -eq 'session_open_summary' } | Select-Object -Last 1
if ($summary) {
    Write-Host ""
    Write-Host "Session summary: $($summary.Extra)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "SNAPSHOT lines: $snapshots (target 0 unless VERBOSE_LAUNCH=1)" -ForegroundColor $(if ($snapshots -eq 0) { 'Green' } else { 'Yellow' })

$cimMarks = @($perf | Where-Object { $_.Mark -eq 'cim_query' })
if ($cimMarks.Count -gt 0) {
    $hits = @($cimMarks | Where-Object { $_.Extra -match 'cache_hit=1' }).Count
    Write-Host "CIM queries: $($cimMarks.Count) cache_hits=$hits" -ForegroundColor Yellow
}

if ($launch.Count -gt 0) {
    Write-Host ""
    Write-Host "Launch milestones:" -ForegroundColor Yellow
    foreach ($l in $launch) { Write-Host "  $l" }
}

Write-Host ""
