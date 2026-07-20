# -*- coding: utf-8 -*-
"""Apply zero-loss offline-first logging (industry pattern) to connect client."""
from pathlib import Path
import re

root = Path(r'D:\Smart\Claude-Code-Server')
ui = root / 'scripts/client/connect-ui.ps1'
text = ui.read_text(encoding='utf-8')

# Replace Get-ConnectLogDir through end of Sync-ConnectLogToServer + Write-ConnectLog
# with full zero-loss implementation.

new_block = r'''function Get-ConnectLogDir {
    $dir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch { }
    return $dir
}

function Get-ConnectLogDayPath {
    $day = Get-Date -Format 'yyyyMMdd'
    return (Join-Path (Get-ConnectLogDir) ("connect-{0}.log" -f $day))
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

function Initialize-ConnectLog {
    param(
        [Parameter(Mandatory)][string]$ScriptDir,
        [string]$Version = ''
    )
    # Zero-loss offline-first (industry pattern):
    # 1) Always append durable local day file
    # 2) Watermark sync-offset so BOOTSTRAP/UPDATE lines written before this process still ship
    # 3) Batch-flush to server ~/.claude/logs when SSH works
    # 4) Nightly cleanup on server (mtime +1) — space is fine during the day
    try {
        $legacy = Join-Path $ScriptDir 'connect.log'
        if (Test-Path -LiteralPath $legacy) { Remove-Item -LiteralPath $legacy -Force -ErrorAction SilentlyContinue }
        $legacy1 = Join-Path $ScriptDir 'connect.log.1'
        if (Test-Path -LiteralPath $legacy1) { Remove-Item -LiteralPath $legacy1 -Force -ErrorAction SilentlyContinue }
    } catch { }
    if (-not $script:ConnectSessionId) {
        $script:ConnectSessionId = [guid]::NewGuid().ToString('N').Substring(0, 12)
    }
    $script:ConnectLogPath = Get-ConnectLogDayPath
    $script:ConnectLogSyncOffset = Read-ConnectLogSyncWatermark -LogPath $script:ConnectLogPath
    $script:ConnectLogLinesSinceSync = 0
    try {
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
    Write-ConnectLog "======== session start v$Version user=$env:USERNAME elevated=$elev pid=$PID session=$($script:ConnectSessionId) ========"
    Write-ConnectLog "log sink: local:$($script:ConnectLogPath) watermark=$($script:ConnectLogSyncOffset) + server:~/.claude/logs/ (nightly purge)"
    Write-ConnectLog "script_dir: $ScriptDir connect_version: $Version" 'DEBUG'
}

function Sync-ConnectLogToServer {
    param([switch]$Force)
    if (-not $script:ConnectLogPath -or -not (Test-Path -LiteralPath $script:ConnectLogPath)) { return $false }
    $target = Get-ConnectLogSyncTarget
    if (-not $target) { return $false }
    try {
        if ($script:ConnectLogWriter) { try { $script:ConnectLogWriter.Flush() } catch { } }
        $all = [System.IO.File]::ReadAllBytes($script:ConnectLogPath)
        $off = [int]$script:ConnectLogSyncOffset
        if ($off -lt 0) { $off = 0 }
        if ($off -gt $all.Length) { $off = 0 }
        if ($off -ge $all.Length) { return $true }
        $chunk = New-Object byte[] ($all.Length - $off)
        [Array]::Copy($all, $off, $chunk, 0, $chunk.Length)
        $tmpLocal = Join-Path $env:TEMP ("claude-connect-chunk-{0}.log" -f $PID)
        [System.IO.File]::WriteAllBytes($tmpLocal, $chunk)
        $day = Get-Date -Format 'yyyyMMdd'
        $remoteTmp = ".claude/logs/.connect-buf-$PID.tmp"
        $remoteDay = ".claude/logs/connect-$day.log"
        # mkdir via ssh (SshX if available, else raw ssh)
        $mk = 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; find "$HOME/.claude/logs" -type f -mtime +1 -delete 2>/dev/null; true'
        if (Get-Command SshX -ErrorAction SilentlyContinue) {
            SshX $mk 2>$null | Out-Null
        } else {
            $null = & ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlMaster=no $target $mk 2>$null
        }
        & scp -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no -q $tmpLocal "${target}:$remoteTmp" 2>$null
        $scpOk = ($LASTEXITCODE -eq 0)
        if ($scpOk) {
            $cat = "cat `"$HOME/$remoteTmp`" >> `"$HOME/$remoteDay`" 2>/dev/null; rm -f `"$HOME/$remoteTmp`"; chmod 600 `"$HOME/$remoteDay`" 2>/dev/null; true"
            if (Get-Command SshX -ErrorAction SilentlyContinue) {
                SshX $cat 2>$null | Out-Null
            } else {
                $null = & ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlMaster=no $target $cat 2>$null
            }
            $script:ConnectLogSyncOffset = $all.Length
            Write-ConnectLogSyncWatermark -Offset $script:ConnectLogSyncOffset -LogPath $script:ConnectLogPath
            $script:ConnectLogLinesSinceSync = 0
        }
        Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue
        return $scpOk
    } catch {
        return $false
    }
}

function Write-ConnectLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'INFO'
    )
    if (-not $script:ConnectLogWriter) { return }
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = if ($script:ConnectSessionId) { $script:ConnectSessionId } else { '-' }
        $script:ConnectLogWriter.WriteLine("[$ts] [$Level] [$sid] $Message")
        $script:ConnectLogLinesSinceSync = [int]$script:ConnectLogLinesSinceSync + 1
        # Batch flush: every 20 lines, or immediately on WARN/ERROR (zero-loss + low latency for failures)
        if ($Level -eq 'WARN' -or $Level -eq 'ERROR' -or $script:ConnectLogLinesSinceSync -ge 20) {
            Sync-ConnectLogToServer | Out-Null
        }
    } catch { }
}

'''

# Find start of Get-ConnectLogDir or Initialize-ConnectLog (after Get-ConnectLogDir was added)
s = text.find('function Get-ConnectLogDir')
if s < 0:
    s = text.find('function Initialize-ConnectLog')
e = text.find('function Write-ConnectTrace')
if s < 0 or e < 0:
    raise SystemExit(f'anchors missing s={s} e={e}')
text = text[:s] + new_block + text[e:]

# Fix Write-ConnectSessionContext sync call - already Sync-ConnectLogToServer
# Close-ConnectLog already keeps local - ensure Force sync
text = text.replace('mtime +7 -delete', 'mtime +1 -delete')

ui.write_text(text, encoding='utf-8', newline='\n')
print('connect-ui.ps1 zero-loss OK')

# ---- connect-update.ps1: layered SSH diagnostics + flush local log to server after update ----
cu = root / 'scripts/client/windows/connect-update.ps1'
cut = cu.read_text(encoding='utf-8')

# Enhance Write-UpdateFileLog area + Invoke-SshTimed logging of err
if 'UPDATE_SSH_STAGE' not in cut:
    # After Invoke-SshTimed returns, log failures in Invoke-SshCat and Resolve
    old_cat = '''function Invoke-SshCat {
    param([string]$Target, [string]$RemotePath)
    $args = $script:SshCommonOpts + @($Target, "cat '$RemotePath'")
    $r = Invoke-SshTimed -ArgumentList $args -TimeoutMs 20000 -RequireStdout
    if (-not $r.Ok) { return $null }
    return $r.Out
}'''
    new_cat = '''function Invoke-SshCat {
    param([string]$Target, [string]$RemotePath)
    Write-UpdateFileLog ("SSH_STAGE cat begin target=$Target path=$RemotePath")
    $args = $script:SshCommonOpts + @($Target, "cat '$RemotePath'")
    $r = Invoke-SshTimed -ArgumentList $args -TimeoutMs 20000 -RequireStdout
    if (-not $r.Ok) {
        $err = ''
        if ($r.ContainsKey('Err')) { $err = [string]$r.Err }
        if ($err.Length -gt 300) { $err = $err.Substring(0, 300) }
        Write-UpdateFileLog ("SSH_STAGE cat FAIL target=$Target exit=$($r.ExitCode) err=$err") 'WARN'
        return $null
    }
    Write-UpdateFileLog ("SSH_STAGE cat OK target=$Target bytes=$($r.Out.Length)")
    return $r.Out
}'''
    if old_cat in cut:
        cut = cut.replace(old_cat, new_cat, 1)
        print('Invoke-SshCat layered OK')
    else:
        print('WARN Invoke-SshCat block mismatch')

    old_dl = '''    $r = Invoke-SshTimed -Exe 'scp' -ArgumentList $scpOpts -TimeoutMs 180000
    if (-not $r.Ok) { return $false }
    $any = @(Get-ChildItem $LocalStagingRoot -Recurse -File -ErrorAction SilentlyContinue)
    return ($any.Count -gt 0)
}'''
    new_dl = '''    Write-UpdateFileLog ("SSH_STAGE scp begin target=$Target remote=$RemoteBundlePath")
    $r = Invoke-SshTimed -Exe 'scp' -ArgumentList $scpOpts -TimeoutMs 180000
    if (-not $r.Ok) {
        $err = ''
        if ($r.ContainsKey('Err')) { $err = [string]$r.Err }
        if ($err.Length -gt 400) { $err = $err.Substring(0, 400) }
        Write-UpdateFileLog ("SSH_STAGE scp FAIL target=$Target exit=$($r.ExitCode) err=$err") 'ERROR'
        return $false
    }
    $any = @(Get-ChildItem $LocalStagingRoot -Recurse -File -ErrorAction SilentlyContinue)
    Write-UpdateFileLog ("SSH_STAGE scp OK files=$($any.Count)")
    return ($any.Count -gt 0)
}'''
    if old_dl in cut:
        cut = cut.replace(old_dl, new_dl, 1)
        print('scp layered OK')
    else:
        print('WARN scp block mismatch')

# Resolve logging
if 'Resolve-UpdateEndpoint' in cut and 'SSH_STAGE resolve' not in cut:
    cut = cut.replace(
        'function Resolve-UpdateEndpoint {\n    # Try laptop REMOTE_USER first, then sepidz/smart service account.\n    $primary = Get-ServerEndpoint\n',
        'function Resolve-UpdateEndpoint {\n    # Try laptop REMOTE_USER first, then sepidz/smart service account.\n    $primary = Get-ServerEndpoint\n    Write-UpdateFileLog ("SSH_STAGE resolve primary=$($primary.Display)")\n',
        1,
    )
    cut = cut.replace(
        '        Write-UpdateMsg ("Update retry via {0}" -f $fb) \'DarkGray\'\n',
        '        Write-UpdateMsg ("Update retry via {0}" -f $fb) \'DarkGray\'\n        Write-UpdateFileLog ("SSH_STAGE resolve fallback=$fb")\n',
        1,
    )
    print('resolve log OK')

# After successful update apply - look for exit 2
if 'Write-UpdateFileLog "applied' not in cut:
    # find exit 2 pattern
    if 'exit 2' in cut:
        cut = cut.replace(
            'exit 2',
            'Write-UpdateFileLog "applied_ok need_relaunch exit=2"\n    # best-effort: ship UPDATE lines to server now (same durable log path)\n    try {\n        $dayLog = Get-UpdateLogPath\n        $cfg = Join-Path $env:USERPROFILE \'.config\\claude-connect\\connect.conf\'\n        $ru=\'\'; $sip=\'\'\n        if (Test-Path $cfg) {\n            Get-Content $cfg | ForEach-Object {\n                if ($_ -match \'^REMOTE_USER=(.+)$\') { $ru=$Matches[1].Trim() }\n            }\n        }\n        if (Get-Command Get-LocalServerIp -ErrorAction SilentlyContinue) { $sip = Get-LocalServerIp }\n        if ($ru -and $sip -and (Test-Path $dayLog)) {\n            $t = "{0}@{1}" -f $ru,$sip\n            $remoteDay = ".claude/logs/connect-$(Get-Date -Format yyyyMMdd).log"\n            ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlMaster=no $t \'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs"\' 2>$null | Out-Null\n            scp -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no -q $dayLog "${t}:$remoteDay.upload" 2>$null\n            if ($LASTEXITCODE -eq 0) {\n                ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlMaster=no $t "cat \\"\\$HOME/$remoteDay.upload\\" >> \\"\\$HOME/$remoteDay\\"; rm -f \\"\\$HOME/$remoteDay.upload\\"; chmod 600 \\"\\$HOME/$remoteDay\\"" 2>$null | Out-Null\n                Write-UpdateFileLog "shipped_day_log_to_server target=$t"\n            }\n        }\n    } catch { }\n    exit 2',
            1,
        )
        print('exit 2 ship log OK')

cu.write_text(cut, encoding='utf-8', newline='\n')
print('connect-update.ps1 OK')

# ---- Mac parity: watermark + session id + flush ----
sh = root / 'scripts/client/connect-ui.sh'
st = sh.read_text(encoding='utf-8')
st = st.replace('mtime +7 -delete', 'mtime +1 -delete')

old_init = '''init_connect_log() {
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

new_init = '''init_connect_log() {
    local script_dir="$1" version="$2" day log_dir wm
    # Zero-loss offline-first: durable local day file + watermark sync-offset + server flush.
    day="$(date +%Y%m%d)"
    log_dir="$HOME/.config/claude-connect/logs"
    mkdir -p "$log_dir" 2>/dev/null || true
    CONNECT_LOG_PATH="$log_dir/connect-${day}.log"
    CONNECT_SESSION_ID="$(date +%s)-$$"
    wm="${CONNECT_LOG_PATH}.sync-offset"
    CONNECT_LOG_SYNC_OFF=0
    if [ -f "$wm" ]; then
        CONNECT_LOG_SYNC_OFF="$(tr -dc '0-9' < "$wm")"
    fi
    : "${CONNECT_LOG_SYNC_OFF:=0}"
    touch "$CONNECT_LOG_PATH" 2>/dev/null || true
    chmod 600 "$CONNECT_LOG_PATH" 2>/dev/null || true
    CONNECT_LOG_LINES_SINCE_SYNC=0
    connect_log "======== session start v$version user=$USER pid=$$ session=$CONNECT_SESSION_ID ========"
    connect_log "log sink: local:$CONNECT_LOG_PATH watermark=$CONNECT_LOG_SYNC_OFF + server:~/.claude/logs/ (nightly purge)" 'INFO'
    connect_log "script_dir: $script_dir connect_version: $version" 'DEBUG'
}'''

if old_init in st:
    st = st.replace(old_init, new_init, 1)
    print('mac init zero-loss OK')
else:
    print('WARN mac init pattern missing')

# update connect_log to include session + batch sync
old_cl = '''connect_log() {
    local msg="$1" level="${2:-INFO}"
    [ -n "${CONNECT_LOG_PATH:-}" ] || return 0
    printf '[%s] [%s] %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg" >> "$CONNECT_LOG_PATH" 2>/dev/null || true
}'''
new_cl = '''connect_log() {
    local msg="$1" level="${2:-INFO}"
    [ -n "${CONNECT_LOG_PATH:-}" ] || return 0
    printf '[%s] [%s] [%s] %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "${CONNECT_SESSION_ID:--}" "$msg" >> "$CONNECT_LOG_PATH" 2>/dev/null || true
    CONNECT_LOG_LINES_SINCE_SYNC=$(( ${CONNECT_LOG_LINES_SINCE_SYNC:-0} + 1 ))
    if [ "$level" = "WARN" ] || [ "$level" = "ERROR" ] || [ "${CONNECT_LOG_LINES_SINCE_SYNC:-0}" -ge 20 ]; then
        sync_connect_log_to_server || true
    fi
}'''
if old_cl in st:
    st = st.replace(old_cl, new_cl, 1)
    print('mac connect_log OK')
else:
    print('WARN mac connect_log missing')

# after successful sync, write watermark
if 'sync-offset' not in st.split('sync_connect_log_to_server')[1][:1200]:
    st = st.replace(
        '            CONNECT_LOG_SYNC_OFF="$(wc -c < "$CONNECT_LOG_PATH" | tr -dc \'0-9\')"\n',
        '            CONNECT_LOG_SYNC_OFF="$(wc -c < "$CONNECT_LOG_PATH" | tr -dc \'0-9\')"\n'
        '            printf \'%s\' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset" 2>/dev/null || true\n'
        '            CONNECT_LOG_LINES_SINCE_SYNC=0\n',
        1,
    )
    print('mac watermark write OK')

# sync should use watermark not skip - currently uses CONNECT_LOG_SYNC_OFF from init which is now watermark - good
# But old init set OFF to file size - fixed

sh.write_text(st, encoding='utf-8', newline='\n')
print('connect-ui.sh OK')

# cleanup script comment already +1
cleanup = root / 'scripts/server/claude-connect-logs-cleanup.sh'
ct = cleanup.read_text(encoding='utf-8')
ct = ct.replace('older than 7 days', 'older than 1 day (nightly)')
ct = ct.replace('mtime +7', 'mtime +1')
cleanup.write_text(ct, encoding='utf-8', newline='\n')
print('cleanup nightly OK')

print('DONE')
