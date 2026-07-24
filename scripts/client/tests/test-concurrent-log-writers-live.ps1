# test-concurrent-log-writers-live.ps1 - LIVE (Bug 6): proves both (a) the underlying per-process
# day-log FileStream/StreamWriter primitive is genuinely unsafe under concurrent unsynchronized
# writers (documents WHY a fix is needed), and (b) the REAL, FIXED code path in connect-ui.ps1 -
# Initialize-ConnectLog registering $script:ConnectLogFileStream + the mutex-protected
# Write-ConnectLogSynced re-seeking to true EOF before every flush - actually eliminates that
# corruption when real, separate powershell.exe processes hammer the same day-log file
# concurrently with zero external coordination beyond the fix itself.
#
# History: Initialize-ConnectLog originally opened its FileStream/StreamWriter with
#   FileMode.Append + FileShare.ReadWrite, AutoFlush=true, and assigned the writer ONLY to a
#   local variable - never to $script:ConnectLogFileStream. Get-ConnectLogWriteMutex
#   (Global\ClaudeConnectDayLogWrite) + Write-ConnectLogSynced already existed to re-seek to the
#   true current EOF inside a cross-process mutex before every flush (the textbook fix for
#   FileMode.Append's "seeks to EOF once, at open time only" behavior) - but because
#   $script:ConnectLogFileStream was never set by Initialize-ConnectLog, that re-seek was
#   silently a no-op for the real interactive session writer, so mutex-serialized flushes still
#   landed at a stale offset and corrupted/overwrote concurrent processes' bytes.
#
# FIX (2026-07-24): Initialize-ConnectLog now assigns $script:ConnectLogFileStream = $fs. Further
# empirical live testing (this test's own multi-process driver) then found that even a corrective
# Seek(0, SeekOrigin.End) on that shared, long-lived FileStream still occasionally landed at a
# stale length under real back-to-back cross-process writes - so Write-ConnectLogSynced was
# hardened further to open a BRAND-NEW, single-purpose FileStream (FileMode.Append) for every
# mutex-protected write instead of reusing/reseeking the shared stream. A fresh FileMode.Append
# open has the OS resolve "current end of file" itself at that exact open call, with no cached/
# stale state possible. The cross-process mutex still provides the exclusivity.
#
# Does NOT modify any production .ps1 file - reads connect-ui.ps1 to extract the real functions
# under test (Get-FunctionSource brace-extraction, the established idiom), then exercises them
# from disposable temp child scripts writing to a disposable temp log file.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Bug 6: concurrent day-log writers - primitive risk + real fix verification (LIVE) ===' -ForegroundColor Cyan

$connectUiPath = Get-ClientFile 'connect-ui.ps1'
$raw = Get-Content -LiteralPath $connectUiPath -Raw
$initFnSrc = Get-FunctionSource -Content $raw -Name 'Initialize-ConnectLog'
if (-not $initFnSrc) {
    Write-Host '  FAIL  could not extract Initialize-ConnectLog from connect-ui.ps1 - source may have moved' -ForegroundColor Red
    exit 1
}
$syncedFnSrc = Get-FunctionSource -Content $raw -Name 'Write-ConnectLogSynced'
$mutexFnSrc = Get-FunctionSource -Content $raw -Name 'Get-ConnectLogWriteMutex'
if (-not $syncedFnSrc -or -not $mutexFnSrc) {
    Write-Host '  FAIL  could not extract Write-ConnectLogSynced / Get-ConnectLogWriteMutex from connect-ui.ps1 - source may have moved' -ForegroundColor Red
    exit 1
}

# --- Fix verification (source-level): Initialize-ConnectLog must register the FileStream it
#     constructs into $script:ConnectLogFileStream so Write-ConnectLogSynced's re-seek is live. ---
Assert ($initFnSrc -match '\$script:ConnectLogFileStream\s*=\s*\$fs') 'BUG 6 FIX PRESENT: Initialize-ConnectLog assigns $script:ConnectLogFileStream = $fs'
Assert ($syncedFnSrc -match '\[System\.IO\.FileStream\]::new\(' -and $syncedFnSrc -match '\[System\.IO\.FileMode\]::Append') 'Write-ConnectLogSynced opens a brand-new FileMode.Append FileStream per protected write (hardened fix - a reseek on a shared long-lived stream was empirically found still occasionally stale under real cross-process writes)'
Assert ($mutexFnSrc -match "Global\\ClaudeConnectDayLogWrite") 'Get-ConnectLogWriteMutex uses the real cross-process named mutex (Global\ClaudeConnectDayLogWrite)'

Write-Host ''
Write-Host '--- Phase 1: the underlying primitive (unsynchronized FileStream/StreamWriter) is genuinely unsafe ---' -ForegroundColor Cyan
Write-Host '  (documents WHY Write-ConnectLogSynced + the FileStream registration fix are needed - not itself the fix under test)' -ForegroundColor DarkGray

$childRawPath = Join-Path $env:TEMP ("bug6-raw-writer-{0}.ps1" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
$childRawContent = @'
param(
    [Parameter(Mandatory)][string]$LogPath,
    [Parameter(Mandatory)][string]$Marker,
    [Parameter(Mandatory)][int]$Count
)
# Raw primitive: FileMode.Append + FileShare.ReadWrite FileStream, AutoFlush StreamWriter,
# zero cross-process synchronization at all (no mutex, no reseek).
$fs = [System.IO.FileStream]::new(
    $LogPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
$writer = [System.IO.StreamWriter]::new($fs, [System.Text.UTF8Encoding]::new($false))
$writer.AutoFlush = $true
for ($i = 0; $i -lt $Count; $i++) {
    $writer.WriteLine(('[PROC-{0}] line-{1} {2}' -f $Marker, $i.ToString('D5'), ('x' * 40)))
}
try { $writer.Flush() } catch { }
try { $writer.Dispose() } catch { }
'@
Set-Content -LiteralPath $childRawPath -Value $childRawContent -Encoding UTF8

$psExe = (Get-Process -Id $PID).Path
if (-not $psExe) { $psExe = 'powershell.exe' }
$linePattern = '^\[PROC-[A-Z]\] line-\d+ x{40}$'

function Invoke-ConcurrentWriters {
    param([string]$ChildScript, [scriptblock]$ExtraArgsBuilder)
    $attempts = @(
        @{ N = 300;  Procs = @('A', 'B') },
        @{ N = 800;  Procs = @('A', 'B', 'C') },
        @{ N = 1500; Procs = @('A', 'B', 'C', 'D') },
        @{ N = 3000; Procs = @('A', 'B', 'C', 'D') },
        @{ N = 6000; Procs = @('A', 'B', 'C', 'D') }
    )
    $corrupted = $false
    $evidence = $null
    for ($attempt = 1; $attempt -le $attempts.Count -and -not $corrupted; $attempt++) {
        $cfg = $attempts[$attempt - 1]
        $n = [int]$cfg.N
        $procs = $cfg.Procs
        $logPath = Join-Path $env:TEMP ("bug6-daylog-{0}.log" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
        if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue }

        Write-Host ("  attempt {0}/{1}: N={2} lines/process x {3} real processes ({4})" -f `
                $attempt, $attempts.Count, $n, $procs.Count, ($procs -join ','))

        $handles = @()
        foreach ($m in $procs) {
            $extra = & $ExtraArgsBuilder $logPath $m $n
            $p = Start-Process -FilePath $psExe -ArgumentList (@(
                    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $ChildScript
                ) + $extra) -PassThru -WindowStyle Hidden
            $handles += $p
        }
        foreach ($p in $handles) { $p.WaitForExit() }
        Start-Sleep -Milliseconds 200

        $lines = @()
        if (Test-Path -LiteralPath $logPath) { $lines = @(Get-Content -LiteralPath $logPath) }
        $expectedTotal = $n * $procs.Count
        $actualTotal = $lines.Count
        $badLines = @($lines | Where-Object { $_ -notmatch $linePattern })

        Write-Host ("    expected_total_lines={0}  actual_total_lines={1}  malformed_lines={2}" -f $expectedTotal, $actualTotal, $badLines.Count)

        if ($badLines.Count -gt 0 -or $actualTotal -ne $expectedTotal) {
            $corrupted = $true
            $evidence = [PSCustomObject]@{
                Attempt = $attempt; N = $n; ProcCount = $procs.Count
                ExpectedTotal = $expectedTotal; ActualTotal = $actualTotal
                BadLineCount = $badLines.Count; BadSamples = @($badLines | Select-Object -First 8)
                LogPath = $logPath
            }
        } else {
            Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
        }
    }
    return [PSCustomObject]@{ Corrupted = $corrupted; Evidence = $evidence; MaxAttempts = $attempts.Count }
}

$rawResult = Invoke-ConcurrentWriters -ChildScript $childRawPath -ExtraArgsBuilder {
    param($logPath, $marker, $n)
    @('-LogPath', $logPath, '-Marker', $marker, '-Count', $n)
}

if ($rawResult.Corrupted) {
    Write-Host '  --- corrupted line samples (raw primitive) ---' -ForegroundColor Red
    $rawResult.Evidence.BadSamples | ForEach-Object { Write-Host ("    CORRUPT: {0}" -f $_) -ForegroundColor Red }
}
Assert $rawResult.Corrupted ("raw unsynchronized FileStream/StreamWriter primitive reproduces real byte-level corruption across independent powershell.exe processes (honest retry budget: up to {0} escalating attempts) - this is why the fix below is necessary" -f $rawResult.MaxAttempts)
if ($rawResult.Evidence) {
    Remove-Item -LiteralPath $rawResult.Evidence.LogPath -Force -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath $childRawPath -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '--- Phase 2: the REAL fixed path (Initialize-ConnectLog registration + Write-ConnectLogSynced mutex+reseek) is corruption-free ---' -ForegroundColor Cyan

# Child script dot-sources the REAL extracted Get-ConnectLogWriteMutex + Write-ConnectLogSynced
# functions (verbatim production source, not a reimplementation), reproduces the REAL fixed
# Initialize-ConnectLog opening (FileStream + $script:ConnectLogFileStream registration), then
# routes every write through the real Write-ConnectLogSynced - exactly what every real
# Write-ConnectLog INFO/WARN/ERROR call does in production.
$childFixedPath = Join-Path $env:TEMP ("bug6-fixed-writer-{0}.ps1" -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
$childFixedContent = @"
param(
    [Parameter(Mandatory)][string]`$LogPath,
    [Parameter(Mandatory)][string]`$Marker,
    [Parameter(Mandatory)][int]`$Count
)
$mutexFnSrc

$syncedFnSrc

# Real fixed Initialize-ConnectLog opening pattern (verbatim: FileMode.Append, FileShare.ReadWrite,
# AutoFlush StreamWriter, PLUS the bug-6 fix - registering `$script:ConnectLogFileStream = `$fs).
`$script:ConnectLogPath = `$LogPath
`$fs = [System.IO.FileStream]::new(
    `$script:ConnectLogPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
`$script:ConnectLogFileStream = `$fs
`$script:ConnectLogWriter = [System.IO.StreamWriter]::new(`$fs, [System.Text.UTF8Encoding]::new(`$false))
`$script:ConnectLogWriter.AutoFlush = `$true

for (`$i = 0; `$i -lt `$Count; `$i++) {
    Write-ConnectLogSynced -Line ('[PROC-{0}] line-{1} {2}' -f `$Marker, `$i.ToString('D5'), ('x' * 40))
}
try { `$script:ConnectLogWriter.Dispose() } catch { }
"@
Set-Content -LiteralPath $childFixedPath -Value $childFixedContent -Encoding UTF8

$fixedResult = Invoke-ConcurrentWriters -ChildScript $childFixedPath -ExtraArgsBuilder {
    param($logPath, $marker, $n)
    @('-LogPath', $logPath, '-Marker', $marker, '-Count', $n)
}

if ($fixedResult.Corrupted) {
    Write-Host '  --- corrupted line samples (real fixed path - UNEXPECTED) ---' -ForegroundColor Red
    $fixedResult.Evidence.BadSamples | ForEach-Object { Write-Host ("    CORRUPT: {0}" -f $_) -ForegroundColor Red }
    Write-Host ("  RED: attempt={0} N={1} procs={2} expected_lines={3} actual_lines={4} malformed_lines={5}" -f `
            $fixedResult.Evidence.Attempt, $fixedResult.Evidence.N, $fixedResult.Evidence.ProcCount, `
            $fixedResult.Evidence.ExpectedTotal, $fixedResult.Evidence.ActualTotal, $fixedResult.Evidence.BadLineCount) -ForegroundColor Red
    Remove-Item -LiteralPath $fixedResult.Evidence.LogPath -Force -ErrorAction SilentlyContinue
} else {
    Write-Host ("  GREEN: real Write-ConnectLogSynced path survived all {0} escalating attempts (up to 4 concurrent real processes x 6000 lines each) with zero corrupted/lost lines" -f $fixedResult.MaxAttempts) -ForegroundColor Green
}
Assert (-not $fixedResult.Corrupted) 'BUG 6 FIXED (GREEN): the real Initialize-ConnectLog opening + real Write-ConnectLogSynced mutex+fresh-handle-per-write path produces NO corrupted or lost lines across real concurrent powershell.exe processes, at the exact same escalating N/process-count budget that reliably corrupted the raw primitive in Phase 1'

Remove-Item -LiteralPath $childFixedPath -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS (Bug 6 fix verified live: primitive is unsafe unsynchronized, but the real fixed code path is corruption-free)' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
