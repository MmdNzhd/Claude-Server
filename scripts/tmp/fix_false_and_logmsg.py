from pathlib import Path
import re

root = Path(r'D:\Smart\Claude-Code-Server')

# 1) Sync-ConnectLogToServer: never emit bool to pipeline (False leak)
ui = root / 'scripts/client/connect-ui.ps1'
t = ui.read_text(encoding='utf-8')
# Replace return $false/$true with script-scoped last result and bare return
old = '''function Sync-ConnectLogToServer {
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
}'''

new = '''function Sync-ConnectLogToServer {
    param([switch]$Force)
    # IMPORTANT: never return $true/$false to the pipeline — that prints "True"/"False" in the UI.
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
        } else {
            # One DEBUG line max per session burst (avoid spam)
            if (-not $script:ConnectLogSyncFailLogged) {
                $script:ConnectLogSyncFailLogged = $true
                try {
                    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                    $sid = if ($script:ConnectSessionId) { $script:ConnectSessionId } else { '-' }
                    if ($script:ConnectLogWriter) {
                        $script:ConnectLogWriter.WriteLine("[$ts] [WARN] [$sid] LOG_SYNC_FAIL target=$target (local log kept; will retry)")
                    }
                } catch { }
            }
        }
        Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue
    } catch { }
}'''

if old not in t:
    raise SystemExit('Sync function block not found exactly')
t = t.replace(old, new, 1)

# Write-ConnectLog: don't sync every single line (causes slowness!) — every 15 + WARN/ERROR
t = t.replace(
    "if ($Level -eq 'WARN' -or $Level -eq 'ERROR' -or $script:ConnectLogLinesSinceSync -ge 1) {\n            Sync-ConnectLogToServer | Out-Null\n        }",
    "if ($Level -eq 'WARN' -or $Level -eq 'ERROR' -or $script:ConnectLogLinesSinceSync -ge 15) {\n            Sync-ConnectLogToServer\n        }",
)

ui.write_text = None
Path(ui).write_text(t, encoding='utf-8', newline='\n') if False else None
ui.write_text(t, encoding='utf-8', newline='\n')
print('connect-ui Sync fixed')

# 2) Fix log path message in connect.ps1
cp = root / 'scripts/client/windows/connect.ps1'
c = cp.read_text(encoding='utf-8')
c = c.replace(
    '$sessionExtras += "Log: $(Split-Path -Leaf $script:ConnectLogPath) (same folder as connect.bat)"',
    '$sessionExtras += "Log: $($script:ConnectLogPath)"',
)
# Out-Null all Sync-ConnectLogToServer bare calls
c = c.replace(
    'if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer }',
    'if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null }',
)
# also without if
cp.write_text(c, encoding='utf-8', newline='\n')
print('connect.ps1 messages fixed')

# connect-ui Close-ConnectLog Sync calls
t2 = ui.read_text(encoding='utf-8')
t2 = t2.replace(
    'if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer }',
    'if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null }',
)
ui.write_text(t2, encoding='utf-8', newline='\n')
print('ui Close sync Out-Null')
