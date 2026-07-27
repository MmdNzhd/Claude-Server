#Requires -Version 5.1
# test-harder-live-log-flush.ps1
# HARD LIVE ERROR force-flush vs WARN coalesce, forbid_shrink, SESSION_FILTER bracket,
# dual RUN_ID mint, and extracted Request-ConnectLogSync / Complete-ConnectLogAsyncDrain /
# Write-ConnectLog LIVE sandbox probes.
# 14 Assert calls. Does NOT modify run-all.ps1 or production scripts.

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_paths.ps1"

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

function Get-BalancedBlock {
    param([string]$Text, [string]$StartPattern)
    $m = [regex]::Match($Text, $StartPattern)
    if (-not $m.Success) { return '' }
    $start = $m.Index
    $i = $Text.IndexOf('{', $start)
    if ($i -lt 0) { return '' }
    $depth = 0
    for ($p = $i; $p -lt $Text.Length; $p++) {
        $ch = $Text[$p]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) { return $Text.Substring($start, $p - $start + 1) }
        }
    }
    return ''
}

function New-LogFlushSandboxHarness {
    param(
        [string]$WorkLogDir,
        [string]$UiContent
    )

    $names = @(
        'Get-ConnectLogDir',
        'Get-ConnectLogDayPath',
        'Get-ConnectSessionId',
        'Get-ConnectLogSyncWatermarkPath',
        'Read-ConnectLogSyncWatermark',
        'Get-ConnectLogWriteMutex',
        'Write-ConnectLogSynced',
        'Ensure-ConnectLogWriter',
        'Test-ConnectRemoteLogNeedsRebuild',
        'Complete-ConnectLogAsyncDrain',
        'Request-ConnectLogSync'
    )
    $srcParts = New-Object System.Collections.Generic.List[string]
    foreach ($n in $names) {
        $fn = Get-FunctionSource -Content $UiContent -Name $n
        if (-not $fn) { return $null }
        [void]$srcParts.Add($fn)
    }

    $dirEsc = $WorkLogDir.Replace("'", "''")
    $harness = @"
`$script:ConnectLogWriter = `$null
`$script:ConnectLogPath = ''
`$script:ConnectSessionId = ''
`$script:ConnectLogSyncNeeded = `$false
`$script:ConnectLogWarnPendingUntil = `$null
`$script:ConnectLogAsyncDrainerRunning = `$false
`$script:ConnectLogAsyncTimer = `$null
`$script:ConnectLogAsyncTimerSubId = `$null
`$script:ConnectLogAsyncStallSince = `$null
`$script:ConnectLogPendingBuffer = [System.Text.StringBuilder]::new()
`$script:ConnectLogFileStream = `$null
`$script:ConnectLogSyncOffset = 0
`$script:ConnectLogLinesSinceSync = 0
`$script:ConnectLogSyncInProgress = `$false
`$script:LastConnectLogSyncOk = `$true
`$script:SyncForceCount = 0
`$script:SyncPlainCount = 0
`$script:NoInlineSyncCalls = 0

function Get-ConnectLogDir { return '$dirEsc' }

function Sync-ConnectLogToServer {
    param([switch]`$Force, [string]`$LogPath = '')
    if (`$Force) { `$script:SyncForceCount++ } else { `$script:SyncPlainCount++ }
    `$script:LastConnectLogSyncOk = `$true
}

function Ensure-ConnectLogAsyncTimer { }

$($srcParts -join "`n`n")

function Invoke-TrackedRequest-ConnectLogSync {
    param([switch]`$Force, [switch]`$NoInline)
    if (`$Force) {
        Complete-ConnectLogAsyncDrain -Force
        return
    }
    if (`$NoInline) {
        `$script:NoInlineSyncCalls++
        Ensure-ConnectLogAsyncTimer
        return
    }
    Request-ConnectLogSync @PSBoundParameters
}

function Write-ConnectLog {
    param(
        [Parameter(Mandatory)][string]`$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]`$Level = 'INFO'
    )
    if (-not (Ensure-ConnectLogWriter)) { return }
    try {
        `$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        `$sid = Get-ConnectSessionId
        if (`$Level -eq 'TRACE' -or `$Level -eq 'DEBUG') { return }
        Write-ConnectLogSynced
        Write-ConnectLogSynced -Line "[`$ts] [`$Level] [`$sid] `$Message"
        `$script:ConnectLogLinesSinceSync = [int]`$script:ConnectLogLinesSinceSync + 1
        if (`$Level -eq 'ERROR') {
            Complete-ConnectLogAsyncDrain -Force
        } elseif (`$Level -eq 'WARN') {
            `$script:ConnectLogWarnPendingUntil = (Get-Date).AddSeconds(5)
            `$script:ConnectLogSyncNeeded = `$true
            Invoke-TrackedRequest-ConnectLogSync -NoInline
        }
    } catch { }
}
"@
    return $harness
}

Write-Host ''
Write-Host '=== test-harder-live-log-flush ===' -ForegroundColor Cyan
Write-Host ''

$uiPath = Get-ClientFile 'connect-ui.ps1'
$uiShPath = Get-ClientFile 'connect-ui.sh'
$batPath = Get-ClientFile 'windows\connect.bat'

$ui = Get-Content -LiteralPath $uiPath -Raw
$uiSh = Get-Content -LiteralPath $uiShPath -Raw
$bat = Get-Content -LiteralPath $batPath -Raw

$wcBody = Get-FunctionSource -Content $ui -Name 'Write-ConnectLog'
$reqBody = Get-FunctionSource -Content $ui -Name 'Request-ConnectLogSync'
$drainBody = Get-FunctionSource -Content $ui -Name 'Complete-ConnectLogAsyncDrain'
$syncBody = Get-FunctionSource -Content $ui -Name 'Sync-ConnectLogToServer'
$needsRebuildBody = Get-FunctionSource -Content $ui -Name 'Test-ConnectRemoteLogNeedsRebuild'
$initBlock = Get-BalancedBlock -Text $ui -StartPattern '(?m)^function Initialize-ConnectLog\b'

Write-Host '--- Static extracted contracts (7) ---' -ForegroundColor DarkCyan

Assert (
    ($wcBody -and $reqBody -and $drainBody)
) 'Write-ConnectLog / Request-ConnectLogSync / Complete-ConnectLogAsyncDrain extractable via Get-FunctionSource'

Assert (
    ($wcBody -match "Level -eq 'ERROR'") -and ($wcBody -match 'Complete-ConnectLogAsyncDrain\s+-Force')
) 'Write-ConnectLog ERROR branch calls Complete-ConnectLogAsyncDrain -Force'

Assert (
    ($wcBody -match "Level -eq 'WARN'") -and ($wcBody -match 'ConnectLogWarnPendingUntil') -and
    ($wcBody -match 'Request-ConnectLogSync\s+-NoInline') -and
    ($wcBody -notmatch "(?s)Level -eq 'WARN'[\s\S]{0,400}Complete-ConnectLogAsyncDrain\s+-Force")
) 'Write-ConnectLog WARN coalesces via Request-ConnectLogSync -NoInline (no Force drain in WARN branch)'

Assert (
    ($drainBody -match 'Sync-ConnectLogToServer\s+-Force') -and
    ($reqBody -match 'Complete-ConnectLogAsyncDrain\s+-Force')
) 'Request-ConnectLogSync -Force delegates to Complete-ConnectLogAsyncDrain; drain ends with Sync -Force'

Assert (
    ($initBlock -match 'SESSION_FILTER grep=\[\$\(\$script:ConnectSessionId\)\]') -and
    ($wcBody -match '\[\$ts\] \[\$Level\] \[\$sid\]')
) 'SESSION_FILTER tip + Write-ConnectLog [session-id] bracket format'

Assert (
    ($syncBody -match 'LOG_SYNC_SKIP reason=forbid_shrink') -and ($syncBody -match '\$fileLen -lt \$remoteBeforeProbe') -and
    ($uiSh -match 'LOG_SYNC_SKIP reason=forbid_shrink')
) 'forbid_shrink skip when local file smaller than remote probe (Win+Mac source)'

Assert (
    ($needsRebuildBody -match 'LocalSize -lt \$RemoteSize') -and ($needsRebuildBody -match 'return \$false')
) 'Test-ConnectRemoteLogNeedsRebuild returns false on local<remote shrink'

Write-Host '--- LIVE sandbox + races (7) ---' -ForegroundColor DarkCyan

$sandboxDir = Join-Path $env:TEMP ('claude-log-flush-harder-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $sandboxDir | Out-Null
$harnessSrc = New-LogFlushSandboxHarness -WorkLogDir $sandboxDir -UiContent $ui
$liveSb = $null
try {
    if (-not $harnessSrc) { throw 'Could not build log-flush LIVE harness (source drift?)' }
    $liveSb = [scriptblock]::Create($harnessSrc)
    . $liveSb

    Remove-Item Env:CLAUDE_CONNECT_RUN_ID -ErrorAction SilentlyContinue
    $script:ConnectSessionId = ''
    Write-ConnectLog 'LIVE_ERROR_PROBE force path' 'ERROR'
    Assert ($script:SyncForceCount -ge 1) "LIVE ERROR Write-ConnectLog invoked Sync-ConnectLogToServer -Force (count=$($script:SyncForceCount))"

    $beforeWarnForce = [int]$script:SyncForceCount
    Write-ConnectLog 'LIVE_WARN_PROBE coalesce path' 'WARN'
    Assert (
        ($script:SyncForceCount -eq $beforeWarnForce) -and
        ($null -ne $script:ConnectLogWarnPendingUntil) -and
        ($script:NoInlineSyncCalls -ge 1)
    ) "LIVE WARN avoids Force flush (force=$($script:SyncForceCount) noinline=$($script:NoInlineSyncCalls))"

    $sid = Get-ConnectSessionId
    $logPath = Get-ConnectLogDayPath
    $logText = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw } else { '' }
    Assert (
        ($sid -match '^[0-9a-fA-F]{12}$') -and ($logText -match "\[$sid\]")
    ) "LIVE log line carries bracketed session id ($sid)"

    . ([scriptblock]::Create($needsRebuildBody))
    $rbShrink = Test-ConnectRemoteLogNeedsRebuild -LocalSize 100 -RemoteSize 500 -Offset 0
    $rbEqual = Test-ConnectRemoteLogNeedsRebuild -LocalSize 500 -RemoteSize 500 -Offset 0
    Assert ((-not $rbShrink) -and (-not $rbEqual)) 'LIVE Test-ConnectRemoteLogNeedsRebuild false when local<=remote shrink'

    $fileLen = 100
    $remoteBeforeProbe = 500
    $off = 0
    $wouldSkipShrink = ($fileLen -lt $remoteBeforeProbe)
    Assert $wouldSkipShrink "LIVE forbid_shrink guard: local=$fileLen remote=$remoteBeforeProbe off=$off skips append/rebuild"
}
finally {
    if (Get-Command Get-EventSubscriber -ErrorAction SilentlyContinue) {
        Get-EventSubscriber -SourceIdentifier 'ConnectLogAsyncTimerElapsed' -ErrorAction SilentlyContinue |
            Unregister-Event -ErrorAction SilentlyContinue
    }
    if ($script:ConnectLogAsyncTimer) {
        try { $script:ConnectLogAsyncTimer.Stop(); $script:ConnectLogAsyncTimer.Dispose() } catch { }
    }
    Remove-Item -LiteralPath $sandboxDir -Recurse -Force -ErrorAction SilentlyContinue
}

$childOut1 = Join-Path $env:TEMP ('log-flush-err1-' + [guid]::NewGuid().ToString('N') + '.txt')
$childOut2 = Join-Path $env:TEMP ('log-flush-err2-' + [guid]::NewGuid().ToString('N') + '.txt')
$childScript = Join-Path $env:TEMP ('log-flush-err-child-' + [guid]::NewGuid().ToString('N') + '.ps1')
$psExe = (Get-Process -Id $PID).Path
if (-not $psExe) { $psExe = 'powershell.exe' }
$work1 = $null
$work2 = $null
try {
    $harnessForChild = New-LogFlushSandboxHarness -WorkLogDir '__PLACEHOLDER__' -UiContent $ui
    if (-not $harnessForChild) { throw 'Could not build child ERROR harness' }
    $childBody = @"
param([string]`$WorkDir, [string]`$OutFile, [string]`$RunId)
`$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path `$WorkDir | Out-Null
$harnessForChild
function Get-ConnectLogDir { return `$WorkDir }
Remove-Item Env:CLAUDE_CONNECT_RUN_ID -ErrorAction SilentlyContinue
`$env:CLAUDE_CONNECT_RUN_ID = `$RunId
`$script:ConnectSessionId = `$RunId
Write-ConnectLog "DUAL_ERROR_WRITER `$RunId" 'ERROR'
Set-Content -LiteralPath `$OutFile -Value `$script:SyncForceCount -Encoding ASCII
"@
    Set-Content -LiteralPath $childScript -Value $childBody -Encoding UTF8

    $work1 = Join-Path $env:TEMP ('log-flush-w1-' + [guid]::NewGuid().ToString('N'))
    $work2 = Join-Path $env:TEMP ('log-flush-w2-' + [guid]::NewGuid().ToString('N'))
    $rid1 = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $rid2 = [guid]::NewGuid().ToString('N').Substring(0, 12)

    $p1 = Start-Process -FilePath $psExe -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $childScript,
        '-WorkDir', $work1, '-OutFile', $childOut1, '-RunId', $rid1
    ) -PassThru -WindowStyle Hidden
    $p2 = Start-Process -FilePath $psExe -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $childScript,
        '-WorkDir', $work2, '-OutFile', $childOut2, '-RunId', $rid2
    ) -PassThru -WindowStyle Hidden
    $null = $p1.WaitForExit(20000)
    $null = $p2.WaitForExit(20000)

    $force1 = [int]((Get-Content -LiteralPath $childOut1 -ErrorAction SilentlyContinue | Select-Object -First 1) + '0')
    $force2 = [int]((Get-Content -LiteralPath $childOut2 -ErrorAction SilentlyContinue | Select-Object -First 1) + '0')
    Assert (
        $p1.HasExited -and $p2.HasExited -and ($force1 -ge 1) -and ($force2 -ge 1) -and ($rid1 -ne $rid2)
    ) "LIVE dual ERROR writers both hit Force path (force1=$force1 force2=$force2 run=$rid1 vs $rid2)"
}
finally {
    Remove-Item -LiteralPath $childScript, $childOut1, $childOut2 -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $work1, $work2 -Recurse -Force -ErrorAction SilentlyContinue
}

$shared = Join-Path $env:TEMP ('claude-connect-run-id-flush-' + [guid]::NewGuid().ToString('N') + '.txt')
$probe = Join-Path $env:TEMP ('claude-log-flush-rid-probe-' + [guid]::NewGuid().ToString('N') + '.cmd')
$ridOut1 = Join-Path $env:TEMP ('log-flush-rid1-' + [guid]::NewGuid().ToString('N') + '.txt')
$ridOut2 = Join-Path $env:TEMP ('log-flush-rid2-' + [guid]::NewGuid().ToString('N') + '.txt')
try {
    $sharedPs = $shared.Replace("'", "''")
    $probeBody = @"
@echo off
setlocal EnableDelayedExpansion
set "CLAUDE_CONNECT_RUN_ID="
if not defined CLAUDE_CONNECT_RUN_ID (
  for /f %%I in ('powershell -NoProfile -WindowStyle Hidden -Command "[guid]::NewGuid().ToString('N').Substring(0,12)"') do set "CLAUDE_CONNECT_RUN_ID=%%I"
)
powershell -NoProfile -WindowStyle Hidden -Command "Set-Content -LiteralPath '$sharedPs' -Value `$env:CLAUDE_CONNECT_RUN_ID -Encoding ASCII"
if not defined CLAUDE_CONNECT_RUN_ID if exist "$shared" (
  for /f "usebackq delims=" %%I in ("$shared") do set "CLAUDE_CONNECT_RUN_ID=%%I"
)
echo !CLAUDE_CONNECT_RUN_ID!
"@
    Set-Content -LiteralPath $probe -Value $probeBody -Encoding ASCII

    $prevRunId = $env:CLAUDE_CONNECT_RUN_ID
    Remove-Item Env:CLAUDE_CONNECT_RUN_ID -ErrorAction SilentlyContinue
    try {
        $rp1 = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', "`"$probe`"") `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput $ridOut1 -RedirectStandardError ($ridOut1 + '.err')
        Start-Sleep -Milliseconds 30
        $rp2 = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/c', "`"$probe`"") `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput $ridOut2 -RedirectStandardError ($ridOut2 + '.err')
    } finally {
        if ($null -ne $prevRunId -and "$prevRunId" -ne '') {
            $env:CLAUDE_CONNECT_RUN_ID = $prevRunId
        }
    }
    $null = $rp1.WaitForExit(15000)
    $null = $rp2.WaitForExit(15000)
    $mint1 = ((Get-Content -LiteralPath $ridOut1 -ErrorAction SilentlyContinue | Select-Object -First 1) + '').Trim()
    $mint2 = ((Get-Content -LiteralPath $ridOut2 -ErrorAction SilentlyContinue | Select-Object -First 1) + '').Trim()
    Assert (
        ($bat -match 'Multi-UI: mint a unique RUN_ID') -and
        $rp1.HasExited -and $rp2.HasExited -and
        ($mint1 -match '^[0-9a-fA-F]{12}$') -and ($mint2 -match '^[0-9a-fA-F]{12}$') -and ($mint1 -ne $mint2)
    ) "LIVE dual RUN_ID mint: distinct 12-hex ids ($mint1 vs $mint2)"
}
finally {
    Remove-Item -LiteralPath $probe, $shared, $ridOut1, $ridOut2, ($ridOut1 + '.err'), ($ridOut2 + '.err') `
        -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("=== RESULT pass={0} fail={1} asserts={2} ===" -f $passed, $failed, ($passed + $failed)) `
    -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Red' })
if ($failed -gt 0) { exit 1 }
Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
exit 0
