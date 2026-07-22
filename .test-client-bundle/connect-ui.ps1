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
        [string[]]$SshOpts
    )
    # Lightweight remote size probe. -1 = probe failed (do not treat as reconcile success).
    $cmd = 'stat -c%s "$HOME/.claude/logs/connect-' + $Day + '.log" 2>/dev/null || echo 0'
    try {
        $argList = @()
        if ($SshOpts) { $argList += $SshOpts }
        $argList += @('-o', 'ConnectTimeout=6', $Target, $cmd)
        $raw = (& ssh @argList 2>$null | Out-String).Trim()
        $digits = ($raw -replace '[^0-9]', '')
        if (-not $digits) { return [int64](-1) }
        return [int64]$digits
    } catch {
        return [int64](-1)
    }
}

function Test-ConnectLogChunkAlreadyRemote {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Day,
        [Parameter(Mandatory)][byte[]]$Chunk,
        [Parameter(Mandatory)][int]$Take,
        [string[]]$SshOpts
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
        $raw = ((& ssh @argList 2>$null) | Out-String).Trim().ToLowerInvariant()
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
    $script:ConnectLogSyncNeeded = $false
    $script:ConnectLogWarnPendingUntil = $null
    $script:ConnectLogAsyncDrainerRunning = $false
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
            return @{ Ok = $false; TimedOut = $true; ExitCode = -1 }
        }
        $ec = $p.ExitCode
        try { [System.IO.File]::WriteAllText($outFile, $outTask.Result) } catch { }
        try { [System.IO.File]::WriteAllText($errFile, $errTask.Result) } catch { }
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
        # --- LOG_SYNC_RECONCILE: stop duplicate appends when cat succeeded but watermark timed out ---
        $pending = Read-ConnectLogSyncPending -LogPath $path
        if ($pending -and $pending.Offset -eq $off -and $pending.Take -eq $take) {
            $rNow = Get-ConnectRemoteLogByteSize -Target $target -Day $day -SshOpts $sshOpts
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
                        $script:ConnectLogWriter.WriteLine("[$ts] [INFO] [$sid] LOG_SYNC_RECONCILE pending_ok off=$off take=$take remote=$rNow (skipped re-append)")
                    }
                } catch { }
                try { Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue } catch { }
                return
            }
        }
        if (Test-ConnectLogChunkAlreadyRemote -Target $target -Day $day -Chunk $chunk -Take $take -SshOpts $sshOpts) {
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
                    $script:ConnectLogWriter.WriteLine("[$ts] [INFO] [$sid] LOG_SYNC_RECONCILE tail_hash_match off=$off take=$take (skipped re-append)")
                }
            } catch { }
            try { Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue } catch { }
            return
        }
        $remoteBefore = Get-ConnectRemoteLogByteSize -Target $target -Day $day -SshOpts $sshOpts
        if ($remoteBefore -lt 0) { $remoteBefore = [int64]0 }
        Write-ConnectLogSyncPending -Offset $off -Take $take -RemoteBefore $remoteBefore -LogPath $path

        $mk = 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; find "$HOME/.claude/logs" -type f -mtime +1 -delete 2>/dev/null; true'
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
        # Even if the timed wait says fail, the remote cat may have succeeded — verify by size.
        if (-not $appendOk) {
            $remoteAfter = Get-ConnectRemoteLogByteSize -Target $target -Day $day -SshOpts $sshOpts
            if ($remoteAfter -ge 0 -and $remoteAfter -ge ($remoteBefore + [int64]$take)) {
                $appendOk = $true
                try {
                    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                    $sid = Get-ConnectSessionId
                    if ($script:ConnectLogWriter) {
                        $script:ConnectLogWriter.WriteLine("[$ts] [INFO] [$sid] LOG_SYNC_RECONCILE size_verify ok before=$remoteBefore after=$remoteAfter take=$take (timeout false-negative)")
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
                    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {
                        Sync-ConnectLogToServer | Out-Null
                    }
                    if ($script:ConnectLogWarnPendingUntil -and (Get-Date) -ge $script:ConnectLogWarnPendingUntil) {
                        $script:ConnectLogWarnPendingUntil = $null
                    }
                    if (-not $script:ConnectLogWarnPendingUntil) {
                        $script:ConnectLogSyncNeeded = $false
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
    param([switch]$Force)
    if ($Force) {
        Complete-ConnectLogAsyncDrain -Force
        return
    }
    $alreadyNeeded = [bool]$script:ConnectLogSyncNeeded
    $script:ConnectLogSyncNeeded = $true
    Ensure-ConnectLogAsyncTimer
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
        # Drain any coalesced Needed/WARN state before the (optional) final Force sync.
        if (($script:ConnectLogSyncNeeded -or $script:ConnectLogWarnPendingUntil) -and (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue)) {
            try { Sync-ConnectLogToServer | Out-Null } catch { }
        }
        $script:ConnectLogSyncNeeded = $false
        $script:ConnectLogWarnPendingUntil = $null
        if ($Force -and (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue)) {
            Sync-ConnectLogToServer -Force | Out-Null
        }
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
                    if (Get-Command Request-ConnectLogSync -ErrorAction SilentlyContinue) {
                        Request-ConnectLogSync
                    } else {
                        Sync-ConnectLogToServer
                    }
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
            if (Get-Command Request-ConnectLogSync -ErrorAction SilentlyContinue) {
                Request-ConnectLogSync
            } else {
                Sync-ConnectLogToServer -Force
            }
        } elseif ($script:ConnectLogLinesSinceSync -ge 25) {
            if (Get-Command Request-ConnectLogSync -ErrorAction SilentlyContinue) {
                Request-ConnectLogSync
            } else {
                Sync-ConnectLogToServer
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
        # Inherit env into a single visible Connect window â€” do NOT cmd/c start (spawns extra consoles).
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
    if (-not (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue)) { return }

    if (Get-Command Test-TunnelUp -ErrorAction SilentlyContinue) {
        try {
            if (-not (Test-TunnelUp)) {
                Write-ConnectLog 'UPDATE_SILENT skip reason=tunnel_down' 'DEBUG'
                return
            }
        } catch {
            Write-ConnectLog "UPDATE_SILENT skip reason=tunnel_check_error error=$($_.Exception.Message)" 'DEBUG'
            return
        }
    }

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

    if (-not (Test-Path -LiteralPath $updateScript)) {
        Write-ConnectLog "UPDATE_SILENT age_min=$ageMin result=fail exit=1 pending_restart=0 reason=no_script path=$updateScript" 'ERROR'
        return
    }

    try {
        & $updateScript -ScriptDir $scriptDir -Quiet
        if ($null -ne $LASTEXITCODE) { $exitCode = [int]$LASTEXITCODE } else { $exitCode = 0 }

        switch ($exitCode) {
            0 { $result = 'ok'; $level = 'INFO' }
            1 { $result = 'fail'; $level = 'ERROR' }
            2 {
                $result = 'applied'
                $pendingRestart = 1
                $level = 'WARN'
                $script:ConnectUpdatePendingRestart = $true
            }
            default { $result = 'fail'; $level = 'ERROR' }
        }

        if ($exitCode -eq 2) {
            Write-ConnectLog "UPDATE_SILENT pending_restart=1 age_min=$ageMin result=$result exit=$exitCode note=relaunch_after_mutex_release" $level
        } else {
            Write-ConnectLog "UPDATE_SILENT age_min=$ageMin result=$result exit=$exitCode pending_restart=$pendingRestart" $level
        }

        if ($exitCode -eq 0 -or $exitCode -eq 2) {
            try {
                $null = New-Item -ItemType Directory -Force -Path $cfgDir
                [System.IO.File]::WriteAllText($stateFile, [string]$now, [System.Text.UTF8Encoding]::new($false))
            } catch {
                Write-ConnectLog "UPDATE_SILENT stamp_fail error=$($_.Exception.Message)" 'ERROR'
            }
        }

        if ($exitCode -eq 2) {
            if (Get-Command Exit-ConnectSingleInstance -ErrorAction SilentlyContinue) {
                Exit-ConnectSingleInstance
            }
            $null = Invoke-ConnectBatRelaunch -ScriptDir $scriptDir
            Wait-ConnectExit -Reason 'update_relaunch' -Code 0
        }
    } catch {
        Write-ConnectLog "UPDATE_SILENT age_min=$ageMin result=fail exit=1 pending_restart=0 error=$($_.Exception.Message)" 'ERROR'
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
        Request-ConnectLogSync
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

