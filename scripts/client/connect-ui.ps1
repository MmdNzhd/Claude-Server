# connect-ui.ps1 - terminal UI helpers (dot-sourced by connect.ps1)
# Requires: Warn, Step helpers may exist in parent scope

$script:ConnectLogWriter = $null
$script:ConnectLogPath = ''
$script:LastSessionStatusKey = ''
$script:ConnectUiReady = $false
$script:ConnectSessionId = ''

function Get-ConnectLogDir {
    $dir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch { }
    return $dir
}

function Get-ConnectLogDayPath {
    $day = Get-Date -Format 'yyyyMMdd'
    return (Join-Path (Get-ConnectLogDir) ("connect-{0}.log" -f $day))
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
            $raw = (Get-Content -LiteralPath $wp -Raw -ErrorAction SilentlyContinue + '').Trim()
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
    # Unlimited concurrent connect UIs. Tunnel slots (Acquire-TunnelPort 0..9) + session IDs isolate tunnels/logs.
    param([string]$Name = '')
    $script:ConnectInstanceMutex = $null
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("MULTI_INSTANCE: allowed pid={0} (no global mutex)" -f $PID) 'INFO'
    }
    return $true
}

function Exit-ConnectSingleInstance {
    # No-op: multi-instance mode does not hold a process-wide mutex.
    $script:ConnectInstanceMutex = $null
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
    # 4) Nightly cleanup on server (mtime +1) - space is fine during the day
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
    try {
        # FileShare.ReadWrite: second connect (or leftover session) must not silently disable logging.
        $fs = [System.IO.FileStream]::new(
            $script:ConnectLogPath,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite)
        $script:ConnectLogWriter = [System.IO.StreamWriter]::new($fs, [System.Text.UTF8Encoding]::new($false))
        $script:ConnectLogWriter.AutoFlush = $true
    } catch {
        $script:ConnectLogWriter = $null
        try { Write-Host ("[WARN] connect log open failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow } catch { }
        return
    }
    $elev = 'unknown'
    if (Get-Command Test-IsElevatedShell -ErrorAction SilentlyContinue) {
        $elev = if (Test-IsElevatedShell) { 'yes' } else { 'no' }
    }
    Write-ConnectLog "======== session start v$Version user=$env:USERNAME elevated=$elev pid=$PID session=$($script:ConnectSessionId) ========"
    Write-ConnectLog "SESSION_FILTER grep=[$($script:ConnectSessionId)] tip=filter day log by bracketed session id"
    Write-ConnectLog "log sink: local:$($script:ConnectLogPath) watermark=$($script:ConnectLogSyncOffset) + server:~/.claude/logs/ (nightly purge)"
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
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $outFile = Join-Path $env:TEMP ("claude-logsync-$id.out")
    $errFile = Join-Path $env:TEMP ("claude-logsync-$id.err")
    try {
        $p = Start-Process -FilePath $Exe -ArgumentList $ArgumentList `
            -NoNewWindow -PassThru `
            -RedirectStandardOutput $outFile `
            -RedirectStandardError $errFile
        if (-not $p.WaitForExit($TimeoutMs)) {
            try { $p.Kill() } catch { }
            return @{ Ok = $false; TimedOut = $true; ExitCode = -1 }
        }
        $ec = 0
        try { if ($null -ne $p.ExitCode) { $ec = [int]$p.ExitCode } } catch { }
        return @{ Ok = ($ec -eq 0); TimedOut = $false; ExitCode = $ec }
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
                        $script:ConnectLogWriter.WriteLine("[$ts] [WARN] [$sid] TEMP_CLEANUP_FAIL path=$f err=$($_.Exception.Message)")
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

    # Bug 72: serialize overlapping syncs (in-process + cross-process lock file).
    if ($script:ConnectLogSyncInProgress -and -not $Force) { return }
    $lockPath = $path + '.sync-lock'
    $lockStream = $null
    try {
        $lockStream = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None)
    } catch {
        if (-not $Force) { return }
        $deadline = (Get-Date).AddSeconds(3)
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
        $mk = 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; find "$HOME/.claude/logs" -type f -mtime +1 -delete 2>/dev/null; true'
        $sshOpts = @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no')
        # Bug 11: cat must surface append failure (no trailing true).
        $cat = 'cat "$HOME/' + $remoteTmp + '" >> "$HOME/' + $remoteDay + '"; ec=$?; rm -f "$HOME/' + $remoteTmp + '"; chmod 600 "$HOME/' + $remoteDay + '" 2>/dev/null; exit $ec'
        $mkRes = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList ($sshOpts + @($target, $mk)) -TimeoutMs 12000
        if (-not $mkRes.Ok) {
            if (-not $script:ConnectLogSyncFailLogged) {
                $script:ConnectLogSyncFailLogged = $true
                try {
                    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                    $sid = Get-ConnectSessionId
                    if ($script:ConnectLogWriter) {
                        $script:ConnectLogWriter.WriteLine("[$ts] [WARN] [$sid] LOG_SYNC_FAIL target=$target reason=mkdir_timeout_or_fail (local kept; retry later)")
                    }
                } catch { }
            }
            try { Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction Stop } catch {
                try {
                    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                    $sid = Get-ConnectSessionId
                    if ($script:ConnectLogWriter) {
                        $script:ConnectLogWriter.WriteLine("[$ts] [WARN] [$sid] TEMP_CLEANUP_FAIL path=$tmpLocal err=$($_.Exception.Message)")
                    }
                } catch { }
            }
            return
        }
        $scpRes = Invoke-ConnectLogProcTimed -Exe 'scp' -ArgumentList (@('-o','BatchMode=yes','-o','ConnectTimeout=12','-o','ControlMaster=no','-q', $tmpLocal, "${target}:$remoteTmp")) -TimeoutMs 20000
        # appendOk/scpOk := remote append succeeded (scp + cat). Watermark ONLY inside this gate.
        $appendOk = $false
        if ($scpRes.Ok) {
            $catRes = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList ($sshOpts + @($target, $cat)) -TimeoutMs 12000
            if ($catRes.Ok) { $appendOk = $true }
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
                    $script:ConnectLogWriter.WriteLine("[$ts] [WARN] [$sid] LOG_SYNC_FAIL target=$target (local kept; retry later)")
                }
            } catch { }
        }
        try { Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction Stop } catch {
            try {
                $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                $sid = Get-ConnectSessionId
                if ($script:ConnectLogWriter) {
                    $script:ConnectLogWriter.WriteLine("[$ts] [WARN] [$sid] TEMP_CLEANUP_FAIL path=$tmpLocal err=$($_.Exception.Message)")
                }
            } catch { }
        }
    } catch { }
    finally {
        $script:ConnectLogSyncInProgress = $false
        if ($lockStream) {
            try { $lockStream.Close() } catch { }
            try { $lockStream.Dispose() } catch { }
        }
    }
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
        $script:ConnectLogWriter = [System.IO.StreamWriter]::new($fs, [System.Text.UTF8Encoding]::new($false))
        $script:ConnectLogWriter.AutoFlush = $true
        return $true
    } catch {
        return $false
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
        $prevAuto = $script:ConnectLogWriter.AutoFlush
        if ($Level -eq 'TRACE' -or $Level -eq 'DEBUG') {
            # Buffer hot-loop noise locally; flush at most every 2s (AV/disk tax).
            $script:ConnectLogWriter.AutoFlush = $false
            $script:ConnectLogWriter.WriteLine("[$ts] [$Level] [$sid] $Message")
            $nowFlush = Get-Date
            if (-not $script:ConnectLogLastTraceFlushAt -or ($nowFlush - $script:ConnectLogLastTraceFlushAt).TotalSeconds -ge 2) {
                try { $script:ConnectLogWriter.Flush() } catch { }
                $script:ConnectLogLastTraceFlushAt = $nowFlush
            }
            $script:ConnectLogWriter.AutoFlush = $prevAuto
            # Bug 36: TUNNEL_* TRACE may carry soft_fail context - allow sync trigger.
            if ($Level -eq 'TRACE' -and $Message -match 'TUNNEL_') {
                $script:ConnectLogLinesSinceSync = [int]$script:ConnectLogLinesSinceSync + 1
                if ($Message -match 'soft_fail|TUNNEL_DROP|TUNNEL_EXIT' -or $script:ConnectLogLinesSinceSync -ge 25) {
                    try { $script:ConnectLogWriter.Flush() } catch { }
                    Sync-ConnectLogToServer
                }
            }
            return
        }
        # Flush any pending TRACE/DEBUG buffer so WARN/ERROR sync is not stuck waiting for 2s TRACE flush.
        try { $script:ConnectLogWriter.Flush() } catch { }
        $script:ConnectLogWriter.AutoFlush = $true
        $script:ConnectLogWriter.WriteLine("[$ts] [$Level] [$sid] $Message")
        # Local always complete. Sync carefully:
        # - TRACE/DEBUG stay local-only during hot loops except TUNNEL_* (above)
        # - WARN/ERROR Force-flush now (bypass TRACE batch + sync lock wait); INFO every 25 lines
        $script:ConnectLogLinesSinceSync = [int]$script:ConnectLogLinesSinceSync + 1
        if ($Level -eq 'ERROR') {
            Sync-ConnectLogToServer -Force
        } elseif ($Level -eq 'WARN') {
            Sync-ConnectLogToServer -Force
        } elseif ($script:ConnectLogLinesSinceSync -ge 25) {
            Sync-ConnectLogToServer
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
    return $val
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
    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer -Force | Out-Null }
    if ($script:ConnectUiReady) {
        try { Read-Host '    Press Enter to close' | Out-Null } catch { }
    }
    if (Get-Command Close-ConnectLog -ErrorAction SilentlyContinue) { Close-ConnectLog }
    exit $Code
}

function Write-ConnectDecision {
    param(
        [Parameter(Mandatory)][string]$What,
        [Parameter(Mandatory)][string]$Value,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    Write-ConnectLog ("DECISION: {0}={1}" -f $What, $Value) $Level
}

function Write-ConnectTrace {
    param([Parameter(Mandatory)][string]$Message)
    Write-ConnectLog $Message 'TRACE'
}

function Write-ConnectPhaseLog {
    param(
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    Write-ConnectLog "${Phase}: $Message" $Level
}

function Write-ConnectTimedLog {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][int]$Ms,
        [string]$Detail = '',
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    $suffix = if ($Detail) { " $Detail" } else { '' }
    Write-ConnectLog "${Label} ms=$Ms$suffix" $Level
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

function Invoke-ConnectPerfBlock {
    param(
        [Parameter(Mandatory)][string]$Mark,
        [Parameter(Mandatory)][scriptblock]$Block,
        [string]$Extra = ''
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        return & $Block
    } finally {
        $sw.Stop()
        Write-ConnectPerfLog -Mark $Mark -Ms $sw.ElapsedMilliseconds -Extra $Extra
    }
}



function Invoke-ConnectSilentUpdateCheck {
    if (-not (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue)) { return }

    $cfgDir = Join-Path $env:USERPROFILE '.config\claude-connect'
    $stateFile = Join-Path $cfgDir '.last-update-check'
    $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    $lastCheck = 0
    if (Test-Path -LiteralPath $stateFile) {
        try {
            $raw = (Get-Content -LiteralPath $stateFile -Raw -ErrorAction Stop).Trim()
            if ($raw -match '^\d+$') { $lastCheck = [int]$raw }
        } catch { }
    }

    $ageSec = if ($lastCheck -gt 0) { $now - $lastCheck } else { [int]::MaxValue }
    $ageMin = if ($ageSec -ge 0 -and $ageSec -lt [int]::MaxValue) { [int][Math]::Floor($ageSec / 60.0) } else { 0 }

    if ($lastCheck -gt 0 -and $ageSec -lt 1800) {
        Write-ConnectLog "UPDATE_SILENT skip reason=throttle age_min=$ageMin" 'DEBUG'
        return
    }

    $scriptDir = $null
    if ($script:ConnectScriptDir) { $scriptDir = $script:ConnectScriptDir }
    elseif ($PSScriptRoot) { $scriptDir = $PSScriptRoot }
    if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

    $updateScript = Join-Path $scriptDir 'connect-update.ps1'
    $exitCode = 1
    $result = 'fail'
    $pendingRestart = 0
    $level = 'ERROR'

    try {
        if (-not (Test-Path -LiteralPath $updateScript)) {
            Write-ConnectLog "UPDATE_SILENT age_min=$ageMin result=fail exit=1 pending_restart=0 reason=no_script path=$updateScript" 'ERROR'
        } else {
            & $updateScript -ScriptDir $scriptDir -Quiet
            if ($null -ne $LASTEXITCODE) { $exitCode = [int]$LASTEXITCODE } else { $exitCode = 0 }

            switch ($exitCode) {
                0 { $result = 'ok'; $level = 'INFO' }
                1 { $result = 'fail'; $level = 'ERROR' }
                2 { $result = 'applied'; $pendingRestart = 1; $level = 'WARN' }
                default { $result = 'fail'; $level = 'ERROR' }
            }
            Write-ConnectLog "UPDATE_SILENT age_min=$ageMin result=$result exit=$exitCode pending_restart=$pendingRestart" $level
        }
    } catch {
        Write-ConnectLog "UPDATE_SILENT age_min=$ageMin result=fail exit=1 pending_restart=0 error=$($_.Exception.Message)" 'ERROR'
    } finally {
        try {
            $null = New-Item -ItemType Directory -Force -Path $cfgDir
            [System.IO.File]::WriteAllText($stateFile, [string]$now, [System.Text.UTF8Encoding]::new($false))
        } catch {
            Write-ConnectLog "UPDATE_SILENT stamp_fail error=$($_.Exception.Message)" 'ERROR'
        }
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
    Write-ConnectLog "REMOTE_USER=$ru SERVER_IP=$sip ALIAS=$al PORT=$pt CONNECT_VERSION=$($script:ConnectVersion)"
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
    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null }
}


function Close-ConnectLog {
    if (-not $script:ConnectLogWriter) {
        if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer -Force | Out-Null }
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
    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer -Force | Out-Null }
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
    # Longest label + " (active)" must fit in the name column
    $want = $maxLabel + 9
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
    if ($tier -eq 'tiny') {
        Write-Host '    --- Claude Connect ---' -ForegroundColor Cyan
        Write-Host "    $Alias  |  $ServerIP  |  v$Version" -ForegroundColor DarkGray
    } else {
        $inner = [Math]::Min(44, $W - 4)
        $line = ('=' * $inner)
        Write-Host "    +$line+" -ForegroundColor Cyan
        Write-Host ('    |' + ' Claude Connect '.PadRight($inner) + '|') -ForegroundColor Cyan
        Write-Host "    +$line+" -ForegroundColor Cyan
        Write-Host "    $Alias  |  $ServerIP  |  v$Version" -ForegroundColor DarkGray
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
        $activeTag = if ($m.Active) { ' (active)' } else { '' }
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
    Write-Host '    a add   e edit   d delete   c config   g git   q quit' -ForegroundColor DarkGray
    Write-Host ''
}

function Write-SessionBox {
    param(
        [string[]]$ExtraLines = @()
    )
    Write-Host ''
    Write-Host '    ============================================' -ForegroundColor DarkGray
    Write-Host '    Session active -- keep this window open' -ForegroundColor Cyan
    Write-Host '    G = git mode   R = reconnect   O = reopen editor   Q or Enter = disconnect' -ForegroundColor DarkGray
    Write-Host '    Tip: File > Exit Cursor before Q so Agent chat history saves' -ForegroundColor DarkGray
    foreach ($ln in $ExtraLines) {
        Write-Host "    $ln" -ForegroundColor Yellow
    }
    Write-Host '    ============================================' -ForegroundColor DarkGray
    Write-Host ''
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
    Write-Host $line -ForegroundColor DarkCyan
    $statusKey = "$ProjectLabel|$GitLabel|$tunnel|$ed"
    if ($statusKey -ne $script:LastSessionStatusKey) {
        $script:LastSessionStatusKey = $statusKey
        Write-ConnectLog "STATUS: [$ProjectLabel | git:$GitLabel | tunnel:$tunnel | $ed]"
    }
    if ($EditorCmd -and $Alias -and $RemotePath) {
        if (-not $EditorOpen) {
            Write-ConnectTrace "STATUS_TICK project=$ProjectLabel tunnel=$tunnel editor=$ed git=$GitLabel"
            if (Get-Command Get-RemoteEditorStateExplain -ErrorAction SilentlyContinue) {
                Write-ConnectLog "HEARTBEAT: $(Get-RemoteEditorStateExplain -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)" 'DEBUG'
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

