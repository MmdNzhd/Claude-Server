# -*- coding: utf-8 -*-
from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')
ui_path = root / 'scripts/client/connect-ui.ps1'
cp_path = root / 'scripts/client/windows/connect.ps1'
sh_path = root / 'scripts/client/connect-ui.sh'
ui = ui_path.read_text(encoding='utf-8')
cp = cp_path.read_text(encoding='utf-8')
sh = sh_path.read_text(encoding='utf-8')

# --- 1) Ensure-ConnectLogWriter + Write-ConnectLog reopen ---
old_wl = '''function Write-ConnectLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    if (-not $script:ConnectLogWriter) { return }
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = if ($script:ConnectSessionId) { $script:ConnectSessionId } else { '-' }
        $script:ConnectLogWriter.WriteLine("[$ts] [$Level] [$sid] $Message")
        # Local always complete. Sync carefully:
        # - TRACE/DEBUG stay local-only during hot loops (were causing False spam + multi-minute stalls)
        # - WARN/ERROR flush now; INFO every 25 lines
        if ($Level -eq 'TRACE' -or $Level -eq 'DEBUG') { return }
        $script:ConnectLogLinesSinceSync = [int]$script:ConnectLogLinesSinceSync + 1
        if ($Level -eq 'WARN' -or $Level -eq 'ERROR' -or $script:ConnectLogLinesSinceSync -ge 25) {
            Sync-ConnectLogToServer
        }
    } catch { }
}'''

new_ensure_and_wl = r'''function Ensure-ConnectLogWriter {
    if ($script:ConnectLogWriter) { return $true }
    if (-not $script:ConnectLogPath) { $script:ConnectLogPath = Get-ConnectLogDayPath }
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
        $sid = if ($script:ConnectSessionId) { $script:ConnectSessionId } else { '-' }
        $script:ConnectLogWriter.WriteLine("[$ts] [$Level] [$sid] $Message")
        # Local always complete. Sync carefully:
        # - TRACE/DEBUG stay local-only during hot loops (were causing False spam + multi-minute stalls)
        # - WARN/ERROR flush now; INFO every 25 lines
        if ($Level -eq 'TRACE' -or $Level -eq 'DEBUG') { return }
        $script:ConnectLogLinesSinceSync = [int]$script:ConnectLogLinesSinceSync + 1
        if ($Level -eq 'WARN' -or $Level -eq 'ERROR' -or $script:ConnectLogLinesSinceSync -ge 25) {
            Sync-ConnectLogToServer
        }
    } catch {
        # Writer may have died; drop handle so next line re-opens.
        try { if ($script:ConnectLogWriter) { $script:ConnectLogWriter.Dispose() } } catch { }
        $script:ConnectLogWriter = $null
    }
}'''

if old_wl not in ui:
    raise SystemExit('Write-ConnectLog block not found exactly')
ui = ui.replace(old_wl, new_ensure_and_wl, 1)

# Cap sync chunk to 512KB to avoid multi-second hangs on huge day logs
old_chunk = '''        $chunk = New-Object byte[] ($all.Length - $off)
        [Array]::Copy($all, $off, $chunk, 0, $chunk.Length)
        $tmpLocal = Join-Path $env:TEMP ("claude-connect-chunk-{0}.log" -f $PID)
        [System.IO.File]::WriteAllBytes($tmpLocal, $chunk)'''
new_chunk = '''        # Cap chunk size so a multi-MB day log does not freeze UI on one scp.
        $maxChunk = 512KB
        $remain = $all.Length - $off
        $take = if ($remain -gt $maxChunk) { [int]$maxChunk } else { [int]$remain }
        $chunk = New-Object byte[] $take
        [Array]::Copy($all, $off, $chunk, 0, $take)
        $tmpLocal = Join-Path $env:TEMP ("claude-connect-chunk-{0}.log" -f $PID)
        [System.IO.File]::WriteAllBytes($tmpLocal, $chunk)'''
if old_chunk not in ui:
    raise SystemExit('chunk block not found')
ui = ui.replace(old_chunk, new_chunk, 1)

old_off = '''            $script:ConnectLogSyncOffset = $all.Length
            Write-ConnectLogSyncWatermark -Offset $script:ConnectLogSyncOffset -LogPath $script:ConnectLogPath
            $script:ConnectLogLinesSinceSync = 0
            $script:LastConnectLogSyncOk = $true
            $script:ConnectLogSyncFailLogged = $false'''
new_off = '''            $script:ConnectLogSyncOffset = $off + $take
            Write-ConnectLogSyncWatermark -Offset $script:ConnectLogSyncOffset -LogPath $script:ConnectLogPath
            $script:ConnectLogLinesSinceSync = 0
            $script:LastConnectLogSyncOk = $true
            $script:ConnectLogSyncFailLogged = $false
            # If more remains, schedule another batch soon (next INFO/WARN).
            if ($script:ConnectLogSyncOffset -lt $all.Length) {
                $script:ConnectLogLinesSinceSync = 25
            }'''
if old_off not in ui:
    raise SystemExit('offset advance block not found')
ui = ui.replace(old_off, new_off, 1)

# --- 2) Single-instance mutex ---
mutex_fns = r'''
function Enter-ConnectSingleInstance {
    # One connect UI per Windows user. Prevents Sepidz+Smart dual tunnels fighting.
    param([string]$Name = '')
    if (-not $Name) { $Name = ("Global\ClaudeConnect-{0}" -f $env:USERNAME) }
    try {
        $created = $false
        $m = New-Object System.Threading.Mutex($false, $Name, [ref]$created)
        $script:ConnectInstanceMutex = $m
        if (-not $m.WaitOne(0)) {
            try { $m.Dispose() } catch { }
            $script:ConnectInstanceMutex = $null
            Write-Host ''
            Write-Host '  [X] Another Claude Connect is already running on this PC.' -ForegroundColor Red
            Write-Host '      Close it (Q) first. Running two (Smart+Sepidz) breaks tunnel/logs.' -ForegroundColor Yellow
            Write-Host ''
            return $false
        }
        Write-ConnectLog ("SINGLE_INSTANCE: acquired mutex={0} pid={1}" -f $Name, $PID) 'INFO'
        return $true
    } catch {
        # If mutex APIs fail, do not block connect.
        Write-ConnectLog ("SINGLE_INSTANCE: mutex error (continue): {0}" -f $_.Exception.Message) 'WARN'
        return $true
    }
}

function Exit-ConnectSingleInstance {
    try {
        if ($script:ConnectInstanceMutex) {
            try { $script:ConnectInstanceMutex.ReleaseMutex() } catch { }
            try { $script:ConnectInstanceMutex.Dispose() } catch { }
            $script:ConnectInstanceMutex = $null
        }
    } catch { }
}

'''

# insert before Initialize-ConnectLog
anchor = 'function Initialize-ConnectLog {'
if 'function Enter-ConnectSingleInstance' not in ui:
    ui = ui.replace(anchor, mutex_fns + anchor, 1)

# Close-ConnectLog should release mutex
if 'Exit-ConnectSingleInstance' not in ui[ui.find('function Close-ConnectLog'):ui.find('function Close-ConnectLog')+900]:
    close_anchor = 'function Close-ConnectLog'
    # find dispose section and add exit before end
    c0 = ui.find('function Close-ConnectLog')
    c1 = ui.find('\nfunction ', c0 + 10)
    close_body = ui[c0:c1]
    if 'Exit-ConnectSingleInstance' not in close_body:
        # append call before final closing of function - find last Sync in close
        if 'Sync-ConnectLogToServer | Out-Null' in close_body:
            close_body2 = close_body.replace(
                'Sync-ConnectLogToServer | Out-Null',
                'Sync-ConnectLogToServer | Out-Null\n    Exit-ConnectSingleInstance',
                1)
            ui = ui[:c0] + close_body2 + ui[c1:]
        else:
            # inject before last }
            last_brace = close_body.rfind('}')
            close_body2 = close_body[:last_brace] + '    Exit-ConnectSingleInstance\n' + close_body[last_brace:]
            ui = ui[:c0] + close_body2 + ui[c1:]

ui_path.write_text(ui, encoding='utf-8', newline='\n')
print('ui patched')

# connect.ps1: after Initialize-ConnectLog, enter mutex
old_init = 'Initialize-ConnectLog -ScriptDir $script:ConnectScriptDir -Version $script:ConnectVersion\n'
new_init = '''Initialize-ConnectLog -ScriptDir $script:ConnectScriptDir -Version $script:ConnectVersion
if (Get-Command Enter-ConnectSingleInstance -ErrorAction SilentlyContinue) {
    if (-not (Enter-ConnectSingleInstance)) {
        if (Get-Command Wait-ConnectExit -ErrorAction SilentlyContinue) { Wait-ConnectExit -Reason 'single_instance' -Code 2 }
        else { exit 2 }
    }
}
'''
if old_init not in cp:
    raise SystemExit('Initialize-ConnectLog call site not found in connect.ps1')
if 'Enter-ConnectSingleInstance' not in cp:
    cp = cp.replace(old_init, new_init, 1)
cp_path.write_text(cp, encoding='utf-8', newline='\n')
print('connect.ps1 patched')

# Mac: flock lock file
old_mac_log = '''connect_log() {
    local msg="$1" level="${2:-INFO}"
    [ -n "${CONNECT_LOG_PATH:-}" ] || return 0
    printf '[%s] [%s] [%s] %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "${CONNECT_SESSION_ID:--}" "$msg" >> "$CONNECT_LOG_PATH" 2>/dev/null || true'''

# add single instance helpers near init_connect_log
if 'enter_connect_single_instance' not in sh:
    mac_mutex = r'''
enter_connect_single_instance() {
    # One connect per user via flock on lock file.
    local lockdir="${HOME}/.config/claude-connect"
    local lockfile="${lockdir}/connect.lock"
    mkdir -p "$lockdir" 2>/dev/null || true
    exec 9>"$lockfile" || return 0
    if ! flock -n 9; then
        printf '\n  [X] Another Claude Connect is already running on this Mac.\n' >&2
        printf '      Close it (q) first. Two sessions break tunnel/logs.\n\n' >&2
        return 1
    fi
    CONNECT_LOCK_HELD=1
    connect_log "SINGLE_INSTANCE: acquired flock pid=$$" 'INFO'
    return 0
}

exit_connect_single_instance() {
    if [ "${CONNECT_LOCK_HELD:-0}" = 1 ]; then
        flock -u 9 2>/dev/null || true
        CONNECT_LOCK_HELD=0
    fi
}

'''
    sh = sh.replace('init_connect_log() {', mac_mutex + 'init_connect_log() {', 1)
    sh_path.write_text(sh, encoding='utf-8', newline='\n')
    print('mac sh patched')
else:
    print('mac already has single instance')

# version bump
ver = root / 'scripts/client/windows/connect-version.txt'
ver.write_text('20260719.13', encoding='ascii', newline='')
# also bump ConnectVersion in connect.ps1 source
cp2 = cp_path.read_text(encoding='utf-8')
cp2 = cp2.replace("$script:ConnectVersion = '20260719.12'", "$script:ConnectVersion = '20260719.13'")
cp2 = cp2.replace("$script:ConnectVersion = '20260719.11'", "$script:ConnectVersion = '20260719.13'")
cp_path.write_text(cp2, encoding='utf-8', newline='\n')
print('version 20260719.13')
print('DONE')
