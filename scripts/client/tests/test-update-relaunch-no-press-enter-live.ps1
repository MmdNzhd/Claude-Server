#Requires -Version 5.1
# Live proof: when connect-update is &'d from a session that still has a STALE
# Wait-ConnectExit (shows Press Enter), the NEW updater must kill the process
# after apply so that prompt never appears. Also asserts Defer is gone from prompt.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== update relaunch: no stale Press Enter (LIVE) ===' -ForegroundColor Cyan

$updRepo = Get-ClientFile 'windows\connect-update.ps1'
$src = Get-Content -LiteralPath $updRepo -Raw
Assert ($src -notmatch '\[D\]efer 48h') 'prompt no longer offers [D]efer 48h'
Assert ($src -match 'Update now\? \[Y\]es / \[N\]ot now:') 'prompt is Yes / Not now only'
Assert ($src -match 'kill_self skip_stale_press_enter') 'apply path kills self when called from live UI'
Assert ($src -match 'calledFromLiveUi|Wait-ConnectExit') 'detects same-process live UI via Wait-ConnectExit'
Assert ($src -match '\[Environment\]::Exit\(2\)') 'uses Environment.Exit(2) so caller cannot resume'
Assert ($src -notmatch 'if \(Test-UpdateDeferActive') 'no longer skips apply because of defer stamp'

$live = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$liveUpd = Join-Path $live 'connect-update.ps1'
if (-not (Test-Path -LiteralPath $liveUpd)) {
    Write-Host '  FAIL  live connect-update.ps1 missing' -ForegroundColor Red
    exit 1
}
# Ensure live has the new kill_self code under test (copy from repo)
Copy-Item -LiteralPath $updRepo -Destination $liveUpd -Force
Assert ((Get-Content -LiteralPath $liveUpd -Raw) -match 'kill_self skip_stale_press_enter') 'live updater patched with kill_self'

$markerDir = Join-Path $env:TEMP ("cc-no-press-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $markerDir
$pressMarker = Join-Path $markerDir 'press-enter-reached.txt'
$startedMarker = Join-Path $markerDir 'harness-started.txt'
$exitMarker = Join-Path $markerDir 'harness-exit.txt'
$logMarker = Join-Path $markerDir 'harness.log'

$harness = Join-Path $markerDir 'stale-ui-harness.ps1'
@'
param([string]$LiveDir, [string]$MarkerDir)
$ErrorActionPreference = 'Continue'
$pressMarker = Join-Path $MarkerDir 'press-enter-reached.txt'
$startedMarker = Join-Path $MarkerDir 'harness-started.txt'
$exitMarker = Join-Path $MarkerDir 'harness-exit.txt'
$logMarker = Join-Path $MarkerDir 'harness.log'
function Log($m) { Add-Content -LiteralPath $logMarker -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $m) }

Set-Content -LiteralPath $startedMarker -Value $PID -Encoding ASCII
Log ("harness pid=$PID live=$LiveDir")

# STALE Wait-ConnectExit — what an old pre-update session still has in memory.
function Wait-ConnectExit {
    param([string]$Reason = 'user_close', [int]$Code = 1)
    Log ("STALE Wait-ConnectExit reason=$Reason code=$Code")
    Set-Content -LiteralPath $pressMarker -Value ("reason={0}" -f $Reason) -Encoding ASCII
    # Do not actually block on Read-Host in CI; marker is the proof.
    Log 'would have shown Press Enter to close'
}

$script:ConnectUiReady = $true
$env:CLAUDE_CONNECT_UPDATE_YES = '1'
$env:CLAUDE_CONNECT_UPDATE_UI = '0'
$env:CLAUDE_CONNECT_MANUAL_UPDATE = '1'
Remove-Item -LiteralPath (Join-Path $env:TEMP 'claude-connect-kill-self.marker') -Force -ErrorAction SilentlyContinue

# Make local behind remote so apply path runs (or up-to-date still exercises handoff).
$verFile = Join-Path $LiveDir 'connect-version.txt'
$serverVer = ''
try {
    $serverVer = (ssh -o BatchMode=yes -o ConnectTimeout=8 smart@192.168.210.240 'cat /usr/local/share/claude-client/connect-version.txt').Trim()
} catch {}
$prev = ''
if (Test-Path $verFile) { $prev = (Get-Content -LiteralPath $verFile -Raw).Trim() }
if ($serverVer -match '^\d{8}\.\d+$') {
    # Force a real apply when possible by writing an older local version.
    if ($prev -eq $serverVer) {
        Set-Content -LiteralPath $verFile -Value '20260726.01' -Encoding ASCII -NoNewline
        Log "forced local ver 20260726.01 (was $prev) server=$serverVer"
    }
}

$upd = Join-Path $LiveDir 'connect-update.ps1'
Log 'calling connect-update.ps1 (same process, Wait-ConnectExit visible)'
try {
    & $upd -ScriptDir $LiveDir
    $ec = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
    Log ("connect-update returned ec=$ec (SHOULD NOT HAPPEN after kill_self apply)")
} catch {
    Log ("connect-update threw: $($_.Exception.Message)")
}

# If we still reach here after a successful apply, stale path would show Press Enter.
if ($ec -eq 2) {
    Log 'simulating stale Invoke-ConnectManualUpdate post-apply'
    Write-Host '    Update applied - relaunching...' -ForegroundColor Green
    Wait-ConnectExit -Reason 'update_manual_relaunch' -Code 0
}

Set-Content -LiteralPath $exitMarker -Value ("still_alive ec=$ec") -Encoding ASCII
Log 'harness still alive at end'
exit 0
'@ | Set-Content -LiteralPath $harness -Encoding UTF8

Write-Host '  ----  starting stale-UI harness (will apply update if behind server)' -ForegroundColor DarkGray

$p = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', $harness,
    '-LiveDir', $live,
    '-MarkerDir', $markerDir
) -PassThru -WindowStyle Normal

$deadline = (Get-Date).AddSeconds(120)
while (-not $p.HasExited -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 400
}
$stillAlive = -not $p.HasExited
if ($stillAlive) {
    try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
}

$pressHit = Test-Path -LiteralPath $pressMarker
$started = Test-Path -LiteralPath $startedMarker
$exitHit = Test-Path -LiteralPath $exitMarker
$logTxt = if (Test-Path $logMarker) { Get-Content -LiteralPath $logMarker -Raw } else { '' }
$liveVerAfter = ''
try { $liveVerAfter = (Get-Content -LiteralPath (Join-Path $live 'connect-version.txt') -Raw).Trim() } catch {}

Write-Host '--- harness log ---'
Write-Host $logTxt
Write-Host ("  ----  harness_alive={0} press_marker={1} exit_marker={2} live_ver={3}" -f $stillAlive, $pressHit, $exitHit, $liveVerAfter)

Assert $started 'harness started'
Assert (-not $pressHit) 'STALE Press Enter path was NOT reached'

$killMarker = Join-Path $env:TEMP 'claude-connect-kill-self.marker'
$killSelfMarker = Test-Path -LiteralPath $killMarker
if ($killSelfMarker) {
    Write-Host ("  ----  kill-self marker: {0}" -f (Get-Content -LiteralPath $killMarker -Raw)) -ForegroundColor DarkGray
}
$day = Get-Date -Format 'yyyyMMdd'
$dayLog = Join-Path $env:USERPROFILE ".config\claude-connect\logs\connect-$day.log"
$killSelfLog = $false
if (Test-Path $dayLog) {
    $tail = @(Select-String -Path $dayLog -Pattern 'kill_self skip_stale_press_enter|bat_relaunch_from_update_self' | Select-Object -Last 15)
    foreach ($t in $tail) { Write-Host ("  LOG  {0}" -f $t.Line) -ForegroundColor DarkGray }
    $killSelfLog = ($tail.Count -gt 0)
}

$returnedToHarness = ($logTxt -match 'connect-update returned ec=')
$killSelf = $killSelfMarker -or $killSelfLog
$applied = $killSelf -or (($liveVerAfter -match '^\d{8}\.\d+$') -and -not $returnedToHarness -and -not $stillAlive -and -not $exitHit)

if ($killSelf -or $applied) {
    Assert $killSelf 'kill_self proven (temp marker and/or day log)'
    Assert (-not $exitHit) 'harness did not reach end after apply (killed before stale prompt)'
    Assert (-not $stillAlive) 'harness process exited/killed after apply'
    Assert (-not $returnedToHarness) 'connect-update did not return to stale caller after apply'
} else {
    Assert $false 'hard test requires real apply + kill_self (set local behind server)'
}

try { Remove-Item -LiteralPath $markerDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}

Write-Host ''
Write-Host ("RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor $(if ($Fail -eq 0) { 'Green' } else { 'Red' })
if ($Fail -gt 0) { exit 1 }
exit 0
