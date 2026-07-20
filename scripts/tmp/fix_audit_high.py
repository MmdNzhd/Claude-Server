# -*- coding: utf-8 -*-
from pathlib import Path
import re

root = Path(r'D:\Smart\Claude-Code-Server')

# ---- connect-ui.ps1: timed Sync-ConnectLogToServer ----
ui = (root / 'scripts/client/connect-ui.ps1').read_text(encoding='utf-8')

if 'function Invoke-ConnectLogProcTimed' not in ui:
    helper = r'''
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
        Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

'''
    ui = ui.replace('function Sync-ConnectLogToServer {', helper + 'function Sync-ConnectLogToServer {', 1)

# Replace bare ssh/scp block inside Sync-ConnectLogToServer
old_sync_body = r'''        $mk = 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; find "$HOME/.claude/logs" -type f -mtime +1 -delete 2>/dev/null; true'
        if (Get-Command SshX -ErrorAction SilentlyContinue) {
            SshX $mk 2>$null | Out-Null
        } else {
            $null = & ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlMaster=no $target $mk 2>$null
        }
        & scp -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no -q $tmpLocal "${target}:$remoteTmp" 2>$null
        $scpOk = ($LASTEXITCODE -eq 0)
        if ($scpOk) {
            $cat = 'cat "$HOME/' + $remoteTmp + '" >> "$HOME/' + $remoteDay + '" 2>/dev/null; rm -f "$HOME/' + $remoteTmp + '"; chmod 600 "$HOME/' + $remoteDay + '" 2>/dev/null; true'
            if (Get-Command SshX -ErrorAction SilentlyContinue) {
                SshX $cat 2>$null | Out-Null
            } else {
                $null = & ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlMaster=no $target $cat 2>$null
            }
            $script:ConnectLogSyncOffset = $off + $take
            Write-ConnectLogSyncWatermark -Offset $script:ConnectLogSyncOffset -LogPath $script:ConnectLogPath
            $script:ConnectLogLinesSinceSync = 0
            $script:LastConnectLogSyncOk = $true
            $script:ConnectLogSyncFailLogged = $false
            # If more remains, schedule another batch soon (next INFO/WARN).
            if ($script:ConnectLogSyncOffset -lt $all.Length) {
                $script:ConnectLogLinesSinceSync = 25
            }
        } elseif (-not $script:ConnectLogSyncFailLogged) {'''

new_sync_body = r'''        $mk = 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; find "$HOME/.claude/logs" -type f -mtime +1 -delete 2>/dev/null; true'
        $sshOpts = @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no')
        $mkRes = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList ($sshOpts + @($target, $mk)) -TimeoutMs 12000
        if (-not $mkRes.Ok) {
            if (-not $script:ConnectLogSyncFailLogged) {
                $script:ConnectLogSyncFailLogged = $true
                try {
                    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                    $sid = if ($script:ConnectSessionId) { $script:ConnectSessionId } else { '-' }
                    if ($script:ConnectLogWriter) {
                        $script:ConnectLogWriter.WriteLine("[$ts] [WARN] [$sid] LOG_SYNC_FAIL target=$target reason=mkdir_timeout_or_fail (local kept; retry later)")
                    }
                } catch { }
            }
            Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue
            return
        }
        $scpRes = Invoke-ConnectLogProcTimed -Exe 'scp' -ArgumentList (@('-o','BatchMode=yes','-o','ConnectTimeout=12','-o','ControlMaster=no','-q', $tmpLocal, "${target}:$remoteTmp")) -TimeoutMs 20000
        $scpOk = [bool]$scpRes.Ok
        if ($scpOk) {
            $cat = 'cat "$HOME/' + $remoteTmp + '" >> "$HOME/' + $remoteDay + '" 2>/dev/null; rm -f "$HOME/' + $remoteTmp + '"; chmod 600 "$HOME/' + $remoteDay + '" 2>/dev/null; true'
            $catRes = Invoke-ConnectLogProcTimed -Exe 'ssh' -ArgumentList ($sshOpts + @($target, $cat)) -TimeoutMs 12000
            if (-not $catRes.Ok) {
                $scpOk = $false
            }
        }
        if ($scpOk) {
            $script:ConnectLogSyncOffset = $off + $take
            Write-ConnectLogSyncWatermark -Offset $script:ConnectLogSyncOffset -LogPath $script:ConnectLogPath
            $script:ConnectLogLinesSinceSync = 0
            $script:LastConnectLogSyncOk = $true
            $script:ConnectLogSyncFailLogged = $false
            # If more remains, schedule another batch soon (next INFO/WARN).
            if ($script:ConnectLogSyncOffset -lt $all.Length) {
                $script:ConnectLogLinesSinceSync = 25
            }
        } elseif (-not $script:ConnectLogSyncFailLogged) {'''

if old_sync_body not in ui:
    raise SystemExit('Sync body pattern not found')
ui = ui.replace(old_sync_body, new_sync_body, 1)

# TRACE/DEBUG: avoid AutoFlush syscall every line — flush on timer
old_write = r'''    if (-not (Ensure-ConnectLogWriter)) { return }
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = if ($script:ConnectSessionId) { $script:ConnectSessionId } else { '-' }
        $script:ConnectLogWriter.WriteLine("[$ts] [$Level] [$sid] $Message")
        # Local always complete. Sync carefully:
        # - TRACE/DEBUG stay local-only during hot loops (were causing False spam + multi-minute stalls)
        # - WARN/ERROR flush now; INFO every 25 lines
        if ($Level -eq 'TRACE' -or $Level -eq 'DEBUG') { return }'''

new_write = r'''    if (-not (Ensure-ConnectLogWriter)) { return }
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = if ($script:ConnectSessionId) { $script:ConnectSessionId } else { '-' }
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
            return
        }
        $script:ConnectLogWriter.AutoFlush = $true
        $script:ConnectLogWriter.WriteLine("[$ts] [$Level] [$sid] $Message")
        # Local always complete. Sync carefully:
        # - TRACE/DEBUG stay local-only during hot loops (were causing False spam + multi-minute stalls)
        # - WARN/ERROR flush now; INFO every 25 lines'''

if old_write not in ui:
    raise SystemExit('Write-ConnectLog pattern not found')
ui = ui.replace(old_write, new_write, 1)

(root / 'scripts/client/connect-ui.ps1').write_text(ui, encoding='utf-8', newline='\n')
print('patched connect-ui.ps1')

# ---- connect-update.ps1: fix ship block ----
upd = (root / 'scripts/client/windows/connect-update.ps1').read_text(encoding='utf-8')

# BOM-less Write-UpdateFileLog
old_wuf = r'''function Write-UpdateFileLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        Add-Content -LiteralPath (Get-UpdateLogPath) -Value "[$ts] [$Level] UPDATE: $Message" -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}'''
new_wuf = r'''function Write-UpdateFileLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $line = "[$ts] [$Level] UPDATE: $Message`n"
        [System.IO.File]::AppendAllText((Get-UpdateLogPath), $line, [System.Text.UTF8Encoding]::new($false))
    } catch { }
}'''
if old_wuf not in upd:
    raise SystemExit('Write-UpdateFileLog not found')
upd = upd.replace(old_wuf, new_wuf, 1)

old_ship = r'''Write-UpdateFileLog "applied_ok need_relaunch exit=2"
    # best-effort: ship UPDATE lines to server now (same durable log path)
    try {
        $dayLog = Get-UpdateLogPath
        $cfg = Join-Path $env:USERPROFILE '.config\claude-connect\connect.conf'
        $ru=''; $sip=''
        if (Test-Path $cfg) {
            Get-Content $cfg | ForEach-Object {
                if ($_ -match '^REMOTE_USER=(.+)$') { $ru=$Matches[1].Trim() }
            }
        }
        if (Get-Command Get-LocalServerIp -ErrorAction SilentlyContinue) { $sip = Get-LocalServerIp }
        if ($ru -and $sip -and (Test-Path $dayLog)) {
            $t = "{0}@{1}" -f $ru,$sip
            $remoteDay = ".claude/logs/connect-$(Get-Date -Format yyyyMMdd).log"
            ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlMaster=no $t 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs"' 2>$null | Out-Null
            scp -o BatchMode=yes -o ConnectTimeout=12 -o ControlMaster=no -q $dayLog "${t}:$remoteDay.upload" 2>$null
            if ($LASTEXITCODE -eq 0) {
                ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlMaster=no $t "cat \"\$HOME/$remoteDay.upload\" >> \"\$HOME/$remoteDay\"; rm -f \"\$HOME/$remoteDay.upload\"; chmod 600 \"\$HOME/$remoteDay\"" 2>$null | Out-Null
                Write-UpdateFileLog "shipped_day_log_to_server target=$t"
            }
        }
    } catch { }
    exit 2'''

new_ship = r'''Write-UpdateFileLog "applied_ok need_relaunch exit=2"
    # best-effort: ship ONLY unsynced bytes (same .sync-offset watermark as connect-ui)
    try {
        $dayLog = Get-UpdateLogPath
        $cfg = Join-Path $env:USERPROFILE '.config\claude-connect\connect.conf'
        $ru=''; $sip=''
        if (Test-Path $cfg) {
            Get-Content $cfg | ForEach-Object {
                if ($_ -match '^REMOTE_USER=(.+)$') { $ru=$Matches[1].Trim() }
            }
        }
        if (Get-Command Get-LocalServerIp -ErrorAction SilentlyContinue) { $sip = Get-LocalServerIp }
        if ($ru -and $sip -and (Test-Path $dayLog)) {
            $t = "{0}@{1}" -f $ru,$sip
            $wmPath = $dayLog + '.sync-offset'
            $off = 0
            if (Test-Path -LiteralPath $wmPath) {
                $raw = ((Get-Content -LiteralPath $wmPath -Raw -ErrorAction SilentlyContinue) + '').Trim()
                [void][int]::TryParse($raw, [ref]$off)
                if ($off -lt 0) { $off = 0 }
            }
            $all = [System.IO.File]::ReadAllBytes($dayLog)
            if ($off -gt $all.Length) { $off = 0 }
            if ($off -lt $all.Length) {
                $take = [Math]::Min(512KB, $all.Length - $off)
                $chunk = New-Object byte[] $take
                [Array]::Copy($all, $off, $chunk, 0, $take)
                $tmpLocal = Join-Path $env:TEMP ("claude-upd-chunk-{0}.log" -f $PID)
                [System.IO.File]::WriteAllBytes($tmpLocal, $chunk)
                $day = Get-Date -Format 'yyyyMMdd'
                $remoteTmp = ".claude/logs/.connect-upd-$PID.tmp"
                $remoteDay = ".claude/logs/connect-$day.log"
                $mk = 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; true'
                $sshOpts = $script:SshCommonOpts + @($t, $mk)
                $rMk = Invoke-SshTimed -ArgumentList $sshOpts -TimeoutMs 12000
                if ($rMk.Ok) {
                    $scpArgs = @('-o','BatchMode=yes','-o','ConnectTimeout=12','-o','ControlMaster=no','-q', $tmpLocal, "${t}:$remoteTmp")
                    $rScp = Invoke-SshTimed -Exe 'scp' -ArgumentList $scpArgs -TimeoutMs 20000
                    if ($rScp.Ok) {
                        # Keep $HOME literal for remote bash (never expand in PowerShell).
                        $cat = 'cat "$HOME/' + $remoteTmp + '" >> "$HOME/' + $remoteDay + '"; rm -f "$HOME/' + $remoteTmp + '"; chmod 600 "$HOME/' + $remoteDay + '"; true'
                        $rCat = Invoke-SshTimed -ArgumentList ($script:SshCommonOpts + @($t, $cat)) -TimeoutMs 12000
                        if ($rCat.Ok) {
                            $newOff = $off + $take
                            Set-Content -LiteralPath $wmPath -Value "$newOff" -Encoding ASCII -NoNewline -ErrorAction SilentlyContinue
                            Write-UpdateFileLog ("shipped_day_log_to_server target=$t bytes=$take offset=$newOff")
                        } else {
                            Write-UpdateFileLog 'SHIP_FAIL cat' 'WARN'
                        }
                    } else {
                        Write-UpdateFileLog 'SHIP_FAIL scp' 'WARN'
                    }
                } else {
                    Write-UpdateFileLog 'SHIP_FAIL mkdir' 'WARN'
                }
                Remove-Item -LiteralPath $tmpLocal -Force -ErrorAction SilentlyContinue
            } else {
                Write-UpdateFileLog 'ship_skip already_synced'
            }
        }
    } catch {
        Write-UpdateFileLog ("SHIP_FAIL ex=" + $_.Exception.Message) 'WARN'
    }
    exit 2'''

if old_ship not in upd:
    raise SystemExit('ship block not found')
upd = upd.replace(old_ship, new_ship, 1)
(root / 'scripts/client/windows/connect-update.ps1').write_text(upd, encoding='utf-8', newline='\n')
print('patched connect-update.ps1')

# bump version .15 -> .16
ver_path = root / 'scripts/client/windows/connect-version.txt'
ver = ver_path.read_text(encoding='utf-8').strip()
if ver != '20260719.15':
    print('WARN unexpected ver', ver)
new_ver = '20260719.16'
ver_path.write_text(new_ver + '\n', encoding='utf-8')
cp = root / 'scripts/client/windows/connect.ps1'
cpt = cp.read_text(encoding='utf-8')
cpt2, n = re.subn(r"\$script:ConnectVersion = '20260719\.15'", f"$script:ConnectVersion = '{new_ver}'", cpt, count=1)
if n != 1:
    raise SystemExit(f'ConnectVersion bump failed n={n}')
cp.write_text(cpt2, encoding='utf-8', newline='\n')
mac_ver = root / 'scripts/client/mac/connect-version.txt'
if mac_ver.exists():
    mac_ver.write_text(new_ver + '\n', encoding='utf-8')
print('bumped to', new_ver)
print('DONE')
