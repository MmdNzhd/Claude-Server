# deep-audit-log.ps1 - ms-level waste analysis for connect.log
param([Parameter(Mandatory)][string]$LogPath)
$lines = @(Get-Content -LiteralPath $LogPath)
Write-Host "=== Deep log audit: $LogPath ===" -ForegroundColor Cyan
$ver = ($lines | Where-Object { $_ -match 'session start v' } | Select-Object -First 1)
Write-Host "Session: $ver"
Write-Host ""

function Parse-Ts($line) {
    if ($line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\]') {
        return [datetime]::ParseExact(
            $Matches[1],
            'yyyy-MM-dd HH:mm:ss.fff',
            [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $null
}

$sessions = @()
$cur = $null
foreach ($ln in $lines) {
    if ($ln -match 'session start v([0-9.]+)') {
        if ($cur) { $sessions += $cur }
        $cur = @{ Version = $Matches[1]; Lines = [System.Collections.Generic.List[string]]::new(); OpenMs = $null; Events = @() }
    }
    if ($cur) { $cur.Lines.Add($ln) }
}
if ($cur) { $sessions += $cur }

foreach ($s in $sessions) {
    Write-Host "--- Session v$($s.Version) ---" -ForegroundColor Yellow
    $launchBegin = $null; $launchOk = $null; $launchSkip = $null
    $snapshots = 0; $perf = 0
    $resultAfterOk = $false; $wasteAfterPoll = $false; $seenOk = $false
    $inOpening = $false; $pollSuccess = $false; $pollSuccessAt = $null
    foreach ($ln in $s.Lines) {
        if ($ln -match 'STEP begin: Opening Cursor') { $inOpening = $true; $pollSuccess = $false; $pollSuccessAt = $null; continue }
        if ($ln -match 'STEP end: Opening Cursor ok ms=(\d+)') {
            $s.OpenMs = [int]$Matches[1]
            $inOpening = $false
            continue
        }
        if (-not $inOpening) { continue }

        if ($ln -match 'LAUNCH_BEGIN:') { $launchBegin = Parse-Ts $ln }
        if ($ln -match 'LAUNCH_OK:') {
            $launchOk = Parse-Ts $ln
            $seenOk = $true
            if ($pollSuccessAt -and $launchOk) {
                $wasteMs = ($launchOk - $pollSuccessAt).TotalMilliseconds
                if ($wasteMs -gt 500) { $wasteAfterPoll = $true }
            }
            $pollSuccess = $false
            continue
        }
        if ($ln -match 'LAUNCH_SKIP:') { $launchSkip = Parse-Ts $ln }
        if ($ln -match 'SNAPSHOT\[') { $snapshots++ }
        if ($ln -match 'PERF\[') { $perf++ }
        if ($ln -match 'LAUNCH_POLL:.*on_folder=True') {
            $pollSuccess = $true
            $pollSuccessAt = Parse-Ts $ln
            continue
        }
        if ($pollSuccess -and $ln -match 'LAUNCH_ATTEMPT_RESULT:|SNAPSHOT\[RESULT|STATE\[RESULT_') {
            $resultAfterOk = $true
        }
        if ($seenOk -and $ln -match 'LAUNCH_ATTEMPT_RESULT:') { $resultAfterOk = $true; $seenOk = $false }
    }
    Write-Host "  Opening Cursor ms: $($s.OpenMs)"
    Write-Host "  SNAPSHOT count: $snapshots"
    Write-Host "  PERF marks: $perf"
    Write-Host "  LAUNCH_SKIP: $(if($launchSkip){'yes'}else{'no'})"
    Write-Host "  Waste after poll success: $(if($wasteAfterPoll){'YES (F2 bug)'}else{'no'})"
    Write-Host "  Waste after LAUNCH_OK: $(if($resultAfterOk){'YES (F2 tail)'}else{'no'})"
    if ($launchBegin -and $launchOk) {
        $waste = ($launchOk - $launchBegin).TotalMilliseconds
        Write-Host "  LAUNCH_BEGIN -> LAUNCH_OK: $([int]$waste) ms"
    }
    if ($launchBegin -and $launchSkip) {
        $skipMs = ($launchSkip - $launchBegin).TotalMilliseconds
        Write-Host "  LAUNCH_BEGIN -> LAUNCH_SKIP: $([int]$skipMs) ms"
    }
    Write-Host ""
}

# Extract first cold-open timeline
Write-Host '=== Cold open event timeline (first Opening Cursor) ===' -ForegroundColor Cyan
$inOpen = $false
foreach ($ln in $lines) {
    if ($ln -match 'STEP begin: Opening Cursor') { $inOpen = $true; Write-Host $ln; continue }
    if (-not $inOpen) { continue }
    if ($ln -match 'STEP end: Opening Cursor') { Write-Host $ln; break }
    if ($ln -match 'LAUNCH_|SNAPSHOT|PERF\[|FOLDER_CHECK|DIAG\[|STATE\[|EDITOR_DECISION') { Write-Host $ln }
}
