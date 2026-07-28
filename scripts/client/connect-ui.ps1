# connect-ui.ps1 - terminal UI helpers (dot-sourced by connect.ps1)
# Requires: Warn, Step helpers may exist in parent scope

$script:ConnectLogWriter = $null
$script:ConnectLogPath = ''
$script:LastSessionStatusKey = ''
$script:LastHeartbeatUnix = 0
$script:ConnectUiReady = $false
$script:ConnectSessionId = ''
$script:ConnectLogSyncNeeded = $false
$script:ConnectLogWarnPendingUntil = $null
$script:ConnectLogAsyncDrainerRunning = $false
$script:ConnectLogAsyncTimer = $null
$script:ConnectLogAsyncTimerSubId = $null
$script:ConnectLogAsyncStallSince = $null
# Bug 6: TRACE/DEBUG hot-loop lines accumulate here (in-process only) instead of the
# long-lived StreamWriter's own internal buffer - see Write-ConnectLogSynced for why the
# actual physical write no longer goes through that stream's cached position.
$script:ConnectLogPendingBuffer = [System.Text.StringBuilder]::new()
$script:LastAgentPathUnix = 0
$script:LastAgentPathResult = $null  # hashtable for SCORECARD reuse

function Get-ConnectLogDir {
    $dir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch { }
    return $dir
}

function Get-ConnectLogDayPath {
    $day = Get-Date -Format 'yyyyMMdd'
    return (Join-Path (Get-ConnectLogDir) ("connect-{0}.log" -f $day))
}

function Clear-ConnectLocalLogsOlderThan {
    # Parity with server claude-connect-logs-cleanup: drop local day logs older than 1 day.
    param([int]$Days = 1)
    try {
        $dir = Get-ConnectLogDir
        if (-not (Test-Path -LiteralPath $dir)) { return }
        $cutoff = (Get-Date).AddDays(-[Math]::Max(1, $Days))
        Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'sessions.index' -and $_.LastWriteTime -lt $cutoff } |
            ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
    } catch { }
}


function Get-ConnectSessionIndexPath {
    return (Join-Path (Get-ConnectLogDir) 'sessions.index')
}

function Get-ConnectSessionId {
    if ($script:ConnectSessionId -and $script:ConnectSessionId.Trim().Length -ge 8) {
        $script:ConnectSessionId = $script:ConnectSessionId.Trim()
    } elseif ($env:CLAUDE_CONNECT_RUN_ID -and $env:CLAUDE_CONNECT_RUN_ID.Trim().Length -ge 8) {
        $script:ConnectSessionId = $env:CLAUDE_CONNECT_RUN_ID.Trim()
    } else {
        $script:ConnectSessionId = [guid]::NewGuid().ToString('N').Substring(0, 12)
    }
    $env:CLAUDE_CONNECT_RUN_ID = $script:ConnectSessionId
    return $script:ConnectSessionId
}

function Write-ConnectSessionIndex {
    param(
        [Parameter(Mandatory)][string]$Phase,
        [string]$Project = '-'
    )
    try {
        $idx = Get-ConnectSessionIndexPath
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = Get-ConnectSessionId
        $hostName = try { [System.Net.Dns]::GetHostName() } catch { $env:COMPUTERNAME }
        $ver = if ($script:ConnectVersion) { $script:ConnectVersion } else { '-' }
        if ($Project -eq '-' -and $script:ActiveProjectId) { $Project = $script:ActiveProjectId }
        elseif ($Project -eq '-' -and $script:ActiveMountId) { $Project = $script:ActiveMountId }
        $projSafe = (($Project + '') -replace "`t", ' ').Trim()
        if (-not $projSafe) { $projSafe = '-' }
        $line = "{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`n" -f $ts, $sid, $PID, $env:USERNAME, $hostName, $ver, $Phase
        [System.IO.File]::AppendAllText($idx, $line, [System.Text.UTF8Encoding]::new($false))
    } catch { }
}

function Get-ConnectLogSyncWatermarkPath {
    param([string]$LogPath = $script:ConnectLogPath)
    if (-not $LogPath) { $LogPath = Get-ConnectLogDayPath }
    return ($LogPath + '.sync-offset')
}

function Read-ConnectLogSyncWatermark {
    param([string]$LogPath = $script:ConnectLogPath)
    $wp = Get-ConnectLogSyncWatermarkPath -LogPath $LogPath
    try {
        if (Test-Path -LiteralPath $wp) {
            $raw = ((Get-Content -LiteralPath $wp -Raw -ErrorAction SilentlyContinue) + '').Trim()
            $n = 0
            if ([int]::TryParse($raw, [ref]$n) -and $n -ge 0) { return $n }
        }
    } catch { }
    return 0
}

function Write-ConnectLogSyncWatermark {
    param([int]$Offset, [string]$LogPath = $script:ConnectLogPath)
    try {
        Set-Content -LiteralPath (Get-ConnectLogSyncWatermarkPath -LogPath $LogPath) -Value "$Offset" -Encoding ASCII -NoNewline -ErrorAction SilentlyContinue
    } catch { }
}

function Get-ConnectLogSyncPendingPath {
    param([string]$LogPath = $script:ConnectLogPath)
    if (-not $LogPath) { $LogPath = Get-ConnectLogDayPath }
    return ($LogPath + '.sync-pending')
}

function Clear-ConnectLogSyncPending {
    param([string]$LogPath = $script:ConnectLogPath)
    try {
        $pp = Get-ConnectLogSyncPendingPath -LogPath $LogPath
        if (Test-Path -LiteralPath $pp) { Remove-Item -LiteralPath $pp -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function Write-ConnectLogSyncPending {
    param(
        [int]$Offset,
        [int]$Take,
        [int64]$RemoteBefore,
        [string]$LogPath = $script:ConnectLogPath
    )
    try {
        $line = '{0}|{1}|{2}' -f $Offset, $Take, $RemoteBefore
        Set-Content -LiteralPath (Get-ConnectLogSyncPendingPath -LogPath $LogPath) -Value $line -Encoding ASCII -NoNewline -ErrorAction SilentlyContinue
    } catch { }
}

function Read-ConnectLogSyncPending {
    param([string]$LogPath = $script:ConnectLogPath)
    try {
        $pp = Get-ConnectLogSyncPendingPath -LogPath $LogPath
        if (-not (Test-Path -LiteralPath $pp)) { return $null }
        $raw = ((Get-Content -LiteralPath $pp -Raw -ErrorAction SilentlyContinue) + '').Trim()
        if ($raw -notmatch '^(\d+)\|(\d+)\|(\d+)$') { return $null }
        return [PSCustomObject]@{
            Offset       = [int]$Matches[1]
            Take         = [int]$Matches[2]
            RemoteBefore = [int64]$Matches[3]
        }
    } catch { return $null }
}

function Get-ConnectRemoteLogByteSize {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Day,
        [string[]]$SshOpts,
        [int]$TimeoutMs = 10000
    )
    # Lightweight remote size probe. -1 = probe failed (do not treat as reconcile success).
    # MUST use timed process: raw & ssh can hang forever and freeze Loading projects
    # when Write-ConnectLog INFO triggers inline Sync-ConnectLogToServer.
    $cmd = 'stat -c%s "$HOME/.claude/logs/connect-' + $Day + '.log" 2>/dev/null || echo 0'
    try {
        $argList = @()
        if ($SshOpts) { $argList += $SshOpts }
        $argList += @('-o', 'ConnectTimeout=6', $Target, $cmd)
        $res = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList $argList -TimeoutMs $TimeoutMs
        if (-not $res.Ok) { return [int64](-1) }
        $raw = ([string]$res.StdOut).Trim()
        $digits = ($raw -replace '[^0-9]', '')
        if (-not $digits) { return [int64](-1) }
        return [int64]$digits
    } catch {
        return [int64](-1)
    }
}


function Test-ConnectRemoteLogNeedsRebuild {
    param(
        [int64]$LocalSize,
        [int64]$RemoteSize,
        [int]$Offset
    )
    # Stage 9: never replace remote day log with a smaller local file (forbid shrink).
    if ($RemoteSize -lt 0) { return $false }
    if ($LocalSize -lt $RemoteSize) { return $false }
    # Prior "bloated remote" triggers all required remote > local Ã¢â‚¬â€ forbidden above.
    # Rebuild remains available only when local >= remote (no shrink); currently unused.
    return $false
}

function Get-ConnectLogUnsyncedByteCount {
    param([string]$LogPath = $script:ConnectLogPath)
    if (-not $LogPath -or -not (Test-Path -LiteralPath $LogPath)) { return [int64]0 }
    try {
        $off = [int64](Read-ConnectLogSyncWatermark -LogPath $LogPath)
        $len = [int64]([System.IO.FileInfo]::new($LogPath).Length)
        if ($off -lt 0) { $off = 0 }
        if ($off -gt $len) { return $len }
        return ($len - $off)
    } catch { return [int64]0 }
}

function Test-ConnectLogChunkAlreadyRemote {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Day,
        [Parameter(Mandatory)][byte[]]$Chunk,
        [Parameter(Mandatory)][int]$Take,
        [string[]]$SshOpts,
        [int]$TimeoutMs = 12000
    )
    # Idempotency: if remote tail bytes match the chunk we are about to send, skip append.
    if ($Take -le 0 -or $Take -gt 524288) { return $false }
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $localHash = ([BitConverter]::ToString($sha.ComputeHash($Chunk))).Replace('-', '').ToLowerInvariant()
        } finally { $sha.Dispose() }
    } catch { return $false }
    $cmd = 'f="$HOME/.claude/logs/connect-' + $Day + '.log"; if [ ! -f "$f" ]; then echo none; exit 0; fi; sz=$(stat -c%s "$f" 2>/dev/null || echo 0); if [ "$sz" -lt ' + $Take + ' ]; then echo short; exit 0; fi; tail -c ' + $Take + ' "$f" | sha256sum | awk ''{print $1}'''
    try {
        $argList = @()
        if ($SshOpts) { $argList += $SshOpts }
        $argList += @('-o', 'ConnectTimeout=8', $Target, $cmd)
        $res = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList $argList -TimeoutMs $TimeoutMs
        if (-not $res.Ok) { return $false }
        $raw = ([string]$res.StdOut).Trim().ToLowerInvariant()
        $remoteHash = ($raw -replace '[^0-9a-f]', '')
        if ($remoteHash.Length -ge 64) { $remoteHash = $remoteHash.Substring(0, 64) }
        return ($remoteHash -eq $localHash)
    } catch { return $false }
}



function Get-ConnectLogSyncTarget {
    # Prefer SSH Host alias when ready; else REMOTE_USER@ServerIP so early UPDATE/BOOTSTRAP can ship.
    if ($Alias) { return $Alias }
    try {
        $ru = $null; $sip = $null
        if ($RemoteUser) { $ru = $RemoteUser }
        if ($ServerIP) { $sip = $ServerIP }
        if (-not $ru -or -not $sip) {
            $cfg = Join-Path $env:USERPROFILE '.config\claude-connect\connect.conf'
            if (Test-Path -LiteralPath $cfg) {
                foreach ($line in Get-Content -LiteralPath $cfg -ErrorAction SilentlyContinue) {
                    if (-not $ru -and $line -match '^\s*REMOTE_USER=(.+)$') { $ru = $Matches[1].Trim() }
                    if (-not $sip -and $line -match '^\s*SERVER_IP=(.+)$') { $sip = $Matches[1].Trim() }
                }
            }
        }
        if (-not $sip -and (Get-Command Get-LocalServerIp -ErrorAction SilentlyContinue)) {
            $sip = Get-LocalServerIp
        }
        if ($ru -and $sip -and ($ru -notmatch '[@/\\]')) { return ("{0}@{1}" -f $ru, $sip) }
    } catch { }
    return ''
}


function Enter-ConnectSingleInstance {
    # Up to 10 Connect UIs per machine (Global\ClaudeConnect#0 .. #9).
    param([string]$Name = '')
    $maxUi = 10
    if ($env:CLAUDE_CONNECT_BOOT_MUTEX -eq '1' -and $global:ClaudeConnectBootMutex) {
        $script:ConnectInstanceMutex = $global:ClaudeConnectBootMutex
        $global:ClaudeConnectBootMutex = $null
        $slot = ($env:CLAUDE_CONNECT_UI_SLOT + '').Trim()
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("MULTI_INSTANCE: acquired pid={0} via=connect-boot slot={1}" -f $PID, $slot) 'INFO'
        }
        return $true
    }
    $script:ConnectInstanceMutex = $null
    try {
        for ($i = 0; $i -lt $maxUi; $i++) {
            $slotName = "Global\ClaudeConnect#$i"
            $created = $false
            $m = $null
            try {
                $m = New-Object System.Threading.Mutex($false, $slotName, [ref]$created)
            } catch { continue }
            $got = $false
            try {
                try { $got = $m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
            } catch {
                try { $m.Dispose() } catch { }
                continue
            }
            if ($got) {
                $script:ConnectInstanceMutex = $m
                $env:CLAUDE_CONNECT_UI_SLOT = [string]$i
                if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                    Write-ConnectLog ("MULTI_INSTANCE: acquired pid={0} slot={1}" -f $PID, $i) 'INFO'
                }
                return $true
            }
            try { $m.Dispose() } catch { }
        }
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("MULTI_INSTANCE: blocked pid={0} reason=all_slots_busy max={1}" -f $PID, $maxUi) 'ERROR'
        }
        Write-Host ''
        Write-Host '  [X] 10 Claude Connect windows already open - close one, then retry.' -ForegroundColor Red
        Write-Host ''
        return $false
    } catch {
        $script:ConnectInstanceMutex = $null
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("MULTI_INSTANCE: mutex error (block): {0}" -f $_.Exception.Message) 'ERROR'
        }
        Write-Host ''
        Write-Host '  [X] Could not acquire Connect lock - close other Claude Connect windows.' -ForegroundColor Red
        Write-Host ''
        return $false
    }
}
function Exit-ConnectSingleInstance {
    try {
        if ($script:ConnectInstanceMutex) {
            try { $script:ConnectInstanceMutex.ReleaseMutex() } catch { }
            try { $script:ConnectInstanceMutex.Close() } catch { }
            $script:ConnectInstanceMutex = $null
        }
    } catch { }
}

function Initialize-ConnectLog {
    param(
        [Parameter(Mandatory)][string]$ScriptDir,
        [string]$Version = ''
    )
    # Zero-loss offline-first (industry pattern):
    # 1) Always append durable local day file
    # 2) Watermark sync-offset so BOOTSTRAP/UPDATE lines written before this process still ship
    # 3) Batch-flush to server ~/.claude/logs when SSH works
    # 4) Retention mtime +1 on laptop + server (purge on connect start / sync flush / server cron)
    Clear-ConnectLocalLogsOlderThan -Days 1
    try {
        $legacy = Join-Path $ScriptDir 'connect.log'
        if (Test-Path -LiteralPath $legacy) { Remove-Item -LiteralPath $legacy -Force -ErrorAction SilentlyContinue }
        $legacy1 = Join-Path $ScriptDir 'connect.log.1'
        if (Test-Path -LiteralPath $legacy1) { Remove-Item -LiteralPath $legacy1 -Force -ErrorAction SilentlyContinue }
    } catch { }
    $null = Get-ConnectSessionId
    $script:ConnectLogPath = Get-ConnectLogDayPath
    $script:ConnectLogSyncOffset = Read-ConnectLogSyncWatermark -LogPath $script:ConnectLogPath
    $script:ConnectLogLinesSinceSync = 0
    $script:ConnectLogSyncNeeded = $false
    $script:ConnectLogWarnPendingUntil = $null
    $script:ConnectLogAsyncDrainerRunning = $false
    $script:ConnectLogAsyncStallSince = $null
    try {
        # FileShare.ReadWrite: second connect (or leftover session) must not silently disable logging.
        $fs = [System.IO.FileStream]::new(
            $script:ConnectLogPath,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite)
        # Bug 6 fix: register the FileStream so Write-ConnectLogSynced (the mutex-protected
        # writer below) can re-seek to the TRUE current end-of-file before every flush.
        # FileMode.Append only seeks to EOF once, at construction time - without this
        # assignment (the gap that made the concurrent-writer corruption still reproducible
        # even after Write-ConnectLogSynced/Get-ConnectLogWriteMutex were added), this
        # process's own writer never re-syncs its write position to what other concurrent
        # connect.ps1 processes have already appended, so mutex-serialized flushes still
        # land at a stale offset and corrupt/overwrite each other's bytes.
        $script:ConnectLogFileStream = $fs
        $script:ConnectLogWriter = [System.IO.StreamWriter]::new($fs, [System.Text.UTF8Encoding]::new($false))
        $script:ConnectLogWriter.AutoFlush = $true
    } catch {
        $script:ConnectLogWriter = $null
        $script:ConnectLogFileStream = $null
        try { Write-Host ("[WARN] connect log open failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow } catch { }
        return
    }
    $elev = 'unknown'
    if (Get-Command Test-IsElevatedShell -ErrorAction SilentlyContinue) {
        $elev = if (Test-IsElevatedShell) { 'yes' } else { 'no' }
    }
    Write-ConnectLog "======== session start v$Version user=$env:USERNAME elevated=$elev pid=$PID session=$($script:ConnectSessionId) ========"
    Write-ConnectLog "SESSION_FILTER grep=[$($script:ConnectSessionId)] tip=Select-String -Pattern '\[$($script:ConnectSessionId)\]'"
    Write-ConnectLog "log sink: local:$($script:ConnectLogPath) watermark=$($script:ConnectLogSyncOffset) + server:~/.claude/logs/ (local+server purge mtime+1)"
    Write-ConnectLog "script_dir: $ScriptDir connect_version: $Version" 'DEBUG'
    Write-ConnectSessionIndex -Phase 'start'
    $script:ConnectUiReady = $true
}


function Invoke-ConnectLogProcTimed {
    param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [int]$TimeoutMs = 15000
    )
    # Raw Process/ProcessStartInfo, not Start-Process -PassThru: on this PS5.1 build,
    # Start-Process -PassThru (without -Wait) returns a Process object whose .ExitCode is
    # unreliable/null even after WaitForExit() succeeds and HasExited is True - confirmed and
    # fixed the same day in the scp-push path (Initialize-ServerSession). Without this fix,
    # `$ec` here silently stayed at its 0 default forever, so every log-sync mkdir/scp/cat
    # always reported Ok=true regardless of whether it actually succeeded (only an outright
    # timeout was ever detected as failure).
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $outFile = Join-Path $env:TEMP ("claude-logsync-$id.out")
    $errFile = Join-Path $env:TEMP ("claude-logsync-$id.err")
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $psi.Arguments = (Format-ProcessArgumentString -ArgumentList $ArgumentList)
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch { }
            return @{ Ok = $false; TimedOut = $true; ExitCode = -1; StdOut = ''; StdErr = '' }
        }
        $ec = $p.ExitCode
        $stdout = ''
        $stderr = ''
        try { $stdout = [string]$outTask.Result } catch { $stdout = '' }
        try { $stderr = [string]$errTask.Result } catch { $stderr = '' }
        try { [System.IO.File]::WriteAllText($outFile, $stdout) } catch { }
        try { [System.IO.File]::WriteAllText($errFile, $stderr) } catch { }
        return @{ Ok = ($ec -eq 0); TimedOut = $false; ExitCode = $ec; StdOut = $stdout; StdErr = $stderr }
    } finally {
        foreach ($f in @($outFile, $errFile)) {
            if (-not $f) { continue }
            try {
                if (Test-Path -LiteralPath $f) {
                    Remove-Item -LiteralPath $f -Force -ErrorAction Stop
                }
            } catch {
                try {
                    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                    $sid = Get-ConnectSessionId
                    if ($script:ConnectLogWriter) {
                        Write-ConnectLogSynced -Line "[$ts] [WARN] [$sid] TEMP_CLEANUP_FAIL path=$f err=$($_.Exception.Message)"
                    }
                } catch { }
            }
        }
    }
}

function Sync-ConnectLogToServer {
    param(
        [switch]$Force,
        [string]$LogPath = ''
    )
    # Never emit True/False to pipeline (was printing "False" in the connect UI).
    $script:LastConnectLogSyncOk = $false
    $path = if ($LogPath) { $LogPath } else { $script:ConnectLogPath }
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return }
    $target = Get-ConnectLogSyncTarget
    if (-not $target) { return }

    # #P7: this function was observed blocking the interactive boot path for 30-60s+ when
    # the mkdir/scp/cat probe chain below hit real (not just theoretical) SSH timeouts back
    # to back - each sub-call had its own multi-second-to-20s timeout and they run strictly
    # sequentially, so a single degraded-network sync attempt could eat a minute of wall
    # clock before "Connecting..."/"Server setup" even had a chance to run. Best-effort log
    # delivery must never cost more than a small, bounded slice of boot time: non-Force
    # attempts now use short per-call timeouts (defer + retry later via the existing async
    # timer is always safe - it is telemetry, not functional state). -Force keeps the
    # original longer budgets since it only fires at rare, important moments (day rollover,
    # unhandled-error flush, final exit) where actually landing the bytes matters more than
    # speed.
    $script:LogSyncFastProbeMs = if ($Force) { 10000 } else { 2500 }
    $script:LogSyncFastChunkMs = if ($Force) { 12000 } else { 2500 }
    $script:LogSyncFastMkdirMs = if ($Force) { 12000 } else { 3000 }
    $script:LogSyncFastScpMs   = if ($Force) { 20000 } else { 4000 }
    $script:LogSyncFastCatMs   = if ($Force) { 12000 } else { 3000 }

    # Bug 72: serialize overlapping syncs (in-process + cross-process lock file).
    if ($script:ConnectLogSyncInProgress -and -not $Force) {
        if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) { $script:ConnectLogSyncNeeded = $true }
        return
    }
    $lockPath = $path + '.sync-lock'
    $lockStream = $null
    try {
        $lockStream = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None)
    } catch {
        if (-not $Force) {
            if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) { $script:ConnectLogSyncNeeded = $true }
            return
        }
        $deadline = (Get-Date).AddSeconds(5)
        while (-not $lockStream -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 150
            try {
                $lockStream = [System.IO.File]::Open(
                    $lockPath,
                    [System.IO.FileMode]::OpenOrCreate,
                    [System.IO.FileAccess]::ReadWrite,
                    [System.IO.FileShare]::None)
            } catch { }
        }
        if (-not $lockStream) { return }
    }
    $script:ConnectLogSyncInProgress = $true
    try {
        if ($script:ConnectLogWriter -and (-not $LogPath -or $LogPath -eq $script:ConnectLogPath)) {
            try { $script:ConnectLogWriter.Flush() } catch { }
        }
        # Re-read watermark under lock to avoid offset-reset races (bug 72).
        $off = [int](Read-ConnectLogSyncWatermark -LogPath $path)
        if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) {
            $script:ConnectLogSyncOffset = $off
        }
        # W3: chunked FileStream read (avoid loading entire day log into memory).
        $maxChunk = 512KB
        $fileLen = [int64]0
        $take = 0
        $chunk = $null
        $fsRead = $null
        try {
            $fsRead = [System.IO.File]::Open(
                $path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite)
            $fileLen = [int64]$fsRead.Length
            if ($off -lt 0) { $off = 0 }
            if ($off -gt $fileLen) { $off = 0 }
            if ($off -ge $fileLen) { $script:LastConnectLogSyncOk = $true; return }
            $remain = $fileLen - $off
            $take = if ($remain -gt $maxChunk) { [int]$maxChunk } else { [int]$remain }
            $null = $fsRead.Seek([int64]$off, [System.IO.SeekOrigin]::Begin)
            $chunk = New-Object byte[] $take
            $got = $fsRead.Read($chunk, 0, $take)
            if ($got -le 0) { $script:LastConnectLogSyncOk = $true; return }
            if ($got -lt $take) {
                $take = $got
                $trimmed = New-Object byte[] $take
                [Array]::Copy($chunk, 0, $trimmed, 0, $take)
                $chunk = $trimmed
            }
        } finally {
            if ($fsRead) { try { $fsRead.Dispose() } catch { } }
        }
        $tmpLocal = Join-Path $env:TEMP ("claude-connect-chunk-{0}.log" -f $PID)
        [System.IO.File]::WriteAllBytes($tmpLocal, $chunk)
        $day = if ($path -match 'connect-(\d{8})\.log$') { $Matches[1] } else { Get-Date -Format 'yyyyMMdd' }
        $remoteTmp = ".claude/logs/.connect-buf-$PID.tmp"
        $remoteDay = ".claude/logs/connect-$day.log"
        $sshOpts = @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no')
        $remoteBeforeProbe = Get-ConnectRemoteLogByteSize -Target $target -Day $day -SshOpts $sshOpts -TimeoutMs $script:LogSyncFastProbeMs
        if ($remoteBeforeProbe -lt 0) { $remoteBeforeProbe = [int64]0 }
        if ($fileLen -lt $remoteBeforeProbe) {
            try {
                $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                $sid = Get-ConnectSessionId
                if ($script:ConnectLogWriter) {
                    Write-ConnectLogSynced -Line "[$ts] [DEBUG] [$sid] LOG_SYNC_SKIP reason=forbid_shrink local=$fileLen remote_was=$remoteBeforeProbe off=$off (append/merge only)"
                }
            } catch { }
        }
        if (Test-ConnectRemoteLogNeedsRebuild -LocalSize $fileLen -RemoteSize $remoteBeforeProbe -Offset $off) {
            Clear-ConnectLogSyncPending -LogPath $path
            $replace = 'cat "$HOME/' + $remoteTmp + '" > "$HOME/' + $remoteDay + '"; ec=$?; rm -f "$HOME/' + $remoteTmp + '"; chmod 600 "$HOME/' + $remoteDay + '" 2>/dev/null; exit $ec'
            $mkRb = 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; find "$HOME/.claude/logs" -type f -mtime +1 -delete 2>/dev/null; true'
            $mkResRb = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList ($sshOpts + @($target, $mkRb)) -TimeoutMs 12000
            if ($mkResRb.Ok) {
                $scpFull = Invoke-ConnectLogProcTimed -Exe 'scp' -ArgumentList (@('-o','BatchMode=yes','-o','ConnectTimeout=20','-o','ControlMaster=no','-q', $path, "${target}:$remoteTmp")) -TimeoutMs 60000
                if ($scpFull.Ok) {
                    $repRes = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList ($sshOpts + @($target, $replace)) -TimeoutMs 20000
                    if ($repRes.Ok) {
                        Write-ConnectLogSyncWatermark -Offset $fileLen -LogPath $path
                        if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) {
                            $script:ConnectLogSyncOffset = [int]$fileLen
                            $script:ConnectLogLinesSinceSync = 0
                            $script:ConnectLogSyncNeeded = $false
                            $script:ConnectLogAsyncStallSince = $null
                        }
                        $script:LastConnectLogSyncOk = $true
                        $script:ConnectLogSyncFailLogged = $false
                        try {
                            $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                            $sid = Get-ConnectSessionId
                            if ($script:ConnectLogWriter) {
                                Write-ConnectLogSynced -Line "[$ts] [INFO] [$sid] LOG_SYNC_REBUILD local=$fileLen remote_was=$remoteBeforeProbe off=$off (replaced remote day log)"
                            }
                        } catch { }
                        try { Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue } catch { }
                        return
                    }
                }
            }
        }
        # --- LOG_SYNC_RECONCILE: stop duplicate appends when cat succeeded but watermark timed out ---
        $pending = Read-ConnectLogSyncPending -LogPath $path
        if ($pending -and $pending.Offset -eq $off -and $pending.Take -eq $take) {
            $rNow = Get-ConnectRemoteLogByteSize -Target $target -Day $day -SshOpts $sshOpts -TimeoutMs $script:LogSyncFastProbeMs
            if ($rNow -ge 0 -and $rNow -ge ($pending.RemoteBefore + [int64]$pending.Take)) {
                $newOff = $off + $take
                Write-ConnectLogSyncWatermark -Offset $newOff -LogPath $path
                Clear-ConnectLogSyncPending -LogPath $path
                if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) {
                    $script:ConnectLogSyncOffset = $newOff
                    $script:ConnectLogLinesSinceSync = 0
                    if ($newOff -lt $fileLen) { $script:ConnectLogLinesSinceSync = 25 }
                }
                $script:LastConnectLogSyncOk = $true
                try {
                    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                    $sid = Get-ConnectSessionId
                    if ($script:ConnectLogWriter) {
                        Write-ConnectLogSynced -Line "[$ts] [INFO] [$sid] LOG_SYNC_RECONCILE pending_ok off=$off take=$take remote=$rNow (skipped re-append)"
                    }
                } catch { }
                try { Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue } catch { }
                return
            }
        }
        if (Test-ConnectLogChunkAlreadyRemote -Target $target -Day $day -Chunk $chunk -Take $take -SshOpts $sshOpts -TimeoutMs $script:LogSyncFastChunkMs) {
            $newOff = $off + $take
            Write-ConnectLogSyncWatermark -Offset $newOff -LogPath $path
            Clear-ConnectLogSyncPending -LogPath $path
            if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) {
                $script:ConnectLogSyncOffset = $newOff
                $script:ConnectLogLinesSinceSync = 0
                if ($newOff -lt $fileLen) { $script:ConnectLogLinesSinceSync = 25 }
            }
            $script:LastConnectLogSyncOk = $true
            try {
                $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                $sid = Get-ConnectSessionId
                if ($script:ConnectLogWriter) {
                    Write-ConnectLogSynced -Line "[$ts] [INFO] [$sid] LOG_SYNC_RECONCILE tail_hash_match off=$off take=$take (skipped re-append)"
                }
            } catch { }
            try { Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue } catch { }
            return
        }
        $remoteBefore = Get-ConnectRemoteLogByteSize -Target $target -Day $day -SshOpts $sshOpts -TimeoutMs $script:LogSyncFastProbeMs
        if ($remoteBefore -lt 0) { $remoteBefore = [int64]0 }
        Write-ConnectLogSyncPending -Offset $off -Take $take -RemoteBefore $remoteBefore -LogPath $path

        $mk = 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; true'
        # Retention find is slow; keep it off the fast/non-Force mkdir SSH (P0-L3 / Task 7).
        $retain = 'find "$HOME/.claude/logs" -type f -mtime +1 -delete 2>/dev/null; true'
        # Bug 11: cat must surface append failure (no trailing true).
        $cat = 'cat "$HOME/' + $remoteTmp + '" >> "$HOME/' + $remoteDay + '"; ec=$?; rm -f "$HOME/' + $remoteTmp + '"; chmod 600 "$HOME/' + $remoteDay + '" 2>/dev/null; exit $ec'
        $mkRes = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList ($sshOpts + @($target, $mk)) -TimeoutMs $script:LogSyncFastMkdirMs
        if ($Force -and $mkRes.Ok) {
            try {
                Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList ($sshOpts + @($target, $retain)) -TimeoutMs $script:LogSyncFastMkdirMs | Out-Null
            } catch { }
        }
        if (-not $mkRes.Ok) {
            if (-not $script:ConnectLogSyncFailLogged) {
                $script:ConnectLogSyncFailLogged = $true
                try {
                    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                    $sid = Get-ConnectSessionId
                    if ($script:ConnectLogWriter) {
                        Write-ConnectLogSynced -Line "[$ts] [WARN] [$sid] LOG_SYNC_FAIL target=$target detail=mkdir_timeout_or_fail (local kept; retry later)"
                    }
                } catch { }
            }
            try { Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction Stop } catch {
                try {
                    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                    $sid = Get-ConnectSessionId
                    if ($script:ConnectLogWriter) {
                        Write-ConnectLogSynced -Line "[$ts] [WARN] [$sid] TEMP_CLEANUP_FAIL path=$tmpLocal err=$($_.Exception.Message)"
                    }
                } catch { }
            }
            return
        }
        $scpRes = Invoke-ConnectLogProcTimed -Exe 'scp' -ArgumentList (@('-o','BatchMode=yes','-o','ConnectTimeout=12','-o','ControlMaster=no','-q', $tmpLocal, "${target}:$remoteTmp")) -TimeoutMs $script:LogSyncFastScpMs
        # appendOk/scpOk := remote append succeeded (scp + cat). Watermark ONLY inside this gate.
        $appendOk = $false
        if ($scpRes.Ok) {
            $catRes = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList ($sshOpts + @($target, $cat)) -TimeoutMs $script:LogSyncFastCatMs
            if ($catRes.Ok) { $appendOk = $true }
        }
        # Even if the timed wait says fail, the remote cat may have succeeded Ã¢â‚¬â€ verify by size.
        if (-not $appendOk) {
            $remoteAfter = Get-ConnectRemoteLogByteSize -Target $target -Day $day -SshOpts $sshOpts -TimeoutMs $script:LogSyncFastProbeMs
            if ($remoteAfter -ge 0 -and $remoteAfter -ge ($remoteBefore + [int64]$take)) {
                $appendOk = $true
                try {
                    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                    $sid = Get-ConnectSessionId
                    if ($script:ConnectLogWriter) {
                        Write-ConnectLogSynced -Line "[$ts] [INFO] [$sid] LOG_SYNC_RECONCILE size_verify ok before=$remoteBefore after=$remoteAfter take=$take (timeout false-negative)"
                    }
                } catch { }
            }
        }
        $scpOk = $appendOk
        if ($scpOk) {
          if ($appendOk) {
            if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) {
                $script:ConnectLogSyncOffset = $off + $take
                $newOff = $script:ConnectLogSyncOffset
                $script:ConnectLogLinesSinceSync = 0
            } else {
                $newOff = $off + $take
            }
            Write-ConnectLogSyncWatermark -Offset $newOff -LogPath $path
            Clear-ConnectLogSyncPending -LogPath $path
            $script:LastConnectLogSyncOk = $true
            $script:ConnectLogSyncFailLogged = $false
            if ($newOff -lt $fileLen -and (-not $LogPath -or $LogPath -eq $script:ConnectLogPath)) {
                $script:ConnectLogLinesSinceSync = 25
            }
            if ($Force) {
                $guard = 0
                while ($guard -lt 64) {
                    $guard++
                    $take2 = 0
                    $chunk2 = $null
                    $fs2 = $null
                    try {
                        $fs2 = [System.IO.File]::Open(
                            $path,
                            [System.IO.FileMode]::Open,
                            [System.IO.FileAccess]::Read,
                            [System.IO.FileShare]::ReadWrite)
                        $fileLen = [int64]$fs2.Length
                        if ($newOff -ge $fileLen) { break }
                        $remain2 = $fileLen - $newOff
                        $take2 = if ($remain2 -gt $maxChunk) { [int]$maxChunk } else { [int]$remain2 }
                        $null = $fs2.Seek([int64]$newOff, [System.IO.SeekOrigin]::Begin)
                        $chunk2 = New-Object byte[] $take2
                        $got2 = $fs2.Read($chunk2, 0, $take2)
                        if ($got2 -le 0) { break }
                        if ($got2 -lt $take2) {
                            $take2 = $got2
                            $trimmed2 = New-Object byte[] $take2
                            [Array]::Copy($chunk2, 0, $trimmed2, 0, $take2)
                            $chunk2 = $trimmed2
                        }
                    } finally {
                        if ($fs2) { try { $fs2.Dispose() } catch { } }
                    }
                    [System.IO.File]::WriteAllBytes($tmpLocal, $chunk2)
                    $scp2 = Invoke-ConnectLogProcTimed -Exe 'scp' -ArgumentList (@('-o','BatchMode=yes','-o','ConnectTimeout=12','-o','ControlMaster=no','-q', $tmpLocal, "${target}:$remoteTmp")) -TimeoutMs 20000
                    if (-not $scp2.Ok) { break }
                    $cat2 = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList ($sshOpts + @($target, $cat)) -TimeoutMs 12000
                    if (-not $cat2.Ok) { break }
                    $newOff = $newOff + $take2
                    Write-ConnectLogSyncWatermark -Offset $newOff -LogPath $path
                    if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) {
                        $script:ConnectLogSyncOffset = $newOff
                    }
                }
            }
          }
        } elseif (-not $script:ConnectLogSyncFailLogged) {
            $script:ConnectLogSyncFailLogged = $true
            try {
                $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                $sid = Get-ConnectSessionId
                if ($script:ConnectLogWriter) {
                    Write-ConnectLogSynced -Line "[$ts] [WARN] [$sid] LOG_SYNC_FAIL target=$target detail=scp_or_append_fail (local kept; retry later)"
                }
            } catch { }
        }
        try { Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction Stop } catch {
            try {
                $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                $sid = Get-ConnectSessionId
                if ($script:ConnectLogWriter) {
                    Write-ConnectLogSynced -Line "[$ts] [WARN] [$sid] TEMP_CLEANUP_FAIL path=$tmpLocal err=$($_.Exception.Message)"
                }
            } catch { }
        }
    } catch {
        # Stage 9: never swallow sync exceptions without a durable breadcrumb.
        if (-not $script:ConnectLogSyncFailLogged) {
            $script:ConnectLogSyncFailLogged = $true
            try {
                $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                $sid = Get-ConnectSessionId
                $ex = $_.Exception.Message
                if ($ex) { $ex = ($ex -replace '[
]+', ' ').Substring(0, [Math]::Min(160, $ex.Length)) }
                if ($script:ConnectLogWriter) {
                    Write-ConnectLogSynced -Line "[$ts] [WARN] [$sid] LOG_SYNC_FAIL target=$target detail=exception err=$ex (local kept; retry later)"
                }
            } catch { }
        }
        if (-not $LogPath -or $LogPath -eq $script:ConnectLogPath) { $script:ConnectLogSyncNeeded = $true }
    }
    finally {
        $script:ConnectLogSyncInProgress = $false
        if ($lockStream) {
            try { $lockStream.Close() } catch { }
            try { $lockStream.Dispose() } catch { }
        }
    }
}

function Ensure-ConnectLogAsyncTimer {
    # Coalescing background drain for Request-ConnectLogSync (non-Force).
    # Register-ObjectEvent (not Start-Job / raw runspace) so the Elapsed handler
    # runs pumped through this same session's event queue - safe on WinPS 5.1.
    if ($script:ConnectLogAsyncDrainerRunning -and $script:ConnectLogAsyncTimer) { return }
    try {
        if (-not $script:ConnectLogAsyncTimer) {
            $timer = [System.Timers.Timer]::new(1500)
            $timer.AutoReset = $true
            $sub = Register-ObjectEvent -InputObject $timer -EventName Elapsed `
                -SourceIdentifier 'ConnectLogAsyncTimerElapsed' -Action {
                try {
                    if ($script:ConnectLogSyncInProgress) { return }
                    $needed = [bool]$script:ConnectLogSyncNeeded
                    $warnUntil = $script:ConnectLogWarnPendingUntil
                    $now = Get-Date
                    $warnActive = ($warnUntil -and $now -lt $warnUntil)
                    if (-not $needed -and -not $warnActive) { return }
                    $unsynced = [int64]0
                    if (Get-Command Get-ConnectLogUnsyncedByteCount -ErrorAction SilentlyContinue) {
                        $unsynced = Get-ConnectLogUnsyncedByteCount
                    }
                    if ($unsynced -gt 8192) {
                        if (-not $script:ConnectLogAsyncStallSince) { $script:ConnectLogAsyncStallSince = Get-Date }
                        elseif (((Get-Date) - $script:ConnectLogAsyncStallSince).TotalSeconds -ge 60) {
                            if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {
                                Sync-ConnectLogToServer -Force | Out-Null
                            }
                            $script:ConnectLogAsyncStallSince = $null
                        }
                    } else { $script:ConnectLogAsyncStallSince = $null }
                    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {
                        Sync-ConnectLogToServer | Out-Null
                    }
                    if ($script:ConnectLogWarnPendingUntil -and (Get-Date) -ge $script:ConnectLogWarnPendingUntil) {
                        $script:ConnectLogWarnPendingUntil = $null
                    }
                    # Only clear Needed when caught up (was clearing on lock/fail ÃƒÂ¢Ã¢â€šÂ¬" stalled drain).
                    $left = [int64]0
                    if (Get-Command Get-ConnectLogUnsyncedByteCount -ErrorAction SilentlyContinue) {
                        $left = Get-ConnectLogUnsyncedByteCount
                    }
                    if ($left -le 0) {
                        $script:ConnectLogSyncNeeded = $false
                        $script:ConnectLogAsyncStallSince = $null
                    } else {
                        $script:ConnectLogSyncNeeded = $true
                    }
                } catch { }
            }
            $script:ConnectLogAsyncTimer = $timer
            if ($sub) { $script:ConnectLogAsyncTimerSubId = $sub.Name }
        }
        $script:ConnectLogAsyncTimer.Start()
        $script:ConnectLogAsyncDrainerRunning = $true
    } catch {
        $script:ConnectLogAsyncDrainerRunning = $false
    }
}

function Request-ConnectLogSync {
    param(
        [switch]$Force,
        [switch]$NoInline
    )
    if ($Force) {
        Complete-ConnectLogAsyncDrain -Force
        return
    }
    $alreadyNeeded = [bool]$script:ConnectLogSyncNeeded
    $script:ConnectLogSyncNeeded = $true
    if (Get-Command Get-ConnectLogUnsyncedByteCount -ErrorAction SilentlyContinue) {
        $u = Get-ConnectLogUnsyncedByteCount
        # Stall Force after 60s if backlog > 8KB (was 256KB/120s ÃƒÂ¢Ã¢â€šÂ¬" never tripped).
        if ($u -gt 8192 -and -not $script:ConnectLogAsyncStallSince) { $script:ConnectLogAsyncStallSince = Get-Date }
        elseif ($u -le 8192) { $script:ConnectLogAsyncStallSince = $null }
    }
    Ensure-ConnectLogAsyncTimer
    # -NoInline: schedule timer only (never block UI / SshX). Used by StepOk and
    # Write-ConnectLog INFO so Loading projects cannot freeze on log scp/ssh.
    if ($NoInline) {
        if (-not $alreadyNeeded -and (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue)) {
            try { Write-ConnectLog 'LOG_SYNC_ASYNC scheduled=1' 'DEBUG' } catch { }
        }
        return
    }
    # WinPS often does not pump Register-ObjectEvent during ReadKey/Sleep - sync inline
    # only for small backlogs. A multi-MB day log inline-sync stalls the UI for tens of
    # seconds (looked like Preparing tunnel / Checking SSH hung). Large backlog = timer only.
    $inlineOk = $true
    if (Get-Command Get-ConnectLogUnsyncedByteCount -ErrorAction SilentlyContinue) {
        try {
            if ((Get-ConnectLogUnsyncedByteCount) -gt 65536) { $inlineOk = $false }
        } catch { }
    }
    if ($inlineOk) {
        try { Sync-ConnectLogToServer | Out-Null } catch { }
    }
    if (Get-Command Get-ConnectLogUnsyncedByteCount -ErrorAction SilentlyContinue) {
        $u2 = Get-ConnectLogUnsyncedByteCount
        if ($u2 -gt 8192 -and $script:ConnectLogAsyncStallSince -and (((Get-Date) - $script:ConnectLogAsyncStallSince).TotalSeconds -ge 60)) {
            try { Sync-ConnectLogToServer -Force | Out-Null } catch { }
            $script:ConnectLogAsyncStallSince = $null
        }
        if ($u2 -le 0) { $script:ConnectLogSyncNeeded = $false }
    }
    if (-not $alreadyNeeded -and (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue)) {
        try { Write-ConnectLog 'LOG_SYNC_ASYNC scheduled=1' 'DEBUG' } catch { }
    }
}

function Complete-ConnectLogAsyncDrain {
    param([switch]$Force)
    try {
        if ($script:ConnectLogAsyncTimer) {
            try { $script:ConnectLogAsyncTimer.Stop() } catch { }
        }
        if ($script:ConnectLogAsyncTimerSubId) {
            try { Unregister-Event -SourceIdentifier $script:ConnectLogAsyncTimerSubId -ErrorAction SilentlyContinue } catch { }
            try { Remove-Job -Name $script:ConnectLogAsyncTimerSubId -Force -ErrorAction SilentlyContinue } catch { }
            $script:ConnectLogAsyncTimerSubId = $null
        }
        if ($script:ConnectLogAsyncTimer) {
            try { $script:ConnectLogAsyncTimer.Dispose() } catch { }
            $script:ConnectLogAsyncTimer = $null
        }
        $script:ConnectLogAsyncDrainerRunning = $false
        # Remember Needed before drain; do not clear it until Force sync succeeds (P0-L3 / Task 7).
        $hadNeeded = [bool]$script:ConnectLogSyncNeeded
        # Drain any coalesced Needed/WARN state before the (optional) final Force sync.
        if (($script:ConnectLogSyncNeeded -or $script:ConnectLogWarnPendingUntil) -and (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue)) {
            try { Sync-ConnectLogToServer | Out-Null } catch { }
        }
        if ($Force -and (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue)) {
            try {
                Sync-ConnectLogToServer -Force | Out-Null
                if (-not $script:LastConnectLogSyncOk -and $hadNeeded) {
                    $script:ConnectLogSyncNeeded = $true
                    return
                }
            } catch {
                if ($hadNeeded) { $script:ConnectLogSyncNeeded = $true }
                return
            }
        }
        $script:ConnectLogSyncNeeded = $false
        $script:ConnectLogWarnPendingUntil = $null
    } catch { }
}

function Ensure-ConnectLogWriter {
    $dayPath = Get-ConnectLogDayPath
    # Midnight rollover: flush previous day to server before abandoning (bug 37).
    if ($script:ConnectLogWriter -and $script:ConnectLogPath -and ($script:ConnectLogPath -ne $dayPath)) {
        $prevPath = $script:ConnectLogPath
        try { $script:ConnectLogWriter.Flush() } catch { }
        try { $script:ConnectLogWriter.Dispose() } catch { }
        $script:ConnectLogWriter = $null
        try { Sync-ConnectLogToServer -Force -LogPath $prevPath } catch { }
        $script:ConnectLogPath = $dayPath
        $script:ConnectLogSyncOffset = Read-ConnectLogSyncWatermark -LogPath $script:ConnectLogPath
        $script:ConnectLogLinesSinceSync = 0
    }
    if ($script:ConnectLogWriter) { return $true }
    if (-not $script:ConnectLogPath) { $script:ConnectLogPath = $dayPath }
    try {
        $fs = [System.IO.FileStream]::new(
            $script:ConnectLogPath,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite)
        $script:ConnectLogFileStream = $fs
        $script:ConnectLogWriter = [System.IO.StreamWriter]::new($fs, [System.Text.UTF8Encoding]::new($false))
        $script:ConnectLogWriter.AutoFlush = $true
        return $true
    } catch {
        return $false
    }
}

# .NET FileStream FileMode.Append only seeks to EOF once, at open time - it does NOT
# re-seek before every write. Two connect.ps1 processes (now legitimately concurrent -
# up to 10 sessions per PC, see connect-boot.ps1) each hold their own FileStream with
# their own tracked position, so near-simultaneous writes to the same day-log file can
# land at stale offsets and overwrite/interleave each other mid-line (observed directly:
# corrupted, spliced log lines from two session IDs in the same file). A named mutex
# serializes the "seek to true current EOF, then write" critical section across every
# connect.ps1 process writing to day logs.
#
# Global\ (not Local\): this machine's client tooling is architected for multiple real
# concurrent connect.ps1 windows (Global\ClaudeConnect#0..9, Enter-ConnectSingleInstance
# above) under one interactive user, so Local\ would already be sufficient for today's
# usage - but per-user Windows session isolation is not guaranteed to hold forever on a
# shared machine (e.g. a second RDP/service session writing the same on-disk log path),
# and Global\ costs nothing extra (same lightweight kernel object either way) while
# staying correct in that edge case too, matching the Global\ scope already chosen for
# the slot mutex this pattern mirrors.
#
# Scoped PER LOG FILE (day-suffixed name, not one bare name for all days/paths): the day
# log path itself is day-suffixed (connect-YYYYMMDD.log), so without day-scoping the
# mutex, sessions writing to *different, unrelated* day-log files (e.g. spanning a
# midnight rollover) would still serialize against each other for no reason - a pure
# throughput cost with zero correctness benefit. Re-derives/recreates the mutex handle
# whenever the day changes (naturally covers Ensure-ConnectLogWriter's midnight rollover).
function Get-ConnectLogWriteMutex {
    $dayTag = if ($script:ConnectLogPath -and ($script:ConnectLogPath -match 'connect-(\d{8})\.log$')) {
        $Matches[1]
    } else {
        Get-Date -Format 'yyyyMMdd'
    }
    $mutexName = "Global\ClaudeConnectDayLogWrite-$dayTag"
    if ($script:ConnectLogWriteMutex -and $script:ConnectLogWriteMutexName -eq $mutexName) {
        return $script:ConnectLogWriteMutex
    }
    if ($script:ConnectLogWriteMutex) {
        try { $script:ConnectLogWriteMutex.Close() } catch { }
        $script:ConnectLogWriteMutex = $null
    }
    try {
        $script:ConnectLogWriteMutex = New-Object System.Threading.Mutex($false, $mutexName)
        $script:ConnectLogWriteMutexName = $mutexName
    } catch {
        $script:ConnectLogWriteMutex = $null
        $script:ConnectLogWriteMutexName = ''
    }
    return $script:ConnectLogWriteMutex
}

# Re-seeks the shared FileStream to the TRUE current end-of-file (which may have moved
# due to another connect.ps1 process's writes) immediately before the bytes actually hit
# disk, all inside the cross-process mutex. Safe for both the AutoFlush=true path (a
# WriteLine here flushes immediately) and the buffered TRACE/DEBUG path (Line omitted;
# just flushes whatever WriteLine already buffered in memory).
function Write-ConnectLogSynced {
    param([string]$Line = '')
    $mutex = Get-ConnectLogWriteMutex
    $acquired = $false
    try {
        if ($mutex) {
            # 5000ms: mutex hold time per writer is a Seek+WriteLine+Flush (sub-ms in
            # practice), so this ceiling is essentially never hit under real contention -
            # it only guards against a genuinely wedged holder (e.g. a killed process that
            # left the mutex abandoned mid-Seek, surfaced below as AbandonedMutexException).
            try { $acquired = $mutex.WaitOne(5000) }
            catch [System.Threading.AbandonedMutexException] { $acquired = $true }
            catch { $acquired = $false }
        }
        if (-not $acquired -and $mutex) {
            # Zero-loss policy (CLAUDE.md "Connect session logs"): never silently drop the
            # line - fall through and write it unsynchronized as a last resort (same risk
            # window this whole fix closes for the common case), but leave a durable,
            # out-of-band breadcrumb about the contention. Written directly to last-fail.txt
            # (the same breadcrumb sink Write-ConnectLog's own ERROR/WARN path uses) rather
            # than via Write-ConnectLog/Write-ConnectLogSynced, to avoid recursing back into
            # this same function.
            try {
                $breadDir = Join-Path $env:USERPROFILE '.config\claude-connect'
                New-Item -ItemType Directory -Force -Path $breadDir | Out-Null
                $bts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                $bsid = if ($script:ConnectSessionId) { $script:ConnectSessionId } else { '' }
                $bline = "[$bts] [WARN] [$bsid] LOG_WRITE_LOCK_CONTENTION waited_ms=5000 acquired=false (wrote unsynchronized as last resort; zero-loss over strict ordering)" + [Environment]::NewLine
                [System.IO.File]::AppendAllText((Join-Path $breadDir 'last-fail.txt'), $bline, [System.Text.UTF8Encoding]::new($false))
            } catch { }
        }
        # Deliberately NOT a Seek (SeekOrigin.End, or even a fresh FileInfo-derived length)
        # on the long-lived $script:ConnectLogFileStream: empirically verified (real
        # multi-process test, see test-concurrent-log-writers-live.ps1 / the E2E driver in
        # this bug's report) that BOTH still occasionally land at a length that is stale by
        # the time another process's just-flushed append becomes visible to a re-query from
        # a different handle/object - under real back-to-back cross-process writes this
        # still corrupted/overwrote a small fraction of lines. The only construction that
        # was actually verified corruption-free across repeated live multi-process runs is a
        # brand-new, single-purpose FileStream/handle per protected write: opening fresh in
        # FileMode.Append means the OS resolves "current end of file" itself, at that exact
        # open call, with no cached/stale state possible (there is no prior state to cache -
        # the handle did not exist a moment ago). This is the "reopen FileShare.None-per-write
        # (flock-style)" alternative named in the plan/bug report; the cross-process mutex
        # above already provides the exclusivity a bare FileShare.None open would add, so
        # FileShare.ReadWrite here (matching the long-lived writer's own share mode) is
        # sufficient and keeps a second concurrent reader (e.g. Sync-ConnectLogToServer's
        # chunked read) unblocked while this fresh append handle is briefly open.
        $pending = ''
        if ($script:ConnectLogPendingBuffer -and $script:ConnectLogPendingBuffer.Length -gt 0) {
            $pending = $script:ConnectLogPendingBuffer.ToString()
            [void]$script:ConnectLogPendingBuffer.Clear()
        }
        $toWrite = $pending
        if ($Line) { $toWrite += $Line + [Environment]::NewLine }
        if ($toWrite -and $script:ConnectLogPath) {
            $fsWrite = $null
            try {
                $fsWrite = [System.IO.FileStream]::new(
                    $script:ConnectLogPath,
                    [System.IO.FileMode]::Append,
                    [System.IO.FileAccess]::Write,
                    [System.IO.FileShare]::ReadWrite)
                $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($toWrite)
                $fsWrite.Write($bytes, 0, $bytes.Length)
                $fsWrite.Flush()
            } catch {
                # Last resort: re-buffer so the next successful sync doesn't silently drop
                # these bytes (zero-loss over strict ordering).
                try { [void]$script:ConnectLogPendingBuffer.Append($toWrite) } catch { }
            } finally {
                if ($fsWrite) { try { $fsWrite.Dispose() } catch { } }
            }
        }
    } finally {
        if ($acquired -and $mutex) { try { $mutex.ReleaseMutex() } catch { } }
    }
}

function Write-ConnectLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    if (-not (Ensure-ConnectLogWriter)) { return }
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = Get-ConnectSessionId
        if ($Level -eq 'TRACE' -or $Level -eq 'DEBUG') {
            # Buffer hot-loop noise locally (in-process StringBuilder, not the shared
            # StreamWriter - see Write-ConnectLogSynced); flush at most every 2s (AV/disk tax).
            [void]$script:ConnectLogPendingBuffer.AppendLine("[$ts] [$Level] [$sid] $Message")
                    if ($Level -eq 'ERROR' -or $Level -eq 'WARN') {
                        try {
                            $breadDir = Join-Path $env:USERPROFILE '.config\claude-connect'
                            New-Item -ItemType Directory -Force -Path $breadDir | Out-Null
                            $bread = Join-Path $breadDir 'last-fail.txt'
                            $bline = "[$ts] [$Level] [$sid] $Message" + [Environment]::NewLine
                            [System.IO.File]::AppendAllText($bread, $bline, [System.Text.UTF8Encoding]::new($false))
                        } catch { }
                    }
            $nowFlush = Get-Date
            if (-not $script:ConnectLogLastTraceFlushAt -or ($nowFlush - $script:ConnectLogLastTraceFlushAt).TotalSeconds -ge 2) {
                Write-ConnectLogSynced
                $script:ConnectLogLastTraceFlushAt = $nowFlush
            }
            # Bug 36: TUNNEL_* TRACE may carry soft_fail context - allow sync trigger.
            if ($Level -eq 'TRACE' -and $Message -match 'TUNNEL_') {
                $script:ConnectLogLinesSinceSync = [int]$script:ConnectLogLinesSinceSync + 1
                if ($Message -match 'soft_fail|TUNNEL_DROP|TUNNEL_EXIT' -or $script:ConnectLogLinesSinceSync -ge 25) {
                    Write-ConnectLogSynced
                    # Never inline-sync from here (same reasoning as the INFO path below): a
                    # burst of TUNNEL_* trace lines mid-connect must not block the console on a
                    # slow/degraded SSH round trip.
                    if (Get-Command Request-ConnectLogSync -ErrorAction SilentlyContinue) {
                        Request-ConnectLogSync -NoInline
                    } else {
                        $script:ConnectLogSyncNeeded = $true
                    }
                }
            }
            return
        }
        # Flush any pending TRACE/DEBUG buffer so WARN/ERROR sync is not stuck waiting for 2s TRACE flush.
        Write-ConnectLogSynced
        Write-ConnectLogSynced -Line "[$ts] [$Level] [$sid] $Message"
        # Local always complete. Sync carefully:
        # - TRACE/DEBUG stay local-only during hot loops except TUNNEL_* (above)
        # - ERROR Force-flushes now; WARN coalesces into a 5s async-drain window; INFO every 25 lines
        $script:ConnectLogLinesSinceSync = [int]$script:ConnectLogLinesSinceSync + 1
        if ($Level -eq 'ERROR') {
            if (Get-Command Complete-ConnectLogAsyncDrain -ErrorAction SilentlyContinue) {
                Complete-ConnectLogAsyncDrain -Force
            } else {
                Sync-ConnectLogToServer -Force
            }
        } elseif ($Level -eq 'WARN') {
            # Coalesce: warn-only bursts get a 5s grace window instead of an immediate Force sync.
            $script:ConnectLogWarnPendingUntil = (Get-Date).AddSeconds(5)
            $script:ConnectLogSyncNeeded = $true
            # -NoInline to actually honor the "5s grace window" above - calling this without
            # -NoInline blocked the console for 8-17s per WARN line under a slow/degraded link.
            if (Get-Command Request-ConnectLogSync -ErrorAction SilentlyContinue) {
                Request-ConnectLogSync -NoInline
            } else {
                $script:ConnectLogSyncNeeded = $true
            }
        } elseif ($script:ConnectLogLinesSinceSync -ge 25) {
            # Never inline-sync from Write-ConnectLog: SshX logs SSH_END via this path
            # mid Get-Mounts ("Loading projects"). A hung/slow ssh size-probe used to
            # freeze the console for minutes with no STEP end / project menu.
            if (Get-Command Request-ConnectLogSync -ErrorAction SilentlyContinue) {
                Request-ConnectLogSync -NoInline
            } else {
                $script:ConnectLogSyncNeeded = $true
            }
        }
    } catch {
        # Writer may have died; drop handle so next line re-opens.
        try { if ($script:ConnectLogWriter) { $script:ConnectLogWriter.Dispose() } } catch { }
        $script:ConnectLogWriter = $null
    }
}


function Read-ConnectPrompt {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Tag = 'INPUT'
    )
    $val = (Read-Host $Prompt)
    $shown = if ($null -eq $val) { '' } else { [string]$val }
    $safe = $shown
    if ($safe.Length -gt 200) { $safe = $safe.Substring(0, 200) + '...' }
    Write-ConnectLog ("{0}: prompt={1} answer={2}" -f $Tag, ($Prompt -replace '\s+', ' ').Trim(), $safe)
    return $shown
}


function Write-ConnectUserFacingError {
    # Every red [X] the user sees MUST land in the day log as ERROR (grep-able).
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Code = ''
    )
    $safe = (($Message + '') -replace '[\r\n]+', ' ').Trim()
    if ($safe.Length -gt 500) { $safe = $safe.Substring(0, 500) + '...' }
    if ($Code) {
        Write-ConnectLog ("USER_ERROR: code={0} {1}" -f $Code, $safe) 'ERROR'
    } else {
        Write-ConnectLog ("USER_ERROR: {0}" -f $safe) 'ERROR'
    }
}


function Close-ConnectRelaunchHostConsole {
    # After update relaunch, kill a leftover parent cmd.exe that was started with /K
    # (or otherwise outlives powershell). Never touch unrelated parents.
    try {
        $self = Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop
        $parentId = [int]$self.ParentProcessId
        if ($parentId -le 4) { return }
        $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$parentId" -ErrorAction SilentlyContinue
        if (-not $parent) { return }
        $cmdLine = [string]$parent.CommandLine
        $isConnectCmd = ($parent.Name -eq 'cmd.exe') -and ($cmdLine -match '(?i)connect\.bat')
        if (-not $isConnectCmd) { return }
        # Detached killer so our exit is not blocked if Stop-Process races us.
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
            ("Start-Sleep -Milliseconds 500; Stop-Process -Id {0} -Force -ErrorAction SilentlyContinue" -f $parentId)
        ) | Out-Null
        Write-ConnectLog ("EXIT_RELAUNCH_HOST_CMD scheduled parent_cmd_pid={0}" -f $parentId) 'INFO'
    } catch { }
}

function Wait-ConnectExit {
    param(
        [string]$Reason = 'user_close',
        [int]$Code = 1
    )
    # Non-zero exit = failure the operator must see in logs immediately (not INFO).
    $level = if ($Code -eq 0) { 'INFO' } else { 'ERROR' }
    Write-ConnectLog ("EXIT_WAIT: reason={0} code={1} uiReady={2}" -f $Reason, $Code, [bool]$script:ConnectUiReady) $level
    if ($Code -ne 0) {
        Write-ConnectLog ("FAIL EXIT reason={0} code={1}" -f $Reason, $Code) 'ERROR'
    }

    # Successful update relaunch already spawned a new Connect window. Must exit FAST:
    # Force log-sync over SSH can hang for tens of seconds and leaves the old UI stuck on
    # "Update applied - relaunching...". Skip blocking drain/Close-ConnectLog here.
    # Also skip Read-Host for ANY update_* reason (even non-zero) — Press Enter after a
    # successful "Update applied" is always wrong UX.
    $skipEnter = (
        $Reason -eq 'update_manual_relaunch' -or
        $Reason -eq 'update_relaunch'
    )
    if ($skipEnter) {
        try {
            if ($script:ConnectLogWriter) {
                try { Write-ConnectLog '======== session end (update_relaunch) ========' } catch { }
                try { $script:ConnectLogWriter.Flush() } catch { }
                try { $script:ConnectLogWriter.Dispose() } catch { }
                $script:ConnectLogWriter = $null
            }
        } catch { }
        try {
            if (Get-Command Exit-ConnectSingleInstance -ErrorAction SilentlyContinue) {
                Exit-ConnectSingleInstance
            }
        } catch { }
        try { Close-ConnectRelaunchHostConsole } catch { }
        exit 0
    }

    if (Get-Command Complete-ConnectLogAsyncDrain -ErrorAction SilentlyContinue) {
        Complete-ConnectLogAsyncDrain -Force
    } elseif (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {
        Sync-ConnectLogToServer -Force | Out-Null
    }
    if ($script:ConnectUiReady) {
        try { Read-Host '    Press Enter to close' | Out-Null } catch { }
    }
    if (Get-Command Close-ConnectLog -ErrorAction SilentlyContinue) { Close-ConnectLog }
    exit $Code
}

function Write-ConnectDecision {
    param(
        [Parameter(Mandatory)][string]$What,
        [AllowEmptyString()][string]$Value = '',
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    if ($null -eq $Value) { $Value = '' }
    Write-ConnectLog ("DECISION: {0}={1}" -f $What, $Value) $Level
}

function Write-ConnectTrace {
    param([Parameter(Mandatory)][string]$Message)
    Write-ConnectLog $Message 'TRACE'
}

function Test-ConnectPerfEnabled {
    # Default OFF: hot session loop was spamming PERF[cim_query] every 200ms.
    # Opt-in: set CLAUDE_CONNECT_PERF_LOG=1
    if ($env:CLAUDE_CONNECT_PERF_LOG -eq '1') { return $true }
    return $false
}

function Write-ConnectPerfLog {
    param(
        [Parameter(Mandatory)][string]$Mark,
        [Parameter(Mandatory)][int]$Ms,
        [string]$Extra = '',
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'DEBUG'
    )
    if (-not (Test-ConnectPerfEnabled)) { return }
    $suffix = if ($Extra) { " $Extra" } else { '' }
    Write-ConnectLog "PERF[$Mark] ms=$Ms$suffix" $Level
}

function Invoke-ConnectBatRelaunch {
    param([string]$ScriptDir)
    if (-not $ScriptDir) {
        if ($script:ConnectScriptDir) { $ScriptDir = $script:ConnectScriptDir }
        elseif ($PSScriptRoot) { $ScriptDir = $PSScriptRoot }
    }
    if (-not $ScriptDir) { return $false }
    try {
        $bat = Join-Path $ScriptDir 'connect.bat'
        if (-not (Test-Path -LiteralPath $bat)) {
            if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                Write-ConnectLog 'UPDATE_RELAUNCH skip reason=no_connect_bat' 'WARN'
            }
            return $false
        }
        $depth = 0
        if ($env:CLAUDE_CONNECT_UPDATE_DEPTH) {
            [void][int]::TryParse(($env:CLAUDE_CONNECT_UPDATE_DEPTH + '').Trim(), [ref]$depth)
        }
        if ($depth -lt 0) { $depth = 0 }
        $depth++
        $relaunchRunId = [guid]::NewGuid().ToString('N').Substring(0, 12)
        $marker = Join-Path $ScriptDir '.client-update-relaunch'
        Set-Content -LiteralPath $marker -Value $relaunchRunId -Encoding ASCII -NoNewline -ErrorAction Stop
        # Inherit env into a single visible Connect window ÃƒÂ¢Ã¢â€šÂ¬" do NOT cmd/c start (spawns extra consoles).
        $prevDepth = $env:CLAUDE_CONNECT_UPDATE_DEPTH
        $prevRun = $env:CLAUDE_CONNECT_RUN_ID
        $prevRelaunch = $env:CLAUDE_CONNECT_IS_RELAUNCH
        try {
            $env:CLAUDE_CONNECT_UPDATE_DEPTH = [string]$depth
            $env:CLAUDE_CONNECT_RUN_ID = $relaunchRunId
            $env:CLAUDE_CONNECT_IS_RELAUNCH = '1'
            Start-Process -FilePath $bat -WorkingDirectory $ScriptDir | Out-Null
        } finally {
            if ($null -eq $prevDepth) { Remove-Item Env:CLAUDE_CONNECT_UPDATE_DEPTH -ErrorAction SilentlyContinue }
            else { $env:CLAUDE_CONNECT_UPDATE_DEPTH = $prevDepth }
            if ($null -eq $prevRun) { Remove-Item Env:CLAUDE_CONNECT_RUN_ID -ErrorAction SilentlyContinue }
            else { $env:CLAUDE_CONNECT_RUN_ID = $prevRun }
            if ($null -eq $prevRelaunch) { Remove-Item Env:CLAUDE_CONNECT_IS_RELAUNCH -ErrorAction SilentlyContinue }
            else { $env:CLAUDE_CONNECT_IS_RELAUNCH = $prevRelaunch }
        }
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("UPDATE_RELAUNCH spawned depth=$depth run_id=$relaunchRunId") 'INFO'
        }
        return $true
    } catch {
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("UPDATE_RELAUNCH fail err=$($_.Exception.Message)") 'ERROR'
        }
        return $false
    }
}

function Invoke-ConnectSilentUpdateCheck {
    # Manual-only policy: never Quiet-check / auto-apply mid-session.
    # Updates run only when the user presses u (Invoke-ConnectManualUpdate).
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'UPDATE_SILENT skip reason=manual_only' 'DEBUG'
    }
}

function Invoke-ConnectManualUpdate {
    <#
    .SYNOPSIS
      User-triggered client update from the project menu (u).
      Always runs a visible check (not Quiet) and clears throttle/defer so Download works on demand.
    #>
    $scriptDir = $null
    if ($script:ConnectScriptDir) { $scriptDir = $script:ConnectScriptDir }
    elseif ($PSScriptRoot) { $scriptDir = $PSScriptRoot }
    if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

    $cfgDir = Join-Path $env:USERPROFILE '.config\claude-connect'
    foreach ($name in @('update-check-miss.txt', 'update-defer.txt', '.last-update-check')) {
        $p = Join-Path $cfgDir $name
        try { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } } catch { }
    }

    $updateScript = Join-Path $scriptDir 'connect-update.ps1'
    if (-not (Test-Path -LiteralPath $updateScript)) {
        Warn "Update script missing: $updateScript"
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog "UPDATE_MANUAL result=fail reason=no_script path=$updateScript" 'ERROR'
        }
        return
    }

    Write-Host ''
    Write-Host '    Checking for client update...' -ForegroundColor Cyan
    Write-Host ''
    if (Get-Command Write-ConnectDecision -ErrorAction SilentlyContinue) {
        Write-ConnectDecision 'project_menu' 'update_manual'
    } elseif (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'DECISION: project_menu=update_manual' 'INFO'
    }

    $exitCode = 1
    try {
        # Not -Quiet: optional updates prompt Y/N; force policy still auto-applies.
        # Flag so connect-update can kill_self after apply (avoids stale Press Enter from old in-memory UI).
        $env:CLAUDE_CONNECT_MANUAL_UPDATE = '1'
        & $updateScript -ScriptDir $scriptDir
        if ($null -ne $LASTEXITCODE) { $exitCode = [int]$LASTEXITCODE } else { $exitCode = 0 }
    } catch {
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("UPDATE_MANUAL result=fail error={0}" -f $_.Exception.Message) 'ERROR'
        }
        Warn ("Update failed: {0}" -f $_.Exception.Message)
        return
    } finally {
        Remove-Item Env:CLAUDE_CONNECT_MANUAL_UPDATE -ErrorAction SilentlyContinue
    }

    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("UPDATE_MANUAL result=exit exit={0}" -f $exitCode) 'INFO'
    }

    if ($exitCode -eq 2) {
        Write-Host '    Update applied - relaunching...' -ForegroundColor Green
        try { [Console]::Out.Flush() } catch { }
        # connect-update (same process) already spawned bat + scheduled kill_self when it
        # detected Wait-ConnectExit. If we still reach here (older updater / race), relaunch
        # and hard-exit without "Press Enter to close".
        if (Get-Command Exit-ConnectSingleInstance -ErrorAction SilentlyContinue) {
            Exit-ConnectSingleInstance
        }
        $null = Invoke-ConnectBatRelaunch -ScriptDir $scriptDir
        try { Close-ConnectRelaunchHostConsole } catch { }
        # Never fall through to a stale in-memory Wait-ConnectExit that still has Read-Host
        # (pre-skipEnter builds showed "Press Enter to close" after a successful update).
        try { [Environment]::Exit(0) } catch { }
        try { Stop-Process -Id $PID -Force -ErrorAction Stop } catch { }
        exit 0
    } elseif ($exitCode -eq 0) {
        Write-Host '    Update check finished.' -ForegroundColor DarkGray
        Write-Host ''
    } else {
        Warn 'Update check failed (see day log).'
        Write-Host ''
    }
}


function Invoke-AgentPathProbe {
    # Fail-open: probe server conf TUNNEL_PORT vs this UI session port (rate-limited 60s).
    # Dual-UI: session!=conf with listen_conf=1 is ok (primary_match=0). Bad only when
    # conf empty, conf port closed, or parse/ssh fail.
    try {
        $sessionPortRaw = $null
        if ($null -ne $script:Port -and ("$($script:Port)").Trim().Length -gt 0) {
            $sessionPortRaw = "$($script:Port)"
        } elseif ($Port -and ("$Port").Trim().Length -gt 0) {
            $sessionPortRaw = "$Port"
        } elseif ($null -ne $script:TunnelPort -and ("$($script:TunnelPort)").Trim().Length -gt 0) {
            $sessionPortRaw = "$($script:TunnelPort)"
        } elseif ($env:TunnelPort -and ("$($env:TunnelPort)").Trim().Length -gt 0) {
            $sessionPortRaw = "$($env:TunnelPort)"
        }
        $sessionPort = if ($null -ne $sessionPortRaw) { ($sessionPortRaw -replace '\D', '') } else { '' }
        if (-not $sessionPort) {
            Write-ConnectTrace 'AGENT_PATH skip reason=no_session_port'
            return
        }

        $nowUnix = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        if (($nowUnix - [int]$script:LastAgentPathUnix) -lt 60) { return }
        # Stamp immediately so a fail does not retry-storm within the window.
        $script:LastAgentPathUnix = $nowUnix

        if (-not (Get-Command SshX -ErrorAction SilentlyContinue)) {
            Write-ConnectTrace 'AGENT_PATH skip reason=no_sshx'
            return
        }

        # Literal remote one-liner; only PORTPLACEHOLDER is substituted (digits-only session port).
        $remoteCmd = @'
timeout 3 bash -c 'C="$HOME/.claude-connect.conf"; cp=$(grep -E "^TUNNEL_PORT=" "$C" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "\r"); am=$(grep -E "^ACTIVE_MOUNT=" "$C" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "\r"); sp=PORTPLACEHOLDER; lc=0; ls=0; if [ -n "$cp" ]; then timeout 1 bash -c "echo >/dev/tcp/127.0.0.1/$cp" 2>/dev/null && lc=1 || true; fi; if [ -n "$sp" ]; then timeout 1 bash -c "echo >/dev/tcp/127.0.0.1/$sp" 2>/dev/null && ls=1 || true; fi; echo "AGENT_PATH_PROBE conf_port=${cp:-} conf_am=${am:-} listen_conf=$lc listen_session=$ls session_port=$sp"'
'@
        $remoteCmd = $remoteCmd.Replace('PORTPLACEHOLDER', $sessionPort)

        $outLines = @()
        try {
            $outLines = @(SshX $remoteCmd)
        } catch {
            $script:LastAgentPathResult = @{ Ok = $false; ConfPort = ''; Reason = 'probe_fail' }
            Write-ConnectLog ("AGENT_PATH bad reason=probe_fail session_port={0} conf_port= conf_am= listen_conf= listen_session= primary_match=0" -f $sessionPort) 'WARN'
            return
        }

        $joined = ($outLines | ForEach-Object { "$_" }) -join "`n"
        $probeLine = $null
        foreach ($ln in $outLines) {
            $s = ("$ln").Trim()
            if ($s -match 'AGENT_PATH_PROBE\b') { $probeLine = $s; break }
        }
        if (-not $probeLine -and $joined -match '(?m)(AGENT_PATH_PROBE\b[^\r\n]*)') {
            $probeLine = $Matches[1].Trim()
        }
        if (-not $probeLine) {
            $script:LastAgentPathResult = @{ Ok = $false; ConfPort = ''; Reason = 'probe_fail' }
            Write-ConnectLog ("AGENT_PATH bad reason=probe_fail session_port={0} conf_port= conf_am= listen_conf= listen_session= primary_match=0" -f $sessionPort) 'WARN'
            return
        }

        $confPort = ''
        $confAm = ''
        $listenConf = ''
        $listenSession = ''
        if ($probeLine -match 'conf_port=([^\s]*)') { $confPort = $Matches[1] }
        if ($probeLine -match 'conf_am=([^\s]*)') { $confAm = $Matches[1] }
        if ($probeLine -match 'listen_conf=([^\s]*)') { $listenConf = $Matches[1] }
        if ($probeLine -match 'listen_session=([^\s]*)') { $listenSession = $Matches[1] }

        $primaryMatch = if ($confPort -and $confPort -eq $sessionPort) { 1 } else { 0 }
        $reason = ''
        $ok = $true
        if (-not $confPort) {
            $ok = $false
            $reason = 'conf_empty'
        } elseif ("$listenConf" -eq '0') {
            $ok = $false
            $reason = 'conf_port_closed'
        }

        $script:LastAgentPathResult = @{
            Ok       = $ok
            ConfPort = $confPort
            Reason   = $reason
        }

        if ($ok) {
            Write-ConnectLog ("AGENT_PATH ok session_port={0} conf_port={1} conf_am={2} listen_conf={3} listen_session={4} primary_match={5}" -f `
                $sessionPort, $confPort, $confAm, $listenConf, $listenSession, $primaryMatch) 'INFO'
        } else {
            Write-ConnectLog ("AGENT_PATH bad reason={0} session_port={1} conf_port={2} conf_am={3} listen_conf={4} listen_session={5} primary_match={6}" -f `
                $reason, $sessionPort, $confPort, $confAm, $listenConf, $listenSession, $primaryMatch) 'WARN'
        }
    } catch {
        # Fail-open: never break the status-line loop.
    }
}

function Write-ConnectScorecard {
    param(
        [Parameter(Mandatory)][ValidateSet('boot', 'end')][string]$Phase
    )
    # #19: always-on day-log INFO Ã¢â‚¬â€ not gated by CLAUDE_CONNECT_PERF_LOG.
    if (-not (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue)) { return }
    $ver = if ($script:ConnectVersion) { $script:ConnectVersion } else { 'unknown' }
    $am = 'none'
    if ($script:ActiveProjectId) { $am = [string]$script:ActiveProjectId }
    elseif ($script:LastPushConfActive) { $am = [string]$script:LastPushConfActive }
    $auth = 'n/a'
    if ($null -ne $script:ConnectPerf -and $null -ne $script:ConnectPerf.AuthMs) {
        $auth = [string][int]$script:ConnectPerf.AuthMs
    } elseif ($script:CursorAuthStampCurrent) {
        $auth = 'stamp_skip'
    }
    $banner = 'n/a'
    if ($null -ne $script:TunnelBannerCacheUp) { $banner = if ($script:TunnelBannerCacheUp) { 'ok' } else { 'soft' } }
    $mount = 'n/a'
    if ($null -ne $script:ConnectPerf -and $null -ne $script:ConnectPerf.MountMs) {
        $mount = [string][int]$script:ConnectPerf.MountMs
    }
    # Prefer $script:EditorOpened (wired by connect.ps1). Scope-1 $editorOpened is secondary.
    # Do NOT OR $script:EditorSeenOpen here - sticky SeenOpen alone causes false-green SCORECARD.
    $edOpen = $false
    if ($null -ne $script:EditorOpened) {
        $edOpen = [bool]$script:EditorOpened
    } elseif (Get-Variable -Name editorOpened -Scope 1 -ErrorAction SilentlyContinue) {
        try { $edOpen = [bool](Get-Variable -Name editorOpened -Scope 1 -ValueOnly) } catch { $edOpen = $false }
    }
    $ed = if ($edOpen) { 'open' } else { 'closed' }
    $slot = ($env:CLAUDE_CONNECT_UI_SLOT + '')
    if (-not $slot) { $slot = '0' }
    $line = ("SCORECARD {0} auth_ms={1} banner={2} mount_ms={3} am={4} editor={5} slot={6} ver={7}" -f `
        $Phase, $auth, $banner, $mount, $am, $ed, $slot, $ver)
    $sessionPortSc = ''
    if ($null -ne $script:Port -and ("$($script:Port)").Trim().Length -gt 0) {
        $sessionPortSc = ("$($script:Port)" -replace '\D', '')
    } elseif ($Port -and ("$Port").Trim().Length -gt 0) {
        $sessionPortSc = ("$Port" -replace '\D', '')
    }
    if ($sessionPortSc) { $line = "$line port=$sessionPortSc" }
    if ($null -ne $script:LastAgentPathResult) {
        $apConf = ''
        try { $apConf = [string]$script:LastAgentPathResult.ConfPort } catch { $apConf = '' }
        $apState = if ($script:LastAgentPathResult.Ok) { 'ok' } else { 'bad' }
        $line = "$line conf_port=$apConf agent_path=$apState"
    }
    Write-ConnectLog $line 'INFO'
    if ($env:CLAUDE_CONNECT_SCORECARD_UI -eq '1') {
        Write-Host ("  {0}" -f $line) -ForegroundColor DarkGray
    }
}

function Write-ConnectSessionOpenSummary {
    if (-not (Test-ConnectPerfEnabled)) { return }
    if (-not $script:ConnectPerf) { return }
    $p = $script:ConnectPerf
    $cim = if ($null -ne $script:LaunchCimCallCount) { $script:LaunchCimCallCount } else { 0 }
    $fixes = if ($script:LaunchPerfFixes) { ($script:LaunchPerfFixes -join ',') } else { 'unknown' }
    $ver = if ($script:ConnectVersion) { $script:ConnectVersion } else { 'unknown' }
    Write-ConnectPerfLog -Mark 'session_open_summary' -Ms 0 -Extra (
        "mount_ms=$($p.MountMs) auth_ms=$($p.AuthMs) open_ms=$($p.OpenMs) diag_ms=$($p.DiagMs) " +
        "ssh_total_ms=$($p.SshMsTotal) ssh_count=$($p.SshCount) cim_total=$cim fixes=$fixes version=$ver"
    )
}

function Write-ConnectSessionContext {
    param(
        [Parameter(Mandatory)][string]$Phase
    )
    if (-not (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue)) { return }
    $gm = '?'
    if (Get-Command Get-GitMode -ErrorAction SilentlyContinue) {
        try { $gm = Get-GitMode } catch { $gm = '?' }
    }
    $am = 'none'
    if ($script:ActiveProjectId) { $am = $script:ActiveProjectId }
    elseif ($script:ActiveMountId) { $am = $script:ActiveMountId }
    elseif ($go -and $go.Id) { $am = $go.Id }
    $edOpen = if ($null -ne $script:EditorOpened) { $script:EditorOpened } else { $false }
    if (Get-Variable -Name editorOpened -Scope 1 -ErrorAction SilentlyContinue) {
        try { $edOpen = [bool](Get-Variable -Name editorOpened -Scope 1 -ValueOnly) } catch { }
    }
    $alDown = if ($null -ne $script:AlreadyDown) { $script:AlreadyDown } else { $false }
    if (Get-Variable -Name alreadyDown -Scope 1 -ErrorAction SilentlyContinue) {
        try { $alDown = [bool](Get-Variable -Name alreadyDown -Scope 1 -ValueOnly) } catch { }
    }
    $editorPref = '?'
    if ($CfgDir -and (Get-Command Get-EditorPref -ErrorAction SilentlyContinue)) {
        try { $editorPref = Get-EditorPref -CfgDir $CfgDir } catch { }
    }
    $hostName = try { [System.Net.Dns]::GetHostName() } catch { $env:COMPUTERNAME }
    $os = [Environment]::OSVersion.VersionString
    $elev = 'unknown'
    if (Get-Command Test-IsElevatedShell -ErrorAction SilentlyContinue) {
        $elev = if (Test-IsElevatedShell) { 'yes' } else { 'no' }
    }
    $goId = if ($go -and $go.Id) { $go.Id } else { '?' }
    $goPath = if ($go -and $go.Path) { $go.Path } else { '?' }
    $goRpath = if ($go -and $go.Rpath) { $go.Rpath } else { '?' }
    $ru = if ($RemoteUser) { $RemoteUser } else { '?' }
    $sip = if ($ServerIP) { $ServerIP } else { '?' }
    $al = if ($Alias) { $Alias } else { '?' }
    $pt = if ($Port) { $Port } else { '?' }
    $ed = if ($EditorCmd) { $EditorCmd } else { '?' }
    Write-ConnectLog "======== CONTEXT phase=$Phase ========"
    Write-ConnectLog "host=$hostName os=$os user=$env:USERNAME laptop_user=$($script:LaptopUser) elevated=$elev pid=$PID"
    Write-ConnectLog "REMOTE_USER=$ru SERVER_IP=$sip ALIAS=$al PORT=$pt CONNECT_VERSION=$($script:ConnectVersion) BUILD_ID=$($script:ConnectBuildId)"
    Write-ConnectLog "GIT_MODE=$gm ACTIVE_MOUNT=$am EDITOR=$ed EDITOR_PREF=$editorPref LAPTOP_OS=windows"
    Write-ConnectLog "flags editor_opened=$edOpen already_down=$alDown recovery_gen=$($script:RecoveryGeneration) session_iter=$($script:SessionLoopIter)"
    Write-ConnectLog "paths Cfg=$Cfg CfgDir=$CfgDir ScriptDir=$($script:ConnectScriptDir) SshDir=$SshDir"
    Write-ConnectLog "project id=$goId server_path=$goPath laptop_path=$goRpath"
    if ($Cfg -and (Test-Path -LiteralPath $Cfg)) {
        try {
            $snip = ((Get-Content -LiteralPath $Cfg -Raw -ErrorAction Stop) -replace '\s+', ' ').Trim()
            if ($snip.Length -gt 400) { $snip = $snip.Substring(0, 400) }
            Write-ConnectLog "local_cfg: $snip" 'DEBUG'
        } catch { }
    }
    if ($Phase -eq 'project_selected' -or $Phase -eq 'session_end') {
        $proj = if ($goId -ne '?') { $goId } else { '-' }
        Write-ConnectSessionIndex -Phase $Phase -Project $proj
    }
    if ($Phase -eq 'session_end') {
        if (Get-Command Complete-ConnectLogAsyncDrain -ErrorAction SilentlyContinue) {
            Complete-ConnectLogAsyncDrain -Force
        } elseif (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {
            Sync-ConnectLogToServer -Force | Out-Null
        }
    } elseif (Get-Command Request-ConnectLogSync -ErrorAction SilentlyContinue) {
        # Bug 9 fix (2026-07-24, live repro): this ran on EVERY CONTEXT phase transition
        # (startup/project_selected/session_loop/server_ready/...), not just session_end -
        # without -NoInline, Request-ConnectLogSync's own "small backlog" branch still runs
        # Sync-ConnectLogToServer INLINE (blocking) whenever the unsynced backlog happens to be
        # under its 64KB gate; under real network/server contention that inline call's own
        # sequential sub-calls (probe/chunk-check/mkdir/scp, ~2.5-4s each) can still chain up to
        # ~17s, and TWO phase transitions firing close together (observed live: project_selected
        # then session_loop within seconds) stacked to a genuine ~36s UI freeze right after
        # project selection - exactly the "looked like Preparing tunnel / Checking SSH hung"
        # symptom this file's own Request-ConnectLogSync comment (~line 889) already warns about
        # for inline sync, just not routed through -NoInline here. Routine phase-context logging
        # must never risk a blocking sync - only session_end (handled above, unconditionally
        # forced) legitimately needs a guaranteed flush before the process exits.
        Request-ConnectLogSync -NoInline
    } elseif (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {
        Sync-ConnectLogToServer | Out-Null
    }
}


function Close-ConnectLog {
    if (-not $script:ConnectLogWriter) {
        if (Get-Command Complete-ConnectLogAsyncDrain -ErrorAction SilentlyContinue) {
            Complete-ConnectLogAsyncDrain -Force
        } elseif (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {
            Sync-ConnectLogToServer -Force | Out-Null
        }
        Exit-ConnectSingleInstance
        return
    }
    try {
        if (Get-Command Write-ConnectSessionContext -ErrorAction SilentlyContinue) {
            Write-ConnectSessionContext -Phase 'session_end'
        }
        Write-ConnectLog '======== session end ========'
        $script:ConnectLogWriter.Flush()
        $script:ConnectLogWriter.Dispose()
    } catch { }
    $script:ConnectLogWriter = $null
    if (Get-Command Complete-ConnectLogAsyncDrain -ErrorAction SilentlyContinue) {
        Complete-ConnectLogAsyncDrain -Force
    } elseif (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {
        Sync-ConnectLogToServer -Force | Out-Null
    }
    # Keep durable local day log so offline / failed-SSH sessions remain auditable.
    $script:ConnectLogPath = ''
    $script:ConnectLogSyncOffset = 0
    Exit-ConnectSingleInstance
}

function Get-TerminalWidth {
    try {
        if ($Host.Name -eq 'ConsoleHost') {
            $w = [Console]::WindowWidth
            $b = [Console]::BufferWidth
            if ($w -gt 0 -and $b -gt 0) { return [Math]::Max(40, [Math]::Min($w, $b)) }
        }
    } catch { }
    return 80
}

function Get-LayoutTier {
    param([int]$Width = (Get-TerminalWidth))
    if ($Width -ge 100) { return 'wide' }
    if ($Width -ge 72)  { return 'normal' }
    if ($Width -ge 60)  { return 'narrow' }
    return 'tiny'
}

function Format-TruncPath {
    param(
        [string]$Path,
        [int]$MaxLen = 40
    )
    if (-not $Path) { return '' }
    if ($Path.Length -le $MaxLen) { return $Path }
    $head = [Math]::Max(8, [int]($MaxLen * 0.4))
    $tail = $MaxLen - $head - 3
    if ($tail -lt 4) { return $Path.Substring(0, $MaxLen - 3) + '...' }
    return $Path.Substring(0, $head) + '...' + $Path.Substring($Path.Length - $tail)
}

function Format-TruncLabel {
    param(
        [string]$Text,
        [int]$MaxLen
    )
    if (-not $Text) { return '' }
    if ($MaxLen -le 0) { return $Text }
    if ($Text.Length -le $MaxLen) { return $Text }
    if ($MaxLen -le 3) { return '...' }
    return $Text.Substring(0, $MaxLen - 3) + '...'
}

function Get-ProjectNameColWidth {
    param(
        [array]$Mounts,
        [int]$TerminalWidth,
        [int]$PathMax
    )
    if (-not $Mounts -or $Mounts.Count -eq 0) { return 14 }
    $maxLabel = ($Mounts | ForEach-Object { $_.Label.Length } | Measure-Object -Maximum).Maximum
    if (-not $maxLabel) { $maxLabel = 10 }
    # Longest label + " (mounted)" must fit in the name column
    $want = $maxLabel + 10
    $fixed = 4 + 2 + 2 + 2 + $PathMax
    $avail = $TerminalWidth - $fixed
    if ($avail -lt 10) { return 0 }
    return [Math]::Max(10, [Math]::Min($want, $avail))
}

function Write-ConnectHeader {
    param(
        [string]$Alias,
        [string]$ServerIP,
        [string]$Version
    )
    $W = Get-TerminalWidth
    $tier = Get-LayoutTier -Width $W
    Write-Host ''
    # Version intentionally not shown on screen (still logged to file/server via
    # Write-ConnectLog "ENV version=..." elsewhere) - user-facing request to keep the
    # console header free of the build number.
    if ($tier -eq 'tiny') {
        Write-Host '    --- Claude Connect ---' -ForegroundColor Cyan
        Write-Host "    $Alias  |  $ServerIP" -ForegroundColor DarkGray
    } else {
        $inner = [Math]::Min(44, $W - 4)
        $line = ('=' * $inner)
        Write-Host "    +$line+" -ForegroundColor Cyan
        Write-Host ('    |' + ' Claude Connect '.PadRight($inner) + '|') -ForegroundColor Cyan
        Write-Host "    +$line+" -ForegroundColor Cyan
        Write-Host "    $Alias  |  $ServerIP" -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Write-GitModeBanner {
    param([string]$GitMode)
    # Get-GitModeLabel lives in git-mode.ps1 (dot-sourced before this file)
    $label = Get-GitModeLabel -Mode $GitMode
    $W = Get-TerminalWidth
    if ((Get-LayoutTier -Width $W) -eq 'tiny') {
        Write-Host "    Git: $label (g to change)" -ForegroundColor DarkGray
    } else {
        $desc = switch ($GitMode) {
            'server' { 'full git over SSHFS' }
            'hide'   { 'hide .git on laptop' }
            default  { 'no .git rename; laptop-exec git' }
        }
        Write-Host "    Git mode: $label ($desc) - press g to change" -ForegroundColor DarkGray
    }
    Write-Host ''
}

function Write-ProjectTable {
    param(
        [array]$Mounts
    )
    $W = Get-TerminalWidth
    $tier = Get-LayoutTier -Width $W
    Write-Host '    Projects' -ForegroundColor White
    Write-Host ''
    if ($Mounts.Count -eq 0) {
        Write-Host '    (no projects configured)' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '    a add   u update   q quit' -ForegroundColor DarkGray
        Write-Host ''
        return
    }
    $pathMax = if ($tier -eq 'wide') { 50 } elseif ($tier -eq 'normal') { 36 } elseif ($tier -eq 'narrow') { 24 } else { 0 }
    $nameCol = if ($pathMax -gt 0) { Get-ProjectNameColWidth -Mounts $Mounts -TerminalWidth $W -PathMax $pathMax } else { 0 }
    if ($pathMax -gt 0 -and $nameCol -eq 0) {
        $tier = 'tiny'
        $pathMax = 0
    }
    $i = 1
    foreach ($m in $Mounts) {
        if ($m.Rpath -and -not (Test-LaptopRpathCompatible -Rpath $m.Rpath -Os 'windows')) { continue }
        $activeTag = if ($m.Mounted -or $m.Active) { ' (mounted)' } else { '' }
        $osTag = ''
        if ($m.Rpath -and -not (Test-LaptopRpathExists -Rpath $m.Rpath)) { $osTag = ' [missing]' }
        $name = $m.Label
        if ($tier -eq 'tiny') {
            $fg = if ($m.Active) { 'White' } else { 'DarkGray' }
            Write-Host ("    {0}  {1}{2}" -f $i, $name, $activeTag) -ForegroundColor $fg
            if ($m.Rpath) {
                Write-Host ("         {0}" -f ((Format-TruncPath -Path $m.Rpath -MaxLen 56) + $osTag)) -ForegroundColor DarkGray
            }
        } elseif ($pathMax -gt 0) {
            $pathShow = (Format-TruncPath -Path $m.Rpath -MaxLen $pathMax) + $osTag
            $nameMax = $nameCol - $activeTag.Length
            $nameShow = Format-TruncLabel -Text $name -MaxLen $nameMax
            $fmt = "    {0,2}  {1,-$nameCol}  {2}"
            if ($m.Active) {
                Write-Host ($fmt -f $i, ($nameShow + $activeTag), $pathShow) -ForegroundColor White
            } else {
                Write-Host ($fmt -f $i, $nameShow, $pathShow) -ForegroundColor DarkGray
            }
        }
        $i++
    }
    Write-Host ''
    Write-Host '    a add   e edit   d delete   c config   u update   q quit' -ForegroundColor DarkGray
    Write-Host ''
}

function Write-SessionBox {
    param(
        [string[]]$ExtraLines = @()
    )
    # Compact one-liner (the framed multi-line "Session active" box was visual noise).
    # Hotkeys still work; the live status line prints right after this.
    Write-Host ''
    Write-Host '    H hygiene   R reconnect   O reopen   Q disconnect' -ForegroundColor DarkGray
}


function Resolve-ConnectProxyServerHostPort {
    param([string]$Raw)
    $s = ($Raw + '').Trim()
    if (-not $s) { return '' }
    if ($s -match '(?i)(?:^|[;\s])https?=([^;\s]+)') { return $Matches[1].Trim() }
    if ($s -match '(?i)(?:^|[;\s])http=([^;\s]+)') { return $Matches[1].Trim() }
    if ($s -match '(?i)socks=([^;\s]+)') { return $Matches[1].Trim() }
    return ([string](($s -split ';' | Select-Object -First 1) + '')).Trim()
}

function Get-ConnectProxyUrl {
    param([string]$HostPort)
    $hp = ($HostPort + '').Trim()
    if (-not $hp) { return '' }
    if ($hp -match '^https?://') { return $hp }
    return "http://$hp"
}

function Test-ConnectHostMatchesBypassPattern {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][string]$Pattern
    )
    $pat = ($Pattern + '').Trim()
    if (-not $pat) { return $false }
    if ($pat -eq '<local>') {
        return ($HostName -match '^(?i)(localhost|127\.\d+\.\d+\.\d+|\[::1\]|::1)')
    }
    if ($pat -notmatch '[\*\?]') {
        return ($HostName -ieq $pat)
    }
    $rx = [regex]::Escape($pat) -replace '\\\*', '.*' -replace '\\\?', '.'
    return ($HostName -match "^$rx$")
}

function Test-ConnectServerBypassesProxy {
    param(
        [Parameter(Mandatory)][string]$ServerIP,
        [string[]]$Bypass = @()
    )
    if ($ServerIP -match '^192\.168\.') { return $true }
    if ($ServerIP -match '^(?i)(localhost|127\.)') { return $true }
    foreach ($pat in @($Bypass)) {
        if (Test-ConnectHostMatchesBypassPattern -HostName $ServerIP -Pattern $pat) { return $true }
    }
    return $false
}

function Get-WindowsSystemProxy {
    $result = [PSCustomObject]@{
        Enabled = $false
        Server  = ''
        Bypass  = @()
        Source  = 'none'
    }

    try {
        $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        $reg = Get-ItemProperty -Path $regPath -ErrorAction Stop
        $enabled = ($null -ne $reg.ProxyEnable -and [int]$reg.ProxyEnable -eq 1)
        $serverRaw = if ($null -ne $reg.ProxyServer) { ($reg.ProxyServer + '').Trim() } else { '' }
        $bypass = @()
        if ($null -ne $reg.ProxyOverride -and ($reg.ProxyOverride + '').Trim()) {
            $bypass = @(
                ($reg.ProxyOverride -split '[;,]') |
                    ForEach-Object { ($_ + '').Trim() } |
                    Where-Object { $_ -and $_ -ne '<local>' }
            )
        }
        $server = Resolve-ConnectProxyServerHostPort -Raw $serverRaw
        if ($enabled -and $server) {
            $result.Enabled = $true
            $result.Server = $server
            $result.Bypass = $bypass
            $result.Source = 'ier'
            return $result
        }
    } catch { }

    try {
        $out = @(netsh winhttp show proxy 2>$null)
        if ($out.Count -eq 0) { return $result }
        $text = ($out -join "`n")
        if ($text -match '(?i)Direct access \(no proxy server\)') { return $result }

        $serverRaw = ''
        $bypass = @()
        foreach ($line in $out) {
            if ($line -match '(?i)Proxy Server\(s\)\s*:\s*(.+)') {
                $serverRaw = $Matches[1].Trim()
            }
            elseif ($line -match '(?i)Bypass List\s*:\s*(.+)') {
                $rawBypass = $Matches[1].Trim()
                if ($rawBypass -and $rawBypass -notmatch '(?i)^\(<\-loopback>\)$') {
                    $bypass = @(
                        ($rawBypass -replace '\(<\-loopback>\)\s*\|\s*', '' -split '[;,]') |
                            ForEach-Object { ($_ + '').Trim() } |
                            Where-Object { $_ -and $_ -ne '<local>' }
                    )
                }
            }
        }
        $server = Resolve-ConnectProxyServerHostPort -Raw $serverRaw
        if ($server -and $server -notmatch '(?i)direct') {
            $result.Enabled = $true
            $result.Server = $server
            $result.Bypass = $bypass
            $result.Source = 'winhttp'
        }
    } catch { }

    return $result
}

function Build-ConnectNoProxyList {
    param(
        [string[]]$Bypass = @(),
        [string]$ServerIP = ''
    )
    $items = [System.Collections.Generic.List[string]]::new()
    foreach ($x in @('localhost', '127.0.0.1', '192.168.*', '.local', '*.local')) {
        if ($items -notcontains $x) { [void]$items.Add($x) }
    }
    if ($ServerIP -and ($items -notcontains $ServerIP)) { [void]$items.Add($ServerIP) }
    foreach ($b in @($Bypass)) {
        $t = ($b + '').Trim()
        if ($t -and ($items -notcontains $t)) { [void]$items.Add($t) }
    }
    return ($items -join ',')
}

function Apply-ConnectProxyEnvironment {
    param([string]$ServerIp = '')
    $px = Get-WindowsSystemProxy
    $src = if ($px.Source) { $px.Source } else { 'none' }
    if (-not $px.Enabled -or -not $px.Server) {
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog "PROXY: enabled=0 source=$src"
        }
        $script:ConnectSystemProxy = $px
        return $px
    }

    $url = Get-ConnectProxyUrl -HostPort $px.Server
    $noProxy = Build-ConnectNoProxyList -Bypass @($px.Bypass) -ServerIP $ServerIp
    foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy')) {
        Set-Item -Path "Env:$name" -Value $url
    }
    foreach ($name in @('NO_PROXY', 'no_proxy')) {
        Set-Item -Path "Env:$name" -Value $noProxy
    }

    $script:ConnectSystemProxy = $px
    $safeServer = ($px.Server + '') -replace '^[^@/]*@', ''
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("PROXY: enabled=1 server={0} source={1}" -f $safeServer, $src)
    }
    return $px
}

function Find-ConnectProxyCommandTool {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Git\mingw64\bin\connect.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\mingw64\bin\connect.exe'),
        (Join-Path $env:ProgramFiles 'Git\usr\bin\connect.exe')
    )
    foreach ($c in @($candidates)) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    $cmd = Get-Command connect.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    return $null
}

function Get-ConnectSshProxyCommandArg {
    param([Parameter(Mandatory)][string]$ProxyHostPort)
    $hostPort = ($ProxyHostPort + '').Trim()
    if ($hostPort -match '^https?://') { $hostPort = ($hostPort -replace '^https?://', '') }
    if ($hostPort -match '@') { $hostPort = ($hostPort -replace '^[^@]+@', '') }
    $tool = Find-ConnectProxyCommandTool
    if (-not $tool) { return $null }
    return ('"{0}" -H {1} %h %p' -f $tool, $hostPort)
}

function Initialize-ConnectProxyForSsh {
    param([string]$ServerIP = '')
    $script:ConnectSshExtraOptions = @()
    $script:ConnectSshProxyCommand = $null
    $script:ConnectProxyLoggedSshNote = $false
    $info = Apply-ConnectProxyEnvironment -ServerIp $ServerIP
    if ($info.Enabled -and -not (Test-ConnectServerBypassesProxy -ServerIP $ServerIP -Bypass @($info.Bypass))) {
        $script:ConnectSshProxyCommand = Get-ConnectSshProxyCommandArg -ProxyHostPort $info.Server
    }
    return $info
}

function Invoke-ConnectBootstrapSsh {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [int]$ConnectTimeout = 15,
        [switch]$ViaProxy
    )
    $sshArgs = @(
        '-n',
        '-o', 'ClearAllForwardings=yes',
        '-o', 'BatchMode=yes',
        '-o', "ConnectTimeout=$ConnectTimeout"
    )
    if ($ViaProxy -and $script:ConnectSshProxyCommand) {
        $sshArgs += '-o', "ProxyCommand=$($script:ConnectSshProxyCommand)"
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & ssh @sshArgs $Alias 'true' 2>$null
    $sw.Stop()
    return [PSCustomObject]@{
        Exit     = $LASTEXITCODE
        Sec      = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        ViaProxy = [bool]$ViaProxy
    }
}

function Write-ConnectProxySshDirectFailedNote {
    param(
        $ProxyInfo,
        [bool]$ServerBypassesProxy
    )
    if ($script:ConnectProxyLoggedSshNote) { return }
    if (-not $ProxyInfo -or -not $ProxyInfo.Enabled) { return }
    $script:ConnectProxyLoggedSshNote = $true
    $note = if ($ServerBypassesProxy) { 'server_bypassed' }
            elseif (-not $script:ConnectSshProxyCommand) { 'ssh_may_need_ProxyCommand' }
            else { 'ssh_proxy_failed' }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "PROXY: ssh_direct_failed proxy_present=1 note=$note" 'WARN'
    }
}

function Set-ConnectTitle {
    param([string]$Text)
    try {
        $Host.UI.RawUI.WindowTitle = $Text
    } catch { }
}

function Update-SessionStatusLine {
    param(
        [string]$ProjectLabel,
        [string]$GitLabel,
        [bool]$TunnelOk,
        [bool]$EditorOpen,
        [string]$EditorName = 'Cursor',
        [string]$EditorLabel = '',
        [string]$EditorCmd = '',
        [string]$Alias = '',
        [string]$RemotePath = ''
    )
    $tunnel = if ($TunnelOk) { 'up' } else { 'down' }
    $ed = if ($EditorLabel) { $EditorLabel } elseif ($EditorOpen) { $EditorName } else { 'closed' }
    $line = ('    [{0} | git:{1} | tunnel:{2} | {3}]' -f $ProjectLabel, $GitLabel, $tunnel, $ed)
    $statusKey = "$ProjectLabel|$GitLabel|$tunnel|$ed"
    if ($statusKey -ne $script:LastSessionStatusKey) {
        $script:LastSessionStatusKey = $statusKey
        Write-Host $line -ForegroundColor DarkCyan
        Write-ConnectLog "STATUS: [$ProjectLabel | git:$GitLabel | tunnel:$tunnel | $ed]"
    }
    if ($TunnelOk) {
        try { Invoke-AgentPathProbe } catch { }
    }
    if ($EditorCmd -and $Alias -and $RemotePath) {
        if (-not $EditorOpen) {
            Write-ConnectTrace "STATUS_TICK project=$ProjectLabel tunnel=$tunnel editor=$ed git=$GitLabel"
            $nowUnix = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            if (($nowUnix - $script:LastHeartbeatUnix) -ge 60) {
                $script:LastHeartbeatUnix = $nowUnix
                $verboseLaunch = ($env:CLAUDE_CONNECT_VERBOSE_LAUNCH -eq '1')
                if ($verboseLaunch -and (Get-Command Get-RemoteEditorStateExplain -ErrorAction SilentlyContinue)) {
                    Write-ConnectLog "HEARTBEAT: $(Get-RemoteEditorStateExplain -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
                } else {
                    # Non-verbose: use the cached presence from the session poll instead of paying
                    # for another full (CIM-heavy) editor state walk every heartbeat.
                    $cached = $script:LastEditorPresence
                    if ($cached) {
                        $ageS = [int]((Get-Date) - $cached.At).TotalSeconds
                        Write-ConnectLog ("HEARTBEAT: light on_folder=$($cached.OnFolder) window_open=$($cached.WindowOpen) label=$($cached.Label) age_s=$ageS") 'DEBUG'
                    } else {
                        Write-ConnectLog "HEARTBEAT: light editor_open=$EditorOpen label=$ed" 'DEBUG'
                    }
                }
            }
        } else {
            Write-ConnectTrace "STATUS_OK project=$ProjectLabel tunnel=$tunnel editor=$ed"
        }
    }
}

function Show-ConnectToast {
    param([string]$Message)
    if (-not $Message) { return }
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $escaped = [System.Security.SecurityElement]::Escape($Message)
        $xml = '<toast><visual><binding template="ToastText01"><text id="1">' + $escaped + '</text></binding></visual></toast>'
        $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $doc.LoadXml($xml)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude.Connect').Show($toast)
    } catch {
        if (Get-Command Warn -ErrorAction SilentlyContinue) { Warn $Message }
    }
}

function Write-BootstrapHint {
    param([string]$CfgDir)
    $marker = [System.IO.Path]::Combine($CfgDir, 'bootstrap.done')
    if (Test-Path $marker) {
        Write-Host '    Reconnect ~15s' -ForegroundColor DarkGray
    } else {
        Write-Host '    First setup may take ~1 min' -ForegroundColor DarkGray
    }
}

function Mark-BootstrapDone {
    param([string]$CfgDir)
    $marker = [System.IO.Path]::Combine($CfgDir, 'bootstrap.done')
    Set-Content -Path $marker -Value (Get-Date -Format 'o') -Encoding ASCII -ErrorAction SilentlyContinue | Out-Null
}

function Pick-LaptopFolder {
    param([string]$Prompt = 'Select project folder on your laptop')
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = $Prompt
        $dlg.ShowNewFolderButton = $true
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return ($dlg.SelectedPath -replace '\\', '/')
        }
    } catch { }
    return $null
}

