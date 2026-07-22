from pathlib import Path

root = Path('.')

p = root / 'scripts/client/connect-ui.ps1'
c = p.read_text(encoding='utf-8')
old_ps = '''function Enter-ConnectSingleInstance {
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
}'''
new_ps = '''function Enter-ConnectSingleInstance {
    # One connect UI per machine (global mutex).
    param([string]$Name = '')
    if (-not $Name) { $Name = 'Global\\ClaudeConnect' }
    $script:ConnectInstanceMutex = $null
    try {
        $created = $false
        $m = New-Object System.Threading.Mutex($false, $Name, [ref]$created)
        $script:ConnectInstanceMutex = $m
        if (-not $m.WaitOne(0)) {
            try { $m.Close() } catch { }
            try { $m.Dispose() } catch { }
            $script:ConnectInstanceMutex = $null
            if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                Write-ConnectLog ("SINGLE_INSTANCE: blocked pid={0} mutex={1}" -f $PID, $Name) 'ERROR'
            }
            Write-Host ''
            Write-Host '  [X] Another Claude Connect is already running.' -ForegroundColor Red
            Write-Host ''
            return $false
        }
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("SINGLE_INSTANCE: acquired pid={0}" -f $PID) 'INFO'
        }
        return $true
    } catch {
        $script:ConnectInstanceMutex = $null
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("SINGLE_INSTANCE: mutex error (continue): {0}" -f $_.Exception.Message) 'WARN'
        }
        return $true
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
}'''
if old_ps not in c:
    raise SystemExit('connect-ui.ps1: old block not found')
c = c.replace(old_ps, new_ps, 1)
p.write_text(c, encoding='utf-8', newline='\r\n')
print('OK connect-ui.ps1')

p = root / 'scripts/client/connect-ui.sh'
c = p.read_text(encoding='utf-8')
old_sh = '''enter_connect_single_instance() {
    # Unlimited concurrent connect UIs. Tunnel slots + session IDs isolate tunnels/logs.
    CONNECT_LOCK_HELD=0
    connect_log "MULTI_INSTANCE: allowed pid=$$ (no flock)" 'INFO'
    return 0
}

exit_connect_single_instance() {
    # No-op: multi-instance mode does not hold a process-wide flock.
    CONNECT_LOCK_HELD=0
}'''
new_sh = '''enter_connect_single_instance() {
    # One connect UI per machine via flock on lock file.
    local lockdir="${HOME}/.config/claude-connect"
    local lockfile="${lockdir}/connect.lock"
    mkdir -p "$lockdir" 2>/dev/null || true
    exec 9>"$lockfile" || return 1
    if ! flock -n 9; then
        connect_log "SINGLE_INSTANCE: blocked pid=$$" 'ERROR'
        printf '\\n  [X] Another Claude Connect is already running.\\n\\n' >&2
        return 1
    fi
    CONNECT_LOCK_HELD=1
    connect_log "SINGLE_INSTANCE: acquired pid=$$" 'INFO'
    return 0
}

exit_connect_single_instance() {
    if [ "${CONNECT_LOCK_HELD:-0}" = 1 ]; then
        flock -u 9 2>/dev/null || true
        exec 9>&- 2>/dev/null || true
        CONNECT_LOCK_HELD=0
    fi
}'''
if old_sh not in c:
    raise SystemExit('connect-ui.sh: old block not found')
c = c.replace(old_sh, new_sh, 1)
p.write_text(c, encoding='utf-8', newline='\n')
print('OK connect-ui.sh')
