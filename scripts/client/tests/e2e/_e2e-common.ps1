#Requires -Version 5.1
# Shared helpers for E2E chat-pyramid harness (TEST ONLY - never edit product connect.ps1).
$ErrorActionPreference = 'Continue'

function Get-E2eConnectBootPath {
    $icPath = Join-Path $env:USERPROFILE '.config\claude-connect\install-current.txt'
    $ver = ''
    if (Test-Path -LiteralPath $icPath) {
        $ver = (Get-Content -LiteralPath $icPath -Raw -ErrorAction SilentlyContinue).Trim()
    }
    if ($ver -match '^\d{8}\.\d+$') {
        $versioned = Join-Path $env:USERPROFILE ("Desktop\Claude-Connect\{0}\src\connect-boot.ps1" -f $ver)
        if (Test-Path -LiteralPath $versioned) { return $versioned }
        # install-current points at a version dir but boot is missing - never fall back to stale flat layout
        return $null
    }
    $candidates = @(
        (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\connect-boot.ps1')
        (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\src\connect-boot.ps1')
    )
    if ($script:ClientRoot) {
        $candidates += (Join-Path $script:ClientRoot 'windows\connect-boot.ps1')
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Get-E2eInstallCurrentVersion {
    $icPath = Join-Path $env:USERPROFILE '.config\claude-connect\install-current.txt'
    if (-not (Test-Path -LiteralPath $icPath)) { return '' }
    return ((Get-Content -LiteralPath $icPath -Raw -ErrorAction SilentlyContinue).Trim())
}

# Parse Connect hygiene markers from filtered session log lines (20260804.3+ E2E proof).
function Update-E2eSessionHygieneFields {
    param(
        [System.Collections.IDictionary]$Rep,
        [string[]]$Lines
    )
    foreach ($line in $Lines) {
        if ($line -match 'session start' -and $line -match 'CONNECT_VERSION=(\S+)') {
            $Rep.ConnectVersion = $Matches[1]
        } elseif (-not $Rep.ConnectVersion -and $line -match 'CONNECT_VERSION=(\S+)') {
            $Rep.ConnectVersion = $Matches[1]
        }
        if ($line -match 'FAIL UNHANDLED|UPDATE_UNHANDLED') { $Rep.UnhandledFail = $true }
        if ($line -match 'LOG_SYNC_FAIL' -and $line -match 'detail=exception\b') { $Rep.LogSyncException = $true }
        # Precise cares about opaque detail=exception NRE (not classified chunk_read_fail soft).
        if ($line -match 'LOG_SYNC_FAIL' -and $line -match 'detail=exception\b' -and $line -match 'NullReferenceException') {
            $Rep.LogSyncNre = $true
        }
        if ($line -match 'SCORECARD boot ' -and $line -match 'agent_path=ok') { $Rep.ScorecardAgentOk = $true }
        if ($line -match 'AGENT_PATH ok' -and $line -match 'listen_conf=1') { $Rep.AgentListenConf = $true }
        if ($line -match 'WINDOWS_MCP: server_sync_unexpected') { $Rep.WmcpSyncUnexpected = $true }
        # Only explicit day-log stamps (`WMCP_PROBE=200`), not WINDOWS_MCP:/SSH_END chatter.
        if ($line -match '\]\s+WMCP_PROBE=(\d+)' -and $line -notmatch 'WINDOWS_MCP:' -and $line -notmatch 'SSH_END\b') {
            $code = $Matches[1]
            # Sticky 200: do not let a later miss overwrite a real success stamp.
            if ($Rep.WmcpProbe -eq '200' -and $code -ne '200') { }
            else {
                $Rep.WmcpProbe = $code
                $Rep.WmcpSixZeros = [bool]($code -eq '000000' -or $code -match '^0{6,}$')
            }
        }
        if ($line -match 'LAUNCH_GATE acquired') { $Rep.LaunchGate = 'acquired' }
        elseif ($line -match 'LAUNCH_GATE timeout') { $Rep.LaunchGate = 'timeout' }
        if ($line -match 'LAUNCH_GATE_PEER' -or $line -match 'reason=launch_gate_peer\b' -or $line -match '\blaunch_gate_peer\b') {
            $Rep.LaunchGatePeer = $true
        }
        if ($line -match 'LAUNCH_PLAN:' -and $line -match 'reason=cold_start\b') {
            if ($line -match 'use_new_window=(False|0)\b') { $Rep.ColdStartNoNwCount++ }
        }
        if ($line -match 'noninteractive_stdin') { $Rep.NonInteractiveStdin = $true }
        if ($line -match 'MOUNT_BG_OK\b') { $Rep.MountBgOk = $true }
        if ($line -match 'MOUNT_BG_FAIL\b') { $Rep.MountBgFail = $true }
        if ($line -match 'MOUNT_BG_RETRY\b') { $Rep.MountBgRetry = $true }
        if ($line -match 'MOUNT_BG_SKIP\b' -or $line -match 'already mounted') { $Rep.MountBgSkip = $true }
        if ($line -match 'MOUNT_VERIFY pending_no_sshfs') { $Rep.MountVerifyPending = $true }
        if ($line -match 'MOUNT_VERIFY ls_ok=1' -and $line -match 'bound_p=\d+') { $Rep.MountVerifyBound = $true }
    }
}

function Get-E2eDayLogPath {
    $logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
    return (Join-Path $logDir ("connect-{0}.log" -f (Get-Date -Format 'yyyyMMdd')))
}

function Get-E2eResultsDir {
    $d = Join-Path $env:USERPROFILE '.config\claude-connect\e2e-harness'
    New-Item -ItemType Directory -Force -Path $d -ErrorAction SilentlyContinue | Out-Null
    return $d
}

function Get-E2eFreeConnectSlotCount {
    $free = 0
    for ($i = 0; $i -lt 10; $i++) {
        $pm = $null
        try {
            $pm = New-Object System.Threading.Mutex($false, "Global\ClaudeConnect#$i")
            $got = $false
            try { $got = $pm.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
            if ($got) { $free++; try { $pm.ReleaseMutex() } catch {} }
        } catch {} finally {
            if ($pm) { try { $pm.Dispose() } catch {} }
        }
    }
    return $free
}

function Get-E2eAgentCommand {
    $cmd = Get-Command agent -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command cursor-agent -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $ps1 = Join-Path $env:LOCALAPPDATA 'cursor-agent\agent.ps1'
    if (Test-Path -LiteralPath $ps1) { return $ps1 }
    return $null
}

function Stop-E2eProcessTree {
    param([int]$RootPid)
    if ($RootPid -le 0) { return }
    $kids = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$RootPid" -ErrorAction SilentlyContinue)
    foreach ($k in $kids) { Stop-E2eProcessTree -RootPid ([int]$k.ProcessId) }
    try { Stop-Process -Id $RootPid -Force -ErrorAction SilentlyContinue } catch {}
}

function Get-E2eProtectedCursorRootPids {
    $cp = @(Get-CimInstance Win32_Process -Filter "Name='Cursor.exe'" -ErrorAction SilentlyContinue)
    $all = @($cp | ForEach-Object { $_.ProcessId })
    return @($cp | Where-Object { $all -notcontains $_.ParentProcessId } | ForEach-Object { $_.ProcessId })
}

function Get-E2eMainTunnelPids {
    return @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match '-N ' -and $_.CommandLine -match '-R ' } |
        ForEach-Object { $_.ProcessId })
}

# Resolve Connect session id from day log. STRICT: requires pid=RootPid on a session-start line.
# Optional ExpectedSession forces that id (harness sets unique CLAUDE_CONNECT_RUN_ID per worker).
function Resolve-E2eSessionId {
    param(
        [string]$DayLog,
        [int]$RootPid,
        [datetime]$NotBefore,
        [string]$ExpectedSession = ''
    )
    if (-not (Test-Path -LiteralPath $DayLog)) { return $null }
    $pidPat = 'pid=' + $RootPid + '\b'
    $tail = @()
    try { $tail = Get-Content -LiteralPath $DayLog -Tail 1200 -ErrorAction SilentlyContinue } catch { return $null }
    $found = $null
    foreach ($line in $tail) {
        if ($line -notmatch 'session start') { continue }
        if ($line -notmatch $pidPat) { continue }
        if ($line -match 'session=(\S+)') {
            $sid = $Matches[1]
            if ($ExpectedSession -and ($sid -ne $ExpectedSession)) { continue }
            # Prefer newest match in tail
            $found = $sid
        }
    }
    if ($found) { return $found }
    if ($ExpectedSession) {
        # Confirm expected session appeared with our pid after NotBefore via Select-String
        try {
            $hits = @(Select-String -LiteralPath $DayLog -Pattern ("pid=" + $RootPid + '\s+session=' + [regex]::Escape($ExpectedSession)) -ErrorAction SilentlyContinue)
            if ($hits.Count -gt 0) { return $ExpectedSession }
        } catch {}
    }
    try {
        $hits = @(Select-String -LiteralPath $DayLog -Pattern ("pid=" + $RootPid + '\s+session=(\S+)') -ErrorAction SilentlyContinue)
        if ($hits.Count -gt 0) {
            $m = $hits[-1].Line
            if ($m -match 'session=(\S+)') { return $Matches[1] }
        }
    } catch {}
    return $null
}

# Deep report filtered to lines at/after NotBefore (avoids polluting with same sticky session id history).
function Get-E2eSessionDeepReportWindowed {
    param(
        [string]$DayLog,
        [string]$SessionId,
        [int]$RootPid = 0,
        [datetime]$NotBefore = [datetime]::MinValue
    )
    $rep = Get-E2eSessionDeepReport -DayLog $DayLog -SessionId $SessionId -RootPid $RootPid
    if (-not $SessionId -or $NotBefore -eq [datetime]::MinValue) { return $rep }
    if (-not (Test-Path -LiteralPath $DayLog)) { return $rep }

    $tag = '[' + $SessionId + ']'
    $lines = @()
    try {
        $lines = @(Select-String -LiteralPath $DayLog -Pattern $tag -SimpleMatch -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Line })
    } catch { $lines = @() }

    $window = @()
    foreach ($line in $lines) {
        if ($line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') {
            try {
                $ts = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', $null)
                if ($ts -ge $NotBefore.AddSeconds(-2)) { $window += $line }
            } catch { $window += $line }
        }
    }
    # Re-parse from window only by writing a temp slice is heavy; instead recompute flags on $window
    $rep2 = [ordered]@{
        SessionId          = $SessionId
        RootPid            = $RootPid
        LineCount          = $window.Count
        SessionStartCount  = 0
        Scorecard          = $false
        ScorecardLine      = ''
        AgentPathOk        = $false
        AgentPathBad       = $false
        AgentPathLine      = ''
        VerdictCode        = ''
        VerdictSummary     = ''
        OnFolderTrue       = $false
        OnFolderFalse      = $false
        MountVerifyOk      = $false
        KeepMarker         = $false
        SessionEndReason   = ''
        KeyAvailableCrash  = $false
        ExitWaitReason     = ''
        ErrorCount         = 0
        WarnCount          = 0
        StepOk             = @()
        StepFail           = @()
        Errors             = @()
        Warns              = @()
        Rank1Pass          = $false
        NotBefore          = $NotBefore.ToString('o')
        LaunchOk           = $false
        LaunchSkipReuse    = $false
        LaunchAttempt      = $false
        LaunchForceNw      = $false
        ScorecardProject   = ''
        DidRealLaunch      = $false
        ConnectVersion     = ''
        UnhandledFail      = $false
        LogSyncException   = $false
        WmcpProbe          = ''
        WmcpSixZeros       = $false
        LaunchGate         = ''
        LaunchGatePeer     = $false
        ColdStartNoNwCount = 0
        NonInteractiveStdin = $false
        MountBgOk          = $false
        MountBgFail        = $false
        MountBgRetry       = $false
        MountBgSkip        = $false
        MountVerifyPending = $false
        MountVerifyBound  = $false
        LogSyncNre         = $false
        ScorecardAgentOk   = $false
        AgentListenConf    = $false
        WmcpSyncUnexpected = $false
    }
    foreach ($line in $window) {
        if ($line -match 'session start') { $rep2.SessionStartCount++ }
        if ($line -match 'SCORECARD boot ') {
            $rep2.Scorecard = $true
            $rep2.ScorecardLine = $line
            if ($line -match '\bam=([^\s]+)') { $rep2.ScorecardProject = $Matches[1] }
        }
        if ($line -match 'AGENT_PATH ok') { $rep2.AgentPathOk = $true; $rep2.AgentPathLine = $line }
        if ($line -match 'AGENT_PATH bad') { $rep2.AgentPathBad = $true; if (-not $rep2.AgentPathLine) { $rep2.AgentPathLine = $line } }
        if ($line -match 'VERDICT_CODE=(\S+)') { $rep2.VerdictCode = $Matches[1] }
        if ($line -match 'VERDICT_SUMMARY=(.+)$') { $rep2.VerdictSummary = $Matches[1].Trim() }
        if ($line -match 'on_folder=True') { $rep2.OnFolderTrue = $true }
        if ($line -match 'on_folder=False') { $rep2.OnFolderFalse = $true }
        if ($line -match 'MOUNT_VERIFY ls_ok=1') { $rep2.MountVerifyOk = $true }
        if ($line -match 'KEEP_MARKER_WRITE') { $rep2.KeepMarker = $true }
        if ($line -match 'SESSION_END reason=(\S+)') { $rep2.SessionEndReason = $Matches[1] }
        if ($line -match 'KeyAvailable|Console\.In\.Peek') { $rep2.KeyAvailableCrash = $true }
        if ($line -match 'EXIT_WAIT: reason=(\S+)') { $rep2.ExitWaitReason = $Matches[1] }
        if ($line -match 'LAUNCH_OK:') { $rep2.LaunchOk = $true; $rep2.DidRealLaunch = $true }
        if ($line -match 'LAUNCH_ATTEMPT:') { $rep2.LaunchAttempt = $true; $rep2.DidRealLaunch = $true }
        if ($line -match 'LAUNCH_SKIP: already on correct folder|EDITOR_DECISION: skip_launch reason=already_on_folder|EDITOR_LAUNCH_SKIP reason=known_on_folder') {
            $rep2.LaunchSkipReuse = $true
        }
        if ($line -match 'force_new_window|ForceNewWindow') { $rep2.LaunchForceNw = $true }
        if ($line -match '\[ERROR\]') {
            $rep2.ErrorCount++
            if ($rep2.Errors.Count -lt 12) { $rep2.Errors += $line }
        }
        if ($line -match '\[WARN\]') {
            $rep2.WarnCount++
            if ($rep2.Warns.Count -lt 12) { $rep2.Warns += $line }
        }
        if ($line -match 'STEP end: (.+?) (ok|failed) ms=(\d+)') {
            $st = [pscustomobject]@{ Name = $Matches[1]; Status = $Matches[2]; Ms = [int]$Matches[3] }
            if ($Matches[2] -eq 'ok') { $rep2.StepOk += $st } else { $rep2.StepFail += $st }
        }
    }
    Update-E2eSessionHygieneFields -Rep $rep2 -Lines $window
    $scorecardOpen = [bool]($rep2.ScorecardLine -match 'editor=open\b')
    $rep2.Rank1Pass = [bool](
        ($rep2.Scorecard -and $scorecardOpen) -or
        ($rep2.VerdictCode -eq 'CURSOR_ON_FOLDER_OK' -and $rep2.OnFolderTrue) -or
        ($rep2.OnFolderTrue -and $rep2.MountVerifyOk -and $rep2.KeepMarker)
    )
    return [pscustomobject]$rep2
}

# Full-session deep parse (post-hoc). Prefer this over live Tail 250.
function Get-E2eSessionDeepReport {
    param(
        [string]$DayLog,
        [string]$SessionId,
        [int]$RootPid = 0
    )
    $rep = [ordered]@{
        SessionId          = $SessionId
        RootPid            = $RootPid
        LineCount          = 0
        SessionStartCount  = 0
        Scorecard          = $false
        ScorecardLine      = ''
        AgentPathOk        = $false
        AgentPathBad       = $false
        AgentPathLine      = ''
        VerdictCode        = ''
        VerdictSummary     = ''
        OnFolderTrue       = $false
        OnFolderFalse      = $false
        MountVerifyOk      = $false
        KeepMarker         = $false
        SessionEndReason   = ''
        KeyAvailableCrash  = $false
        ExitWaitReason     = ''
        ErrorCount         = 0
        WarnCount          = 0
        StepOk             = @()
        StepFail           = @()
        Errors             = @()
        Warns              = @()
        Rank1Pass          = $false
        ConnectVersion     = ''
        UnhandledFail      = $false
        LogSyncException   = $false
        WmcpProbe          = ''
        WmcpSixZeros       = $false
        LaunchGate         = ''
        LaunchGatePeer     = $false
        ColdStartNoNwCount = 0
        NonInteractiveStdin = $false
        MountBgOk          = $false
        MountBgFail        = $false
        MountBgRetry       = $false
        MountBgSkip        = $false
        MountVerifyPending = $false
        MountVerifyBound  = $false
        LogSyncNre         = $false
        ScorecardAgentOk   = $false
        AgentListenConf    = $false
        WmcpSyncUnexpected = $false
    }
    if (-not $SessionId -or -not (Test-Path -LiteralPath $DayLog)) { return [pscustomobject]$rep }

    $tag = '[' + $SessionId + ']'
    $lines = @()
    try {
        # Stream filter - day log can be multi-MB; avoid loading entire file when possible
        $lines = @(Select-String -LiteralPath $DayLog -Pattern $tag -SimpleMatch -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Line })
    } catch { $lines = @() }
    $rep.LineCount = $lines.Count

    foreach ($line in $lines) {
        if ($line -match 'session start') { $rep.SessionStartCount++ }
        if ($line -match 'SCORECARD boot ') {
            $rep.Scorecard = $true
            $rep.ScorecardLine = $line
        }
        if ($line -match 'AGENT_PATH ok') {
            $rep.AgentPathOk = $true
            $rep.AgentPathLine = $line
        }
        if ($line -match 'AGENT_PATH bad') {
            $rep.AgentPathBad = $true
            if (-not $rep.AgentPathLine) { $rep.AgentPathLine = $line }
        }
        if ($line -match 'VERDICT_CODE=(\S+)') { $rep.VerdictCode = $Matches[1] }
        if ($line -match 'VERDICT_SUMMARY=(.+)$') { $rep.VerdictSummary = $Matches[1].Trim() }
        if ($line -match 'on_folder=True') { $rep.OnFolderTrue = $true }
        if ($line -match 'on_folder=False') { $rep.OnFolderFalse = $true }
        if ($line -match 'MOUNT_VERIFY ls_ok=1') { $rep.MountVerifyOk = $true }
        if ($line -match 'KEEP_MARKER_WRITE') { $rep.KeepMarker = $true }
        if ($line -match 'SESSION_END reason=(\S+)') { $rep.SessionEndReason = $Matches[1] }
        if ($line -match 'KeyAvailable|Console\.In\.Peek') { $rep.KeyAvailableCrash = $true }
        if ($line -match 'EXIT_WAIT: reason=(\S+)') { $rep.ExitWaitReason = $Matches[1] }
        if ($line -match '\[ERROR\]') {
            $rep.ErrorCount++
            if ($rep.Errors.Count -lt 12) { $rep.Errors += $line }
        }
        if ($line -match '\[WARN\]') {
            $rep.WarnCount++
            if ($rep.Warns.Count -lt 12) { $rep.Warns += $line }
        }
        if ($line -match 'STEP end: (.+?) (ok|failed) ms=(\d+)') {
            $st = [pscustomobject]@{ Name = $Matches[1]; Status = $Matches[2]; Ms = [int]$Matches[3] }
            if ($Matches[2] -eq 'ok') { $rep.StepOk += $st } else { $rep.StepFail += $st }
        }
    }

    Update-E2eSessionHygieneFields -Rep $rep -Lines $lines

    # Rank-1: SCORECARD with editor=open (not mere SCORECARD presence — editor=closed was a false green).
    $scorecardOpen = [bool]($rep.ScorecardLine -match 'editor=open\b')
    $rep.Rank1Pass = [bool](
        ($rep.Scorecard -and $scorecardOpen) -or
        ($rep.VerdictCode -eq 'CURSOR_ON_FOLDER_OK' -and $rep.OnFolderTrue) -or
        ($rep.OnFolderTrue -and $rep.MountVerifyOk -and $rep.KeepMarker)
    )
    return [pscustomobject]$rep
}

function Write-E2eDeepReportHost {
    param($Report)
    if (-not $Report) { Write-Host '  ----  (no report)'; return }
    Write-Host ("  ----  session={0} lines={1} starts={2}" -f $Report.SessionId, $Report.LineCount, $Report.SessionStartCount)
    Write-Host ("  ----  SCORECARD={0} AGENT_PATH_ok={1} bad={2} VERDICT={3}" -f `
        $Report.Scorecard, $Report.AgentPathOk, $Report.AgentPathBad, $Report.VerdictCode)
    Write-Host ("  ----  project={0} launch_ok={1} launch_attempt={2} skip_reuse={3}" -f `
        $Report.ScorecardProject, $Report.LaunchOk, $Report.LaunchAttempt, $Report.LaunchSkipReuse)
    Write-Host ("  ----  on_folder_true={0} mount_verify={1} keep={2} end={3}" -f `
        $Report.OnFolderTrue, $Report.MountVerifyOk, $Report.KeepMarker, $Report.SessionEndReason)
    Write-Host ("  ----  connect_ver={0} unhandled={1} logsync_exc={2} wmcp={3} wmcp6z={4}" -f `
        $Report.ConnectVersion, $Report.UnhandledFail, $Report.LogSyncException, $Report.WmcpProbe, $Report.WmcpSixZeros)
    Write-Host ("  ----  launch_gate={0} gate_peer={1} cold_no_nw={2} noninteractive_stdin={3}" -f `
        $Report.LaunchGate, $Report.LaunchGatePeer, $Report.ColdStartNoNwCount, $Report.NonInteractiveStdin)
    Write-Host ("  ----  mount_bg_ok={0} fail={1} retry={2} verify_bound={3} pending={4}" -f `
        $Report.MountBgOk, $Report.MountBgFail, $Report.MountBgRetry, $Report.MountVerifyBound, $Report.MountVerifyPending)
    Write-Host ("  ----  keyavail_crash={0} exit_wait={1} err={2} warn={3}" -f `
        $Report.KeyAvailableCrash, $Report.ExitWaitReason, $Report.ErrorCount, $Report.WarnCount)
    if ($Report.ScorecardLine) {
        Write-Host ("  ----  SCORECARD_LINE: {0}" -f ($Report.ScorecardLine -replace '^.*?\]\s*', ''))
    }
    if ($Report.StepOk.Count -gt 0) {
        $sum = ($Report.StepOk | ForEach-Object { '{0}={1}ms' -f $_.Name, $_.Ms }) -join '; '
        Write-Host ("  ----  STEPS_OK: {0}" -f $sum)
    }
    if ($Report.StepFail.Count -gt 0) {
        Write-Host ("  ----  STEPS_FAIL: {0}" -f (($Report.StepFail | ForEach-Object { $_.Name }) -join ', ')) -ForegroundColor Yellow
    }
    foreach ($e in @($Report.Errors | Select-Object -Last 5)) {
        Write-Host ("  ERR   {0}" -f ($e -replace '^.*?\]\s*', '')) -ForegroundColor DarkRed
    }
    foreach ($w in @($Report.Warns | Select-Object -Last 3)) {
        Write-Host ("  WARN  {0}" -f ($w -replace '^.*?\]\s*', '')) -ForegroundColor DarkYellow
    }
}
