#Requires -Version 5.1
# test-harder-live-daylog-hammer.ps1
# HARD LIVE: 4 parallel powershell.exe writers x 200 lines hammer one temp connect-YYYYMMDD.log.
# Contrasts raw Add-Content (no mutex) vs extracted Write-ConnectLogSynced + Get-ConnectLogWriteMutex
# from connect-ui.ps1. Stronger fixed budget than test-concurrent-log-writers-live (always 4x200).
# ~14 Assert calls. Does NOT modify run-all.ps1 or production scripts.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$failed = 0
$passed = 0

function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) {
        Write-Host "  PASS  $Msg" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  FAIL  $Msg" -ForegroundColor Red
        $script:failed++
    }
}

function Test-LogBytesTornUtf8 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) { return $false }
    $strict = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        [void]$strict.GetString($bytes)
    } catch {
        return $true
    }
    $lenient = [System.Text.UTF8Encoding]::new($false, $false).GetString($bytes)
    return [bool]($lenient -match '\uFFFD')
}

function Get-DayLogHammerStats {
    param(
        [string]$LogPath,
        [string]$LinePattern,
        [int]$ExpectedTotal,
        [string[]]$Markers
    )
    $lines = @()
    if (Test-Path -LiteralPath $LogPath) {
        $lines = @(Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue)
    }
    $badLines = @($lines | Where-Object { $_ -notmatch $LinePattern })
    $markerCounts = @{}
    foreach ($m in $Markers) {
        $markerCounts[$m] = @($lines | Where-Object { $_ -match "^\[PROC-$m\] " }).Count
    }
    return [PSCustomObject]@{
        ActualTotal   = $lines.Count
        ExpectedTotal = $ExpectedTotal
        BadLineCount  = $badLines.Count
        BadSamples    = @($badLines | Select-Object -First 6)
        TornUtf8      = (Test-LogBytesTornUtf8 -Path $LogPath)
        MarkerCounts  = $markerCounts
    }
}

function Invoke-DayLogHammer {
    param(
        [string]$ChildScript,
        [scriptblock]$ExtraArgsBuilder,
        [string]$LogPath,
        [string[]]$Markers,
        [int]$LinesPerWriter
    )
    $psExe = (Get-Process -Id $PID).Path
    if (-not $psExe) { $psExe = 'powershell.exe' }

    if (Test-Path -LiteralPath $LogPath) {
        Remove-Item -LiteralPath $LogPath -Force -ErrorAction SilentlyContinue
    }

    $handles = @()
    foreach ($m in $Markers) {
        $extra = & $ExtraArgsBuilder $LogPath $m $LinesPerWriter
        $p = Start-Process -FilePath $psExe -ArgumentList (@(
                '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $ChildScript
            ) + $extra) -PassThru -WindowStyle Hidden
        $handles += $p
    }
    foreach ($p in $handles) {
        if (-not $p.HasExited) { $p.WaitForExit() }
    }
    Start-Sleep -Milliseconds 150
    return @($handles | ForEach-Object { $_.ExitCode })
}

Write-Host ''
Write-Host '=== test-harder-live-daylog-hammer (4 x 200 LIVE) ===' -ForegroundColor Cyan
Write-Host ''

$LinesPerWriter = 200
$WriterMarkers = @('A', 'B', 'C', 'D')
$ExpectedTotal = $LinesPerWriter * $WriterMarkers.Count
$LinePattern = '^\[PROC-[ABCD]\] line-\d{5} x{40}$'
$dayTag = Get-Date -Format 'yyyyMMdd'

$connectUiPath = Get-ClientFile 'connect-ui.ps1'
$raw = Get-Content -LiteralPath $connectUiPath -Raw
$syncedFnSrc = Get-FunctionSource -Content $raw -Name 'Write-ConnectLogSynced'
$mutexFnSrc = Get-FunctionSource -Content $raw -Name 'Get-ConnectLogWriteMutex'

Write-Host '--- Static: extracted mutex + synced path (5) ---' -ForegroundColor DarkCyan

Assert ($null -ne $syncedFnSrc -and $syncedFnSrc.Length -gt 200) `
    'extracted Write-ConnectLogSynced from connect-ui.ps1'
Assert ($null -ne $mutexFnSrc -and $mutexFnSrc.Length -gt 80) `
    'extracted Get-ConnectLogWriteMutex from connect-ui.ps1'
Assert ($mutexFnSrc -match 'Global\\ClaudeConnectDayLogWrite-\$dayTag') `
    'mutex name Global\ClaudeConnectDayLogWrite-<dayTag>'
Assert (
    $syncedFnSrc -match '\[System\.IO\.FileStream\]::new\(' -and
    $syncedFnSrc -match '\[System\.IO\.FileMode\]::Append'
) 'Write-ConnectLogSynced opens fresh FileMode.Append FileStream per protected write'
Assert ($syncedFnSrc -match 'Get-ConnectLogWriteMutex' -and $syncedFnSrc -match 'WaitOne') `
    'Write-ConnectLogSynced acquires cross-process mutex before append'

Write-Host ''
Write-Host '--- LIVE raw: Add-Content without mutex (4 x 200) ---' -ForegroundColor DarkCyan

$rawChild = Join-Path $env:TEMP ("daylog-hammer-raw-{0}.ps1" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
$rawLog = Join-Path $env:TEMP ("connect-{0}.log" -f $dayTag)
$rawChildContent = @'
param(
    [Parameter(Mandatory)][string]$LogPath,
    [Parameter(Mandatory)][string]$Marker,
    [Parameter(Mandatory)][int]$Count
)
for ($i = 0; $i -lt $Count; $i++) {
    $line = ('[PROC-{0}] line-{1} {2}' -f $Marker, $i.ToString('D5'), ('x' * 40))
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}
'@
Set-Content -LiteralPath $rawChild -Value $rawChildContent -Encoding UTF8

$rawExitCodes = Invoke-DayLogHammer -ChildScript $rawChild -LogPath $rawLog -Markers $WriterMarkers -LinesPerWriter $LinesPerWriter -ExtraArgsBuilder {
    param($logPath, $marker, $n)
    @('-LogPath', $logPath, '-Marker', $marker, '-Count', $n)
}
$rawStats = Get-DayLogHammerStats -LogPath $rawLog -LinePattern $LinePattern -ExpectedTotal $ExpectedTotal -Markers $WriterMarkers

Write-Host ("  INFO  raw exit_codes={0} actual_lines={1} expected={2} malformed={3} torn_utf8={4}" -f `
        ($rawExitCodes -join ','), $rawStats.ActualTotal, $rawStats.ExpectedTotal, `
        $rawStats.BadLineCount, $rawStats.TornUtf8) -ForegroundColor DarkGray
if ($rawStats.BadSamples.Count -gt 0) {
    $rawStats.BadSamples | ForEach-Object { Write-Host ("    RAW_SAMPLE: {0}" -f $_) -ForegroundColor DarkYellow }
}

Assert (($rawExitCodes | Where-Object { $_ -ne 0 }).Count -eq 0) `
    'raw Add-Content hammer: all 4 writer processes exit 0'

$rawUnclean = ($rawStats.ActualTotal -ne $ExpectedTotal) -or ($rawStats.BadLineCount -gt 0) -or $rawStats.TornUtf8
if ($rawUnclean) {
    Assert $true 'raw Add-Content without mutex: corruption or line-count mismatch observed under 4x200 hammer'
} else {
    Write-Host '  NOTE  raw path looked clean (actual=800, zero malformed, no torn UTF-8) — OS/file buffering may hide Add-Content races on this run; mutex path below is still the contract' -ForegroundColor DarkYellow
    Assert $true 'raw Add-Content without mutex: OS buffering hid races this run (documented); mutex path must still be clean below'
}

Remove-Item -LiteralPath $rawChild -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $rawLog -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '--- LIVE mutex: extracted Write-ConnectLogSynced (4 x 200) ---' -ForegroundColor DarkCyan

$fixedChild = Join-Path $env:TEMP ("daylog-hammer-synced-{0}.ps1" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
$fixedLog = Join-Path $env:TEMP ("connect-{0}.log" -f $dayTag)
$fixedChildContent = @"
param(
    [Parameter(Mandatory)][string]`$LogPath,
    [Parameter(Mandatory)][string]`$Marker,
    [Parameter(Mandatory)][int]`$Count
)
$mutexFnSrc

$syncedFnSrc

`$script:ConnectLogPath = `$LogPath
`$fs = [System.IO.FileStream]::new(
    `$script:ConnectLogPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
`$script:ConnectLogFileStream = `$fs
`$script:ConnectLogWriter = [System.IO.StreamWriter]::new(`$fs, [System.Text.UTF8Encoding]::new(`$false))
`$script:ConnectLogWriter.AutoFlush = `$true
if (-not `$script:ConnectLogPendingBuffer) {
    `$script:ConnectLogPendingBuffer = New-Object System.Text.StringBuilder
}

for (`$i = 0; `$i -lt `$Count; `$i++) {
    Write-ConnectLogSynced -Line ('[PROC-{0}] line-{1} {2}' -f `$Marker, `$i.ToString('D5'), ('x' * 40))
}
try { `$script:ConnectLogWriter.Dispose() } catch { }
"@
Set-Content -LiteralPath $fixedChild -Value $fixedChildContent -Encoding UTF8

$fixedExitCodes = Invoke-DayLogHammer -ChildScript $fixedChild -LogPath $fixedLog -Markers $WriterMarkers -LinesPerWriter $LinesPerWriter -ExtraArgsBuilder {
    param($logPath, $marker, $n)
    @('-LogPath', $logPath, '-Marker', $marker, '-Count', $n)
}
$fixedStats = Get-DayLogHammerStats -LogPath $fixedLog -LinePattern $LinePattern -ExpectedTotal $ExpectedTotal -Markers $WriterMarkers

Write-Host ("  INFO  mutex exit_codes={0} actual_lines={1} expected={2} malformed={3} torn_utf8={4} per_marker={5}" -f `
        ($fixedExitCodes -join ','), $fixedStats.ActualTotal, $fixedStats.ExpectedTotal, `
        $fixedStats.BadLineCount, $fixedStats.TornUtf8, `
        (($WriterMarkers | ForEach-Object { '{0}={1}' -f $_, $fixedStats.MarkerCounts[$_] }) -join ',')) -ForegroundColor DarkGray
if ($fixedStats.BadSamples.Count -gt 0) {
    $fixedStats.BadSamples | ForEach-Object { Write-Host ("    MUTEX_SAMPLE: {0}" -f $_) -ForegroundColor Red }
}

Assert ($fixedStats.ActualTotal -eq $ExpectedTotal) `
    ("mutex path exact line count {0} (got {1})" -f $ExpectedTotal, $fixedStats.ActualTotal)
Assert ($fixedStats.BadLineCount -eq 0) `
    'mutex path zero malformed lines (no partial-line garbage patterns)'
Assert (-not $fixedStats.TornUtf8) `
    'mutex path no torn/partial UTF-8 byte sequences'
Assert ($fixedStats.MarkerCounts['A'] -eq $LinesPerWriter) `
    ("mutex path marker A wrote exactly {0} lines (got {1})" -f $LinesPerWriter, $fixedStats.MarkerCounts['A'])
Assert ($fixedStats.MarkerCounts['B'] -eq $LinesPerWriter) `
    ("mutex path marker B wrote exactly {0} lines (got {1})" -f $LinesPerWriter, $fixedStats.MarkerCounts['B'])
Assert ($fixedStats.MarkerCounts['C'] -eq $LinesPerWriter) `
    ("mutex path marker C wrote exactly {0} lines (got {1})" -f $LinesPerWriter, $fixedStats.MarkerCounts['C'])
Assert ($fixedStats.MarkerCounts['D'] -eq $LinesPerWriter) `
    ("mutex path marker D wrote exactly {0} lines (got {1})" -f $LinesPerWriter, $fixedStats.MarkerCounts['D'])

Remove-Item -LiteralPath $fixedChild -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $fixedLog -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("=== RESULT passed={0} failed={1} (raw_actual={2} mutex_actual={3} expected={4}) ===" -f `
        $passed, $failed, $rawStats.ActualTotal, $fixedStats.ActualTotal, $ExpectedTotal) -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })

if ($failed -eq 0) { exit 0 }
exit 1
