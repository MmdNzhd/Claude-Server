# test-context-log-sync-noninline-live.ps1 - Bug 9 LIVE: proves Write-ConnectSessionContext no
# longer risks a blocking log-sync on every routine CONTEXT phase transition (startup,
# project_selected, session_loop, server_ready, ...).
#
# Live incident this reproduces (2026-07-24): right after project selection, the log went silent
# for 36.3 real seconds before "LOG_SYNC_FAIL ... mkdir_timeout_or_fail" appeared. Root cause:
# Write-ConnectSessionContext called bare `Request-ConnectLogSync` (no -NoInline) for every phase
# except session_end. Request-ConnectLogSync's own "small backlog" branch (connect-ui.ps1 ~888)
# then ran `Sync-ConnectLogToServer` INLINE (blocking) whenever the unsynced backlog happened to
# be under its 64KB gate - under real network/server contention that inline call's own sequential
# sub-calls chain up to ~17s, and two phase transitions firing close together (observed live:
# project_selected then session_loop within seconds) stacked into the ~36s freeze. Per CLAUDE.md,
# only session_end is supposed to force a guaranteed flush; every other phase must be fire-and-
# forget async.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== CONTEXT-phase log-sync must not block (Bug 9) LIVE ===' -ForegroundColor Cyan

$uiContent = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw

# --- Part 1: source-drift-allergic proof the caller was actually fixed ---
$fnSrc = Get-FunctionSource -Content $uiContent -Name 'Write-ConnectSessionContext'
if (-not $fnSrc) {
    Write-Host "  FAIL  could not extract Write-ConnectSessionContext - live test cannot run (source drifted)" -ForegroundColor Red
    exit 1
}
Assert ($fnSrc -match "Phase -eq 'session_end'[\s\S]*?\}\s*elseif[\s\S]*?Request-ConnectLogSync\s+-NoInline") `
    'FIXED: the non-session_end branch of Write-ConnectSessionContext calls Request-ConnectLogSync -NoInline (fire-and-forget), not a bare/inline-capable call'
Assert ($fnSrc -notmatch "elseif \(Get-Command Request-ConnectLogSync[\s\S]{0,80}Request-ConnectLogSync\s*\r?\n") `
    'FIXED: no bare (non--NoInline) Request-ConnectLogSync call remains reachable for a non-session_end phase'

# --- Part 2: real timing proof that -NoInline genuinely never invokes a blocking sync ---
foreach ($n in @('Get-ConnectSessionId', 'Get-ConnectLogUnsyncedByteCount')) {
    $src = Get-FunctionSource -Content $uiContent -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}
$reqSrc = Get-FunctionSource -Content $uiContent -Name 'Request-ConnectLogSync'
$timerSrc = Get-FunctionSource -Content $uiContent -Name 'Ensure-ConnectLogAsyncTimer'
if (-not $reqSrc -or -not $timerSrc) {
    Write-Host "  FAIL  could not extract Request-ConnectLogSync/Ensure-ConnectLogAsyncTimer - live test cannot run (source drifted)" -ForegroundColor Red
    exit 1
}
. ([scriptblock]::Create($timerSrc))
. ([scriptblock]::Create($reqSrc))

# Stub Write-ConnectLog (real one has heavy file/mutex dependencies not needed for this test)
# and Sync-ConnectLogToServer as a REAL slow call so a leak into the inline path would be caught.
$script:SyncConnectLogToServerCalls = 0
function Write-ConnectLog { param($Line, $Level) }
function Sync-ConnectLogToServer {
    param([switch]$Force)
    $script:SyncConnectLogToServerCalls++
    Start-Sleep -Seconds 5  # if this ever runs synchronously in the -NoInline path, the test below fails
}
function Complete-ConnectLogAsyncDrain { param([switch]$Force) }

$Cfg = $null; $CfgDir = $null; $SshDir = $null; $script:ConnectScriptDir = $null; $script:ConnectVersion = 'test'
$script:ConnectBuildId = 'test'; $script:RecoveryGeneration = 0; $script:SessionLoopIter = 0

$sw = [System.Diagnostics.Stopwatch]::StartNew()
Request-ConnectLogSync -NoInline
$sw.Stop()
Write-Host "  INFO  Request-ConnectLogSync -NoInline wall-clock: $($sw.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
Assert ($sw.ElapsedMilliseconds -lt 1000) "Request-ConnectLogSync -NoInline returned in $($sw.ElapsedMilliseconds)ms - genuinely fire-and-forget, not blocked on the 5s stubbed Sync-ConnectLogToServer"
Assert ($script:SyncConnectLogToServerCalls -eq 0) 'Sync-ConnectLogToServer was never actually invoked by the -NoInline call (proves it only scheduled the async timer)'

if (Get-Command Get-EventSubscriber -ErrorAction SilentlyContinue) {
    Get-EventSubscriber -SourceIdentifier 'ConnectLogAsyncTimerElapsed' -ErrorAction SilentlyContinue | Unregister-Event -ErrorAction SilentlyContinue
}
if ($script:ConnectLogAsyncTimer) { try { $script:ConnectLogAsyncTimer.Stop(); $script:ConnectLogAsyncTimer.Dispose() } catch { } }

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS (GREEN): Bug 9 is FIXED - routine CONTEXT phase transitions no longer risk a blocking log-sync stall.' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
