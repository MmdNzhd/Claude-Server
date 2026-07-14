# connect-diagnostic.ps1 - single-run diagnostic report (dot-sourced by connect.ps1)
# Callers: connect.ps1 after session open / mount fail / tunnel fail
# User request (verbatim): "More complete, more precise log - I need to know exactly what the problem is from a single run"
# Exports: Write-ConnectDiagnosticReport, Get-ConnectProblemVerdict, Get-ServerMountDiagnostic

function Get-CursorExeVersion {
    try {
        $exe = $null
        if (Get-Command Get-EditorNativeExe -ErrorAction SilentlyContinue) {
            $exe = Get-EditorNativeExe 'cursor'
        }
        if (-not $exe -or -not (Test-Path $exe)) { return 'unknown' }
        $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
        $parts = @($vi.ProductVersion, $vi.FileVersion) | Where-Object { $_ }
        if ($parts.Count -gt 0) { return ($parts | Select-Object -First 1) }
    } catch { }
    return 'unknown'
}

function Get-ServerMountDiagnostic {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$RemotePath
    )
    $bits = @("project_id=$ProjectId remote_path=$RemotePath")
    if (-not (Get-Command SshX -ErrorAction SilentlyContinue)) {
        $bits += 'ssh_unavailable=1'
        return ($bits -join ' | ')
    }
    $active = ((SshX "grep -E '^ACTIVE_MOUNT=' ~/.claude-connect.conf 2>/dev/null") -join '').Trim()
    $bits += "active_mount_conf=$active"
    $list = ((SshX '$HOME/.local/bin/claude-mount list 2>/dev/null') -join "`n").Trim()
    $bits += if ($list) { "mount_list=$($list -replace '\s+',' ')" } else { 'mount_list=empty' }
    $pathEsc = $RemotePath -replace "'", "'\\''"
    $bits += "mountpoint=$(((SshX "mountpoint -q '$pathEsc' 2>/dev/null && echo yes || echo no") -join '').Trim())"
    $bits += "path_exists=$(((SshX "test -d '$pathEsc' && echo yes || echo no") -join '').Trim())"
    $cnt = ((SshX "ls -A '$pathEsc' 2>/dev/null | wc -l") -join '').Trim()
    if ($cnt) { $bits += "path_entry_count=$cnt" }
    return ($bits -join ' | ')
}

function Get-ConnectProblemVerdict {
    param([Parameter(Mandatory)][hashtable]$Ctx)

    if (-not $Ctx.TunnelUp) {
        return @{
            Code = 'TUNNEL_DOWN'; Severity = 'ERROR'
            Summary = "Reverse SSH tunnel not up on port $($Ctx.Port)."
            Cause = 'Laptop OpenSSH stopped, firewall, or tunnel died.'
            Fix = 'Press R. Ensure sshd running and firewall allows inbound TCP 22.'
            NextAction = 'R'
        }
    }
    if ($Ctx.ServerReachable -eq $false) {
        return @{
            Code = 'SERVER_UNREACHABLE'; Severity = 'ERROR'
            Summary = "Server $($Ctx.ServerIP):22 unreachable."
            Cause = 'VPN/network or wrong SERVER_IP.'
            Fix = 'Check VPN and network, then press R.'
            NextAction = 'R'
        }
    }
    if (-not $Ctx.MountOk) {
        $mo = [string]$Ctx.MountOut
        if ($mo -match 'No such file|not found|cannot find') {
            return @{
                Code = 'MOUNT_PATH_MISSING'; Severity = 'ERROR'; Summary = 'Laptop project path missing.'
                Cause = $mo.Trim(); Fix = 'Press E to edit path, then R.'
                NextAction = 'E'
            }
        }
        if ($mo -match 'key auth failed|Permission denied|publickey') {
            return @{
                Code = 'MOUNT_SSH_AUTH'; Severity = 'ERROR'; Summary = 'Server cannot SSH to laptop.'
                Cause = $mo.Trim(); Fix = 'Run connect.bat as admin. Check authorized_keys.'
                NextAction = 'R'
            }
        }
        if ($mo -match 'tunnel') {
            return @{
                Code = 'MOUNT_TUNNEL_DOWN'; Severity = 'ERROR'; Summary = 'Mount failed - tunnel down on server.'
                Cause = $mo.Trim(); Fix = 'Press R to reconnect.'
                NextAction = 'R'
            }
        }
        return @{
            Code = 'MOUNT_FAILED'; Severity = 'ERROR'; Summary = 'SSHFS mount failed.'
            Cause = if ($mo) { $mo.Trim() } else { 'claude-mount up failed' }
            Fix = 'Read MOUNT section below. Press R.'
            NextAction = 'R'
        }
    }
    if ($Ctx.MountPoint -eq 'no') {
        return @{
            Code = 'SSHFS_NOT_MOUNTED'; Severity = 'ERROR'
            Summary = "$($Ctx.RemotePath) not mounted on server."
            Cause = 'mountpoint check failed after claude-mount up.'
            Fix = 'Press R. Admin: sudo claude-server deploy-mount-fix.'
            NextAction = 'R'
        }
    }
    if ($Ctx.EditorCmd -eq 'cursor' -and -not $Ctx.CursorExeFound) {
        return @{
            Code = 'CURSOR_NOT_FOUND'; Severity = 'ERROR'; Summary = 'Cursor not installed.'
            Cause = 'Cursor.exe missing from PATH.'
            Fix = 'Install Cursor or switch to VS Code in config.'
            NextAction = 'C'
        }
    }
    if ($Ctx.EditorCmd -eq 'cursor' -and $Ctx.AuthOk -eq $false -and -not $Ctx.OnFolder) {
        return @{
            Code = 'CURSOR_AUTH_INCOMPLETE'; Severity = 'WARN'; Summary = 'Cursor auth merge incomplete.'
            Cause = 'state.vscdb tokens missing or merge failed.'
            Fix = 'Close [Claude Server] windows. Admin: sudo claude-server sync-cursor-auth. Press R.'
            NextAction = 'R'
        }
    }
    if ($Ctx.OnFolder) {
        return @{
            Code = 'CURSOR_ON_FOLDER_OK'; Severity = 'INFO'
            Summary = "Cursor on project folder $($Ctx.RemotePath)."
            Cause = ''; Fix = ''; NextAction = ''
        }
    }
    $launchHist = [string]$Ctx.LaunchHistory
    if ($launchHist -and $launchHist -notmatch 'folder=True' -and $Ctx.DidLaunch) {
        if ($Ctx.AgentHome) {
            return @{
                Code = 'CURSOR_AGENT_HOME'; Severity = 'WARN'
                Summary = 'Cursor on Agent home - launch strategies did not open project folder.'
                Cause = 'Cursor 3.x ignores --folder-uri when already open (forum #153009). All strategies failed.'
                Fix = 'Press O. Or close all [Claude Server] Cursor windows, then R.'
                NextAction = 'O'
            }
        }
        return @{
            Code = 'CURSOR_LAUNCH_ALL_FAILED'; Severity = 'WARN'
            Summary = 'All launch strategies ran but folder workspace not detected.'
            Cause = $launchHist
            Fix = 'Read LAUNCH_HISTORY below. Press O to retry. Close extra Cursor windows first.'
            NextAction = 'O'
        }
    }
    if ($Ctx.AgentHome -and $Ctx.WindowOpen) {
        return @{
            Code = 'CURSOR_AGENT_HOME'; Severity = 'WARN'
            Summary = 'Cursor on Agent home - not project folder.'
            Cause = 'Cursor 3.x Agents window; --folder-uri ignored when already open (forum #153009).'
            Fix = 'Press O. Or close [Claude Server] windows and reconnect.'
            NextAction = 'O'
        }
    }
    if ($Ctx.WindowOpen -and -not $Ctx.OnFolder) {
        return @{
            Code = 'CURSOR_WRONG_WORKSPACE'; Severity = 'WARN'
            Summary = 'Cursor open on wrong workspace.'
            Cause = 'cmdline/title mismatch with expected remote path.'
            Fix = 'Press O. Read PROCESSES section in this report.'
            NextAction = 'O'
        }
    }
    if (-not $Ctx.WindowOpen -and $Ctx.DidLaunch) {
        return @{
            Code = 'CURSOR_LAUNCH_NO_WINDOW'; Severity = 'WARN'
            Summary = 'Launch ran but no Cursor window detected.'
            Cause = 'Process exited immediately or wrong profile.'
            Fix = 'Check LAUNCH_HISTORY and PROC_START lines in connect.log.'
            NextAction = 'O'
        }
    }
    if (-not $Ctx.WindowOpen) {
        return @{
            Code = 'CURSOR_NOT_OPEN'; Severity = 'WARN'
            Summary = 'Cursor server profile not open.'
            Cause = 'Launch failed or was skipped.'
            Fix = 'Press O.'
            NextAction = 'O'
        }
    }
    return @{ Code = 'OK'; Severity = 'INFO'; Summary = 'OK'; Cause = ''; Fix = ''; NextAction = '' }
}

function Write-ConnectDiagnosticReport {
    param(
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$EditorName,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$RemotePath,
        [bool]$TunnelUp = $false,
        [bool]$MountOk = $true,
        [string]$MountOut = '',
        [bool]$OnFolder = $false,
        [bool]$AgentHome = $false,
        [bool]$WindowOpen = $false,
        [bool]$DidLaunch = $false,
        [bool]$AuthOk = $true,
        [string]$ServerIP = '',
        [int]$Port = 0,
        [string]$LaunchHistory = '',
        [string]$AuthDetail = '',
        [string[]]$Timeline = @(),
        [string[]]$SshRecent = @()
    )
    if (-not (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue)) { return $null }

    $cursorFound = $false
    if ($EditorCmd -eq 'cursor' -and (Get-Command Get-EditorNativeExe -ErrorAction SilentlyContinue)) {
        $cursorFound = [bool](Get-EditorNativeExe 'cursor')
    }
    $serverReachable = $null
    if ($ServerIP -and (Get-Command PortOpen -ErrorAction SilentlyContinue)) {
        $serverReachable = PortOpen $ServerIP 22
    }
    $localPortOpen = $null
    if ($Port -gt 0 -and (Get-Command PortOpen -ErrorAction SilentlyContinue)) {
        $localPortOpen = PortOpen '127.0.0.1' $Port
    }
    $mountPoint = ''; $pathExists = ''
    $serverMount = Get-ServerMountDiagnostic -ProjectId $ProjectId -RemotePath $RemotePath
    if ($serverMount -match 'mountpoint=(\w+)') { $mountPoint = $Matches[1] }
    if ($serverMount -match 'path_exists=(\w+)') { $pathExists = $Matches[1] }

    $expectedUri = ''
    if (Get-Command Get-RemoteFolderUri -ErrorAction SilentlyContinue) {
        $expectedUri = Get-RemoteFolderUri -Alias $Alias -RemotePath $RemotePath
    }

    $verdict = Get-ConnectProblemVerdict -Ctx @{
        EditorCmd = $EditorCmd; Port = $Port; ServerIP = $ServerIP
        TunnelUp = $TunnelUp; MountOk = $MountOk; MountOut = $MountOut
        OnFolder = $OnFolder; AgentHome = $AgentHome; WindowOpen = $WindowOpen
        DidLaunch = $DidLaunch; AuthOk = $AuthOk; CursorExeFound = $cursorFound
        ServerReachable = $serverReachable; RemotePath = $RemotePath
        MountPoint = $mountPoint; PathExists = $pathExists
        LaunchHistory = $LaunchHistory
    }

    $sessionStatus = if ($verdict.Severity -eq 'INFO') { 'OK' } else { 'BROKEN' }
    $elev = if ((Get-Command Test-IsElevatedShell -ErrorAction SilentlyContinue) -and (Test-IsElevatedShell)) { 'yes' } else { 'no' }
    $logPath = if ($script:ConnectLogPath) { $script:ConnectLogPath } else { 'connect.log' }

    $lines = @(
        "======== DIAGNOSTIC REPORT [$Phase] ========"
        "SESSION_STATUS=$sessionStatus"
        "VERDICT_CODE=$($verdict.Code)"
        "VERDICT_SEVERITY=$($verdict.Severity)"
        "VERDICT_SUMMARY=$($verdict.Summary)"
    )
    if ($verdict.NextAction) { $lines += "NEXT_ACTION=Press $($verdict.NextAction) in connect window" }
    if ($verdict.Cause) { $lines += "LIKELY_CAUSE=$($verdict.Cause)" }
    if ($verdict.Fix) { $lines += "FIX=$($verdict.Fix)" }
    $lines += "LOG_FILE=$logPath"
    $lines += '---'
    $lines += "ENV version=$($script:ConnectVersion) user=$env:USERNAME elevated=$elev pid=$PID"
    $lines += "ENV server=$ServerIP alias=$Alias port=$Port git=$(if (Get-Command Get-GitMode -ErrorAction SilentlyContinue) { Get-GitMode } else { '?' })"
    if ($EditorCmd -eq 'cursor') {
        $lines += "ENV cursor_version=$(Get-CursorExeVersion) profile=$(Get-CursorRemoteProfileDir)"
    }
    $lines += "PROJECT id=$ProjectId path=$RemotePath"
    if ($expectedUri) { $lines += "EXPECTED_URI=$expectedUri" }
    $lines += "TUNNEL up=$TunnelUp local_port_open=$localPortOpen server_reachable=$serverReachable banner=$(if (Get-Command Get-TunnelBanner -ErrorAction SilentlyContinue) { Get-TunnelBanner } else { '?' })"
    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) {
        $lines += "TUNNEL pid=$($script:SessionBgTunnel.Id)"
    }
    $lines += "MOUNT ok=$MountOk $serverMount"
    if ($MountOut) {
        $mo = ($MountOut.Trim() -replace '\s+', ' ')
        if ($mo.Length -gt 500) { $mo = $mo.Substring(0, 500) + '...' }
        $lines += "MOUNT output=$mo"
    }
    $lines += "AUTH ok=$AuthOk detail=$AuthDetail"
    if ($EditorCmd -eq 'cursor' -and (Get-Command Get-CursorProfileStorageDiag -ErrorAction SilentlyContinue)) {
        $lines += "AUTH storage=$(Get-CursorProfileStorageDiag)"
    }
    $lines += "EDITOR on_folder=$OnFolder agent=$AgentHome window=$WindowOpen launch=$DidLaunch"
    $lightDiag = ($Phase -eq 'SESSION_OPEN' -and $OnFolder -and $MountOk -and ($AuthOk -ne $false))
    if ($lightDiag) {
        $lines += "EDITOR summary=on_folder=$OnFolder launch=$DidLaunch (light SESSION_OPEN)"
        if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
            Write-ConnectPerfLog -Mark 'diag_process_snapshot' -Ms 0 -Extra 'skipped=light_session_open'
        }
    } else {
        if (Get-Command Get-RemoteEditorStateExplain -ErrorAction SilentlyContinue) {
            $swState = [System.Diagnostics.Stopwatch]::StartNew()
            $lines += "EDITOR state=$(Get-RemoteEditorStateExplain -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)"
            $swState.Stop()
            if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
                Write-ConnectPerfLog -Mark 'diag_state_explain' -Ms $swState.ElapsedMilliseconds
            }
        }
        if (Get-Command Get-RemoteEditorProcessSnapshot -ErrorAction SilentlyContinue) {
            $swSnap = [System.Diagnostics.Stopwatch]::StartNew()
            $lines += "PROCESSES $(Get-RemoteEditorProcessSnapshot -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath)"
            $swSnap.Stop()
            if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
                Write-ConnectPerfLog -Mark 'diag_process_snapshot' -Ms $swSnap.ElapsedMilliseconds
            }
        }
    }
    if ($LaunchHistory) { $lines += "LAUNCH_HISTORY=$LaunchHistory" }
    if ($Timeline -and $Timeline.Count -gt 0) {
        $lines += 'TIMELINE begin'
        foreach ($t in $Timeline) { $lines += "  $t" }
        $lines += 'TIMELINE end'
    }
    if ($SshRecent -and $SshRecent.Count -gt 0) {
        $lines += 'SSH_RECENT begin'
        foreach ($s in $SshRecent) { $lines += "  $s" }
        $lines += 'SSH_RECENT end'
    }
    $lines += '======== END DIAGNOSTIC REPORT ========'

    foreach ($line in $lines) {
        $lvl = if ($line -match '^(SESSION_STATUS|VERDICT_)' -and $verdict.Severity -eq 'ERROR') { 'ERROR' }
               elseif ($line -match '^(SESSION_STATUS|VERDICT_|NEXT_ACTION)' -and $verdict.Severity -eq 'WARN') { 'WARN' }
               elseif ($line -match '^====') { 'INFO' }
               elseif ($line -match '^(LIKELY_CAUSE|FIX|LOG_FILE)=') { 'INFO' }
               else { 'DEBUG' }
        Write-ConnectLog $line $lvl
    }

    if ($verdict.Severity -ne 'INFO') {
        Write-Host ''
        Write-Host '    ============================================' -ForegroundColor Yellow
        Write-Host "    DIAGNOSTIC: $($verdict.Code)" -ForegroundColor Yellow
        Write-Host "    $($verdict.Summary)" -ForegroundColor White
        if ($verdict.Fix) { Write-Host "    -> $($verdict.Fix)" -ForegroundColor DarkGray }
        if ($verdict.NextAction) {
            Write-Host "    -> Hotkey: $($verdict.NextAction)" -ForegroundColor Cyan
        }
        Write-Host "    -> Log: $(Split-Path -Leaf $logPath) (search DIAGNOSTIC REPORT)" -ForegroundColor DarkGray
        Write-Host '    ============================================' -ForegroundColor Yellow
        Write-Host ''
    } elseif ($Phase -eq 'SESSION_OPEN') {
        Write-Host ''
        Write-Host '    [OK] Session ready - Cursor on project folder' -ForegroundColor Green
        Write-Host "    Log: $(Split-Path -Leaf $logPath)" -ForegroundColor DarkGray
        Write-Host ''
    }
    return $verdict
}
