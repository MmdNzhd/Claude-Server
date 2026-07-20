# -*- coding: utf-8 -*-
from pathlib import Path
import re

root = Path(r'D:\Smart\Claude-Code-Server')
ui = root / 'scripts/client/connect-ui.ps1'
t = ui.read_text(encoding='utf-8')

# Replace entire Sync-ConnectLogToServer function via anchors
s = t.find('function Sync-ConnectLogToServer')
e = t.find('function Write-ConnectLog')
if s < 0 or e < 0:
    raise SystemExit(f'anchors s={s} e={e}')

new_sync = r'''function Sync-ConnectLogToServer {
    param([switch]$Force)
    # Never emit True/False to pipeline (was printing "False" in the connect UI).
    $script:LastConnectLogSyncOk = $false
    if (-not $script:ConnectLogPath -or -not (Test-Path -LiteralPath $script:ConnectLogPath)) { return }
    $target = Get-ConnectLogSyncTarget
    if (-not $target) { return }
    try {
        if ($script:ConnectLogWriter) { try { $script:ConnectLogWriter.Flush() } catch { } }
        $all = [System.IO.File]::ReadAllBytes($script:ConnectLogPath)
        $off = [int]$script:ConnectLogSyncOffset
        if ($off -lt 0) { $off = 0 }
        if ($off -gt $all.Length) { $off = 0 }
        if ($off -ge $all.Length) { $script:LastConnectLogSyncOk = $true; return }
        $chunk = New-Object byte[] ($all.Length - $off)
        [Array]::Copy($all, $off, $chunk, 0, $chunk.Length)
        $tmpLocal = Join-Path $env:TEMP ("claude-connect-chunk-{0}.log" -f $PID)
        [System.IO.File]::WriteAllBytes($tmpLocal, $chunk)
        $day = Get-Date -Format 'yyyyMMdd'
        $remoteTmp = ".claude/logs/.connect-buf-$PID.tmp"
        $remoteDay = ".claude/logs/connect-$day.log"
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
            $script:LastConnectLogSyncOk = $true
            $script:ConnectLogSyncFailLogged = $false
        } elseif (-not $script:ConnectLogSyncFailLogged) {
            $script:ConnectLogSyncFailLogged = $true
            try {
                $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                $sid = if ($script:ConnectSessionId) { $script:ConnectSessionId } else { '-' }
                if ($script:ConnectLogWriter) {
                    $script:ConnectLogWriter.WriteLine("[$ts] [WARN] [$sid] LOG_SYNC_FAIL target=$target (local kept; retry later)")
                }
            } catch { }
        }
        Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue
    } catch { }
}

'''

t = t[:s] + new_sync + t[e:]

# Fix Write-ConnectLog sync policy: never on TRACE/DEBUG; WARN/ERROR immediate; INFO every 25
old_w = '''function Write-ConnectLog {
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
        if ($Level -eq 'WARN' -or $Level -eq 'ERROR' -or $script:ConnectLogLinesSinceSync -ge 1) {
            Sync-ConnectLogToServer | Out-Null
        }
    } catch { }
}'''

# flexible match current
m = re.search(
    r"function Write-ConnectLog \{.*?^\}\n",
    t,
    re.M | re.S,
)
if not m:
    raise SystemExit('Write-ConnectLog not found')

new_w = '''function Write-ConnectLog {
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
}
'''

t = t[:m.start()] + new_w + t[m.end():]

# Out-Null bare Sync in Close/context
t = t.replace(
    'if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer }',
    'if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null }',
)

ui.write_text(t, encoding='utf-8', newline='\n')
print('ui OK')

cp = root / 'scripts/client/windows/connect.ps1'
c = cp.read_text(encoding='utf-8')
c = c.replace(
    '$sessionExtras += "Log: $(Split-Path -Leaf $script:ConnectLogPath) (same folder as connect.bat)"',
    '$sessionExtras += "Log: $($script:ConnectLogPath)"',
)
c = c.replace(
    'if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer }',
    'if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null }',
)
# also the comment variant
c = c.replace(
    'if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer }  # ship BOOTSTRAP/UPDATE + session so far',
    'if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null }  # ship BOOTSTRAP/UPDATE + session so far',
)
cp.write_text(c, encoding='utf-8', newline='\n')
print('connect.ps1 OK')
print('DONE')
