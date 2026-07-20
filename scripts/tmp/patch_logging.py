# -*- coding: utf-8 -*-
from pathlib import Path

root = Path(r'D:\Smart\Claude-Code-Server')

# ---- connect-ui.ps1 ----
ui = root / 'scripts/client/connect-ui.ps1'
text = ui.read_text(encoding='utf-8')

new_init = r'''function Get-ConnectLogDir {
    $dir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch { }
    return $dir
}

function Get-ConnectLogDayPath {
    $day = Get-Date -Format 'yyyyMMdd'
    return (Join-Path (Get-ConnectLogDir) ("connect-{0}.log" -f $day))
}

function Initialize-ConnectLog {
    param(
        [Parameter(Mandatory)][string]$ScriptDir,
        [string]$Version = ''
    )
    # Durable on laptop AND server. Temp-only lost logs when SSH/update failed.
    try {
        $legacy = Join-Path $ScriptDir 'connect.log'
        if (Test-Path -LiteralPath $legacy) { Remove-Item -LiteralPath $legacy -Force -ErrorAction SilentlyContinue }
        $legacy1 = Join-Path $ScriptDir 'connect.log.1'
        if (Test-Path -LiteralPath $legacy1) { Remove-Item -LiteralPath $legacy1 -Force -ErrorAction SilentlyContinue }
    } catch { }
    $script:ConnectLogPath = Get-ConnectLogDayPath
    $script:ConnectLogSyncOffset = 0
    try {
        if (Test-Path -LiteralPath $script:ConnectLogPath) {
            $script:ConnectLogSyncOffset = ([System.IO.FileInfo]$script:ConnectLogPath).Length
        }
        $script:ConnectLogWriter = [System.IO.StreamWriter]::new(
            $script:ConnectLogPath, $true, [System.Text.UTF8Encoding]::new($false))
        $script:ConnectLogWriter.AutoFlush = $true
    } catch {
        $script:ConnectLogWriter = $null
        return
    }
    $elev = 'unknown'
    if (Get-Command Test-IsElevatedShell -ErrorAction SilentlyContinue) {
        $elev = if (Test-IsElevatedShell) { 'yes' } else { 'no' }
    }
    Write-ConnectLog "======== session start v$Version user=$env:USERNAME elevated=$elev pid=$PID ========"
    Write-ConnectLog "log sink: local:$($script:ConnectLogPath) + server:~/.claude/logs/"
    Write-ConnectLog "script_dir: $ScriptDir connect_version: $Version" 'DEBUG'
}

'''

s = text.find('function Initialize-ConnectLog')
if s < 0:
    raise SystemExit('Initialize-ConnectLog missing')
e = text.find('function Sync-ConnectLogToServer', s)
if e < 0:
    raise SystemExit('Sync missing')
text = text[:s] + new_init + text[e:]

old_close_tail = '''    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer }
    try {
        if ($script:ConnectLogPath -and (Test-Path -LiteralPath $script:ConnectLogPath)) {
            Remove-Item -LiteralPath $script:ConnectLogPath -Force -ErrorAction SilentlyContinue
        }
    } catch { }
    $script:ConnectLogPath = ''
    $script:ConnectLogSyncOffset = 0
}'''

new_close_tail = '''    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer }
    # Keep durable local day log so offline / failed-SSH sessions remain auditable.
    $script:ConnectLogPath = ''
    $script:ConnectLogSyncOffset = 0
}'''

if old_close_tail not in text:
    raise SystemExit('Close-ConnectLog tail not found')
text = text.replace(old_close_tail, new_close_tail, 1)
text = text.replace('mtime +1 -delete', 'mtime +7 -delete')
ui.write_text(text, encoding='utf-8', newline='\n')
print('connect-ui.ps1 OK')

# ---- connect-update.ps1 ----
cu = root / 'scripts/client/windows/connect-update.ps1'
cut = cu.read_text(encoding='utf-8')
if 'Write-UpdateFileLog' not in cut:
    helper = r'''
function Get-UpdateLogPath {
    $dir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch { }
    $day = Get-Date -Format 'yyyyMMdd'
    return (Join-Path $dir ("connect-{0}.log" -f $day))
}

function Write-UpdateFileLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        Add-Content -LiteralPath (Get-UpdateLogPath) -Value "[$ts] [$Level] UPDATE: $Message" -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

'''
    idx = cut.find('function Get-ConnectVersionParts')
    if idx < 0:
        raise SystemExit('Get-ConnectVersionParts missing')
    cut = cut[:idx] + helper + cut[idx:]

replacements = [
    (
        '$localVer = Get-LocalVersion\nif (-not $localVer) { exit 0 }',
        '$localVer = Get-LocalVersion\nWrite-UpdateFileLog ("bat_launch script_dir=$ScriptDir local_ver=$localVer")\nif (-not $localVer) { Write-UpdateFileLog \'no local connect-version.txt - skip\' \'WARN\'; exit 0 }',
    ),
    (
        "Write-UpdateMsg (\"Client update check skipped (unreachable: {0})\" -f $ep.Display) 'DarkYellow'\n    exit 0",
        "Write-UpdateMsg (\"Client update check skipped (unreachable: {0})\" -f $ep.Display) 'DarkYellow'\n    Write-UpdateFileLog (\"unreachable ep=$($ep.Display)\") 'WARN'\n    exit 0",
    ),
    (
        "Write-UpdateMsg \"Client up to date (v$localVer)\" 'DarkGray'\n    exit 0",
        "Write-UpdateMsg \"Client up to date (v$localVer)\" 'DarkGray'\n    Write-UpdateFileLog \"up_to_date v$localVer\"\n    exit 0",
    ),
    (
        "Write-UpdateMsg \"Client update available: v$localVer -> v$remoteVer\" 'Cyan'",
        "Write-UpdateMsg \"Client update available: v$localVer -> v$remoteVer\" 'Cyan'\nWrite-UpdateFileLog \"available v$localVer -> v$remoteVer\"",
    ),
    (
        "Write-UpdateMsg '[!] Update download failed - using local copy' 'DarkYellow'",
        "Write-UpdateMsg '[!] Update download failed - using local copy' 'DarkYellow'\n    Write-UpdateFileLog 'download_failed' 'ERROR'",
    ),
]

for old, new in replacements:
    if old not in cut:
        print('WARN missing block:', old[:60].replace('\n',' '))
    else:
        cut = cut.replace(old, new, 1)
        print('patched:', old[:40].replace('\n',' '))

# also log when Resolve returns null - check pattern
if 'if (-not $resolved)' in cut and "Write-UpdateFileLog (\"unreachable" not in cut.split('if (-not $resolved)')[1][:400]:
    cut = cut.replace(
        'if (-not $resolved) {\n    $ep = Get-ServerEndpoint\n    Write-UpdateMsg ("Client update check skipped (unreachable: {0})" -f $ep.Display) \'DarkYellow\'\n    exit 0\n}',
        'if (-not $resolved) {\n    $ep = Get-ServerEndpoint\n    Write-UpdateMsg ("Client update check skipped (unreachable: {0})" -f $ep.Display) \'DarkYellow\'\n    Write-UpdateFileLog ("unreachable ep=$($ep.Display)") \'WARN\'\n    exit 0\n}',
        1,
    )
    print('patched resolved-null')

cu.write_text(cut, encoding='utf-8', newline='\n')
print('connect-update.ps1 OK')

# ---- connect.bat ----
bat = root / 'scripts/client/windows/connect.bat'
bt = bat.read_text(encoding='utf-8')
if 'BOOTSTRAP' not in bt:
    boot = (
        'REM Log double-click immediately (before update) — durable local day log\r\n'
        'powershell -NoProfile -ExecutionPolicy Bypass -Command '
        '"try { $d=Join-Path $env:USERPROFILE \'.config\\claude-connect\\logs\'; '
        'New-Item -ItemType Directory -Force -Path $d|Out-Null; '
        '$f=Join-Path $d (\'connect-{0}.log\' -f (Get-Date -Format \'yyyyMMdd\')); '
        '$ts=Get-Date -Format \'yyyy-MM-dd HH:mm:ss.fff\'; '
        'Add-Content -LiteralPath $f -Value (\'[{0}] [INFO] BOOTSTRAP: connect.bat start here={1}\' -f $ts, \'%HERE%\') '
        '-Encoding UTF8 } catch {}" 2>nul\r\n\r\n'
    )
    needle = 'title Claude Connect\r\n\r\n'
    if needle not in bt:
        needle = 'title Claude Connect\n\n'
        boot = boot.replace('\r\n', '\n')
    if needle not in bt:
        raise SystemExit('title Claude Connect not found')
    bt = bt.replace(needle, 'title Claude Connect\r\n\r\n' + boot if '\r\n' in needle else 'title Claude Connect\n\n' + boot, 1)
    bat.write_text(bt, encoding='utf-8', newline='')
    print('connect.bat OK')
else:
    print('connect.bat already bootstrapped')

# ---- mac connect-ui.sh ----
sh = root / 'scripts/client/connect-ui.sh'
st = sh.read_text(encoding='utf-8')
st = st.replace('mtime +1 -delete', 'mtime +7 -delete')
old_init_sh = '''init_connect_log() {
    local script_dir="$1" version="$2"
    # Never store under the user's config dir (privacy / support reads from server only).
    rm -rf "$HOME/.config/claude-connect/logs" 2>/dev/null || true
    CONNECT_LOG_PATH="$(mktemp "${TMPDIR:-/tmp}/claude-connect.log.XXXXXX")"
    CONNECT_LOG_SYNC_OFF=0
    chmod 600 "$CONNECT_LOG_PATH" 2>/dev/null || true
    connect_log "======== session start v$version user=$USER pid=$$ ========"
    connect_log "script_dir: $script_dir connect_version: $version log=server:~/.claude/logs/" 'DEBUG'
}'''
new_init_sh = '''init_connect_log() {
    local script_dir="$1" version="$2" day log_dir
    # Durable local + server sync (temp-only lost logs when SSH failed).
    day="$(date +%Y%m%d)"
    log_dir="$HOME/.config/claude-connect/logs"
    mkdir -p "$log_dir" 2>/dev/null || true
    CONNECT_LOG_PATH="$log_dir/connect-${day}.log"
    CONNECT_LOG_SYNC_OFF=0
    if [ -f "$CONNECT_LOG_PATH" ]; then
        CONNECT_LOG_SYNC_OFF="$(wc -c < "$CONNECT_LOG_PATH" | tr -dc '0-9')"
    fi
    touch "$CONNECT_LOG_PATH" 2>/dev/null || true
    chmod 600 "$CONNECT_LOG_PATH" 2>/dev/null || true
    connect_log "======== session start v$version user=$USER pid=$$ ========"
    connect_log "script_dir: $script_dir connect_version: $version log=local:$CONNECT_LOG_PATH + server:~/.claude/logs/" 'DEBUG'
}'''
if old_init_sh not in st:
    print('WARN mac init_connect_log pattern missing')
else:
    st = st.replace(old_init_sh, new_init_sh, 1)
    print('mac init OK')

old_flush = '''flush_connect_log_to_server() {
    if [ -n "${CONNECT_LOG_PATH:-}" ] && [ -f "${CONNECT_LOG_PATH}" ]; then
        connect_log '======== session end ========' || true
    fi
    sync_connect_log_to_server || true
    if [ -n "${CONNECT_LOG_PATH:-}" ] && [ -f "${CONNECT_LOG_PATH}" ]; then
        rm -f "$CONNECT_LOG_PATH" "${CONNECT_LOG_PATH}.chunk" 2>/dev/null || true
    fi
    CONNECT_LOG_PATH=""
    CONNECT_LOG_SYNC_OFF=0
}'''
new_flush = '''flush_connect_log_to_server() {
    if [ -n "${CONNECT_LOG_PATH:-}" ] && [ -f "${CONNECT_LOG_PATH}" ]; then
        connect_log '======== session end ========' || true
    fi
    sync_connect_log_to_server || true
    # Keep durable local day log (do not delete).
    rm -f "${CONNECT_LOG_PATH}.chunk" 2>/dev/null || true
    CONNECT_LOG_PATH=""
    CONNECT_LOG_SYNC_OFF=0
}'''
if old_flush not in st:
    print('WARN mac flush pattern missing')
else:
    st = st.replace(old_flush, new_flush, 1)
    print('mac flush OK')

# comment about server-only
st = st.replace(
    '# Server-only durable logs (no ~/.config/claude-connect/logs on the laptop).\n# Local buffer lives under $TMPDIR and is deleted after upload.\n',
    '# Durable local day logs under ~/.config/claude-connect/logs/ plus sync to server.\n',
)
sh.write_text(st, encoding='utf-8', newline='\n')
print('connect-ui.sh OK')

# mac connect-update.sh - append to same log
mu = root / 'scripts/client/mac/connect-update.sh'
mt = mu.read_text(encoding='utf-8')
if '_update_file_log' not in mt:
    helper = r'''
_update_log_path() {
    local day dir
    day="$(date +%Y%m%d)"
    dir="$HOME/.config/claude-connect/logs"
    mkdir -p "$dir" 2>/dev/null || true
    printf '%s\n' "$dir/connect-${day}.log"
}

_update_file_log() {
    local msg="$1" level="${2:-INFO}"
    printf '[%s] [%s] UPDATE: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg" >> "$(_update_log_path)" 2>/dev/null || true
}

'''
    # insert before main()
    idx = mt.find('main() {')
    if idx < 0:
        raise SystemExit('mac main missing')
    mt = mt[:idx] + helper + mt[idx:]
    mt = mt.replace(
        '    local_ver="$(tr -d \'\\r\\n\' < "$VER_FILE")"\n    target="$(_get_server_target)"',
        '    local_ver="$(tr -d \'\\r\\n\' < "$VER_FILE")"\n    _update_file_log "bat_launch local_ver=$local_ver"\n    target="$(_get_server_target)"',
        1,
    )
    mt = mt.replace(
        '    [ -n "$remote_ver" ] || exit 0\n',
        '    if [ -z "$remote_ver" ]; then _update_file_log "unreachable target=$target" WARN; exit 0; fi\n',
        1,
    )
    mu.write_text(mt, encoding='utf-8', newline='\n')
    print('mac connect-update.sh OK')
else:
    print('mac update already has log')

print('ALL LOGGING PATCHES DONE')
