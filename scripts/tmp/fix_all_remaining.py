# -*- coding: utf-8 -*-
"""Close remaining edge gaps for connect logging/perf/stale/lifecycle."""
from pathlib import Path
import re

root = Path(r'D:\Smart\Claude-Code-Server')
ui = (root/'scripts/client/connect-ui.ps1').read_text(encoding='utf-8')
gm = (root/'scripts/client/git-mode.ps1').read_text(encoding='utf-8')
cp = (root/'scripts/client/windows/connect.ps1').read_text(encoding='utf-8')
gsh = (root/'scripts/client/git-mode.sh').read_text(encoding='utf-8')
bat = (root/'scripts/client/windows/connect.bat').read_text(encoding='utf-8', errors='replace')
ush = (root/'scripts/client/connect-ui.sh').read_text(encoding='utf-8')

# ---- 1) PERF default OFF ----
old_perf = '''function Test-ConnectPerfEnabled {
    if ($env:CLAUDE_CONNECT_PERF_LOG -eq '0') { return $false }
    return $true
}'''
new_perf = '''function Test-ConnectPerfEnabled {
    # Default OFF: hot session loop was spamming PERF[cim_query] every 200ms.
    # Opt-in: set CLAUDE_CONNECT_PERF_LOG=1
    if ($env:CLAUDE_CONNECT_PERF_LOG -eq '1') { return $true }
    return $false
}'''
if old_perf not in ui:
    raise SystemExit('Test-ConnectPerfEnabled block missing')
ui = ui.replace(old_perf, new_perf, 1)

# ---- 2) Day rollover in Ensure-ConnectLogWriter ----
old_ensure = '''function Ensure-ConnectLogWriter {
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
}'''
new_ensure = '''function Ensure-ConnectLogWriter {
    $dayPath = Get-ConnectLogDayPath
    # Midnight rollover: switch day file without restart.
    if ($script:ConnectLogWriter -and $script:ConnectLogPath -and ($script:ConnectLogPath -ne $dayPath)) {
        try { $script:ConnectLogWriter.Flush() } catch { }
        try { $script:ConnectLogWriter.Dispose() } catch { }
        $script:ConnectLogWriter = $null
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
}'''
if old_ensure not in ui:
    raise SystemExit('Ensure-ConnectLogWriter block missing')
ui = ui.replace(old_ensure, new_ensure, 1)

# ---- 3) Throttle TUNNEL_SYNC TRACE ----
old_trace = '''        Write-GitModeLog "TUNNEL_SYNC: bg_alive pid=$($BgTunnel.Value.Id) port=$Port" 'TRACE'
        return $true'''
new_trace = '''        # Throttle TRACE: was every ~200ms and flooded the day log.
        $nowTs = Get-Date
        if (-not $script:LastTunnelSyncTraceAt -or ($nowTs - $script:LastTunnelSyncTraceAt).TotalSeconds -ge 30) {
            Write-GitModeLog "TUNNEL_SYNC: bg_alive pid=$($BgTunnel.Value.Id) port=$Port" 'TRACE'
            $script:LastTunnelSyncTraceAt = $nowTs
        }
        return $true'''
if old_trace not in gm:
    raise SystemExit('TUNNEL_SYNC bg_alive TRACE missing')
gm = gm.replace(old_trace, new_trace, 1)

# ---- 4) Faster STALE wait Windows: 8*500ms -> 4*250ms ----
old_stale = '''    for ($i = 1; $i -le 8; $i++) {
        Start-Sleep -Milliseconds 500
        Clear-TunnelBannerCache
        $savedPort = $Port
        $Port = $TargetPort
        try {
            if (-not (Test-TunnelPortTcpOpen)) {
                Write-GitModeLog "STALE_FORWARD: port released port=$TargetPort wait=$i" 'DEBUG'
                return
            }
        } finally {
            $Port = $savedPort
        }
    }'''
new_stale = '''    # Keep short: long waits were a major "still slow" cost when ports were sticky.
    for ($i = 1; $i -le 4; $i++) {
        Start-Sleep -Milliseconds 250
        Clear-TunnelBannerCache
        $savedPort = $Port
        $Port = $TargetPort
        try {
            if (-not (Test-TunnelPortTcpOpen)) {
                Write-GitModeLog "STALE_FORWARD: port released port=$TargetPort wait=$i" 'DEBUG'
                return
            }
        } finally {
            $Port = $savedPort
        }
    }'''
if old_stale not in gm:
    raise SystemExit('STALE wait loop missing')
gm = gm.replace(old_stale, new_stale, 1)

# ---- 5) Session loop: throttle editor CIM checks; sleep 500ms ----
old_loop = '''            while ($true) {
                # Sync is authoritative (reattach + 30s probe with retries). Do NOT call
                # Test-TunnelUp every 200ms A??????,???????? that defeated the probe throttle (false DROP2/3).
                $tunnelSyncOk = [bool](Sync-SessionTunnelProcess -BgTunnel ([ref]$bgTunnel))
                if (-not $tunnelSyncOk) { break }
                if ($EditorCmd -eq 'cursor') {
                    $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $editorOpened = $onFolderNow
                    $editorLabel = if ($onFolderNow) { $EditorName } elseif ($windowOpen) { 'agent' } else { 'closed' }
                } else {
                    $onFolderNow = $editorOpened
                    $editorLabel = ''
                }
                if ((Get-Date) - $lastStatusAt -gt [TimeSpan]::FromSeconds(30)) {
                    Update-SessionStatusLine -ProjectLabel $go.Id -GitLabel (Get-GitModeLabel) -TunnelOk $tunnelSyncOk `
                        -EditorOpen $onFolderNow -EditorName $EditorName -EditorLabel $editorLabel `
                        -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $lastStatusAt = Get-Date
                }
                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    if ($ki.KeyChar.ToString().ToLower() -eq 'r' -or $ki.Key -eq [ConsoleKey]::R) { $action = 'r' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'g' -or $ki.Key -eq [ConsoleKey]::G) { $action = 'g' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'o' -or $ki.Key -eq [ConsoleKey]::O) { $action = 'o' }
                    elseif ($ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }
                    Write-ConnectDecision 'session_key' ("action={0} key={1} keychar={2}" -f $action, $ki.Key, $ki.KeyChar)
                    $gotKey = $true
                    break
                }
                Start-Sleep -Milliseconds 200
            }'''

# The mojibake comment might not match - use flexible replace via regex
pat_loop = re.compile(
    r'while \(\$true\) \{\n'
    r'\s+# Sync is authoritative.*?\n'
    r'\s+# Test-TunnelUp every 200ms.*?\n'
    r'\s+\$tunnelSyncOk = \[bool\]\(Sync-SessionTunnelProcess -BgTunnel \(\[ref\]\$bgTunnel\)\)\n'
    r'(.*?)\n'
    r'\s+Start-Sleep -Milliseconds 200\n'
    r'\s+\}',
    re.S)

new_loop = '''            $lastEditorCheckAt = [DateTime]::MinValue
            $onFolderNow = $editorOpened
            $editorLabel = if ($editorOpened) { $EditorName } else { 'closed' }
            while ($true) {
                # Sync is authoritative (reattach + probe). Do NOT call Test-TunnelUp every tick.
                $tunnelSyncOk = [bool](Sync-SessionTunnelProcess -BgTunnel ([ref]$bgTunnel))
                if (-not $tunnelSyncOk) { break }
                # Editor CIM queries are expensive — at most every 2s (was every 200ms).
                if ($EditorCmd -eq 'cursor' -and ((Get-Date) - $lastEditorCheckAt -gt [TimeSpan]::FromSeconds(2))) {
                    $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $editorOpened = $onFolderNow
                    $editorLabel = if ($onFolderNow) { $EditorName } elseif ($windowOpen) { 'agent' } else { 'closed' }
                    $lastEditorCheckAt = Get-Date
                } elseif ($EditorCmd -ne 'cursor') {
                    $onFolderNow = $editorOpened
                    $editorLabel = ''
                }
                if ((Get-Date) - $lastStatusAt -gt [TimeSpan]::FromSeconds(30)) {
                    Update-SessionStatusLine -ProjectLabel $go.Id -GitLabel (Get-GitModeLabel) -TunnelOk $tunnelSyncOk `
                        -EditorOpen $onFolderNow -EditorName $EditorName -EditorLabel $editorLabel `
                        -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $lastStatusAt = Get-Date
                }
                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    if ($ki.KeyChar.ToString().ToLower() -eq 'r' -or $ki.Key -eq [ConsoleKey]::R) { $action = 'r' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'g' -or $ki.Key -eq [ConsoleKey]::G) { $action = 'g' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'o' -or $ki.Key -eq [ConsoleKey]::O) { $action = 'o' }
                    elseif ($ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }
                    Write-ConnectDecision 'session_key' ("action={0} key={1} keychar={2}" -f $action, $ki.Key, $ki.KeyChar)
                    $gotKey = $true
                    break
                }
                Start-Sleep -Milliseconds 500
            }'''

m = pat_loop.search(cp)
if not m:
    # try without the weird comment lines
    pat2 = re.compile(
        r'\$tunnelSyncOk = \[bool\]\(Sync-SessionTunnelProcess -BgTunnel \(\[ref\]\$bgTunnel\)\)\n'
        r'                if \(-not \$tunnelSyncOk\) \{ break \}\n'
        r'                if \(\$EditorCmd -eq \'cursor\'\) \{.*?'
        r'Start-Sleep -Milliseconds 200\n'
        r'            \}',
        re.S)
    m2 = pat2.search(cp)
    if not m2:
        raise SystemExit('session loop pattern not found')
    # expand to include while ($true) {
    start = cp.rfind('while ($true) {', 0, m2.start())
    cp = cp[:start] + new_loop + cp[m2.end():]
else:
    cp = cp[:m.start()] + new_loop + cp[m.end():]

# ---- 6) Mac stale wait: seq 1 12 sleep 0.5 -> seq 1 4 sleep 0.25 ----
gsh2 = gsh
# replace both occurrences of for i in $(seq 1 12); do ... sleep 0.5 in stale context
gsh2 = gsh2.replace('for i in $(seq 1 12); do', 'for i in $(seq 1 4); do', 2)
# only change sleep 0.5 near stale if present after our seq change - careful global
# Change sleep 0.5 in clear_stale functions - count
if gsh2.count('sleep 0.5') >= 1:
    # replace first two sleep 0.5 that follow seq 1 4 (stale clears)
    parts = gsh2.split('for i in $(seq 1 4); do')
    if len(parts) >= 3:
        rebuilt = [parts[0]]
        for p in parts[1:]:
            p2 = p.replace('sleep 0.5', 'sleep 0.25', 1)
            rebuilt.append(p2)
        gsh2 = 'for i in $(seq 1 4); do'.join(rebuilt)
gsh = gsh2

# Mac TUNNEL_SYNC TRACE throttle - harder in shell; wrap with time check
old_mac_tr = '''            connect_log "TUNNEL_SYNC: bg_alive pid=$bg_pid port=$PORT" 'TRACE\''''
# there may be multiple - throttle via env timestamp
# Use a simple approach: change TRACE to only every 30s with date +%s
mac_tr_count = gsh.count("TUNNEL_SYNC: bg_alive")
print('mac bg_alive count', mac_tr_count)
# replace all bg_alive TRACE lines with throttled version
throttle_snip = '''            _now=$(date +%s)
            if [ -z "${_LAST_TUNNEL_TRACE:-}" ] || [ $((_now - _LAST_TUNNEL_TRACE)) -ge 30 ]; then
                connect_log "TUNNEL_SYNC: bg_alive pid=$bg_pid port=$PORT" 'TRACE'
                _LAST_TUNNEL_TRACE=$_now
            fi'''
# naive line-by-line
out_lines=[]
for line in gsh.splitlines(True):
    if "TUNNEL_SYNC: bg_alive pid=$bg_pid port=$PORT" in line and 'TRACE' in line:
        indent = line[:len(line)-len(line.lstrip())]
        out_lines.append(indent + '_now=$(date +%s)\n')
        out_lines.append(indent + 'if [ -z "${_LAST_TUNNEL_TRACE:-}" ] || [ $((_now - _LAST_TUNNEL_TRACE)) -ge 30 ]; then\n')
        out_lines.append(indent + '  connect_log "TUNNEL_SYNC: bg_alive pid=$bg_pid port=$PORT" \'TRACE\'\n')
        out_lines.append(indent + '  _LAST_TUNNEL_TRACE=$_now\n')
        out_lines.append(indent + 'fi\n')
    else:
        out_lines.append(line)
gsh = ''.join(out_lines)

# ---- 7) BOOTSTRAP with sid ----
old_boot = """powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\\claude-connect\\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; Add-Content -LiteralPath $f -Value ('[{0}] [INFO] BOOTSTRAP: connect.bat start here={1}' -f $ts, '%HERE%') -Encoding UTF8 } catch {}" 2>nul"""
# bat may have different quote escaping - find BOOTSTRAP line
if 'BOOTSTRAP: connect.bat start' not in bat:
    raise SystemExit('bootstrap line missing')
# replace the Add-Content value format to include sid
bat2 = bat
# Use a simpler unique replace on the Value pattern
bat2 = bat2.replace(
    "('[{0}] [INFO] BOOTSTRAP: connect.bat start here={1}' -f $ts, '%HERE%')",
    "('[{0}] [INFO] [{1}] BOOTSTRAP: connect.bat start here={2}' -f $ts, ([guid]::NewGuid().ToString('N').Substring(0,12)), '%HERE%')"
)
if bat2 == bat:
    # try alternate
    raise SystemExit('bootstrap replace failed')
bat = bat2

# ---- 8) Mac connect_log day rollover hint ----
# In connect_log, refresh CONNECT_LOG_PATH if day changed
old_clog = '''connect_log() {
    local msg="$1" level="${2:-INFO}"
    [ -n "${CONNECT_LOG_PATH:-}" ] || return 0
    printf '[%s] [%s] [%s] %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "${CONNECT_SESSION_ID:--}" "$msg" >> "$CONNECT_LOG_PATH" 2>/dev/null || true'''
new_clog = '''connect_log() {
    local msg="$1" level="${2:-INFO}"
    [ -n "${CONNECT_LOG_PATH:-}" ] || return 0
    # Midnight rollover
    local day_path="$HOME/.config/claude-connect/logs/connect-$(date +%Y%m%d).log"
    if [ "$CONNECT_LOG_PATH" != "$day_path" ]; then
        CONNECT_LOG_PATH="$day_path"
        CONNECT_LOG_SYNC_OFF=0
        CONNECT_LOG_LINES_SINCE_SYNC=0
        mkdir -p "$(dirname "$CONNECT_LOG_PATH")" 2>/dev/null || true
    fi
    printf '[%s] [%s] [%s] %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "${CONNECT_SESSION_ID:--}" "$msg" >> "$CONNECT_LOG_PATH" 2>/dev/null || true'''
if old_clog not in ush:
    raise SystemExit('mac connect_log header missing')
ush = ush.replace(old_clog, new_clog, 1)

# write all
(root/'scripts/client/connect-ui.ps1').write_text(ui, encoding='utf-8', newline='\n')
(root/'scripts/client/git-mode.ps1').write_text(gm, encoding='utf-8', newline='\n')
(root/'scripts/client/windows/connect.ps1').write_text(cp, encoding='utf-8', newline='\n')
(root/'scripts/client/git-mode.sh').write_text(gsh, encoding='utf-8', newline='\n')
(root/'scripts/client/windows/connect.bat').write_text(bat, encoding='utf-8', newline='\r\n')
(root/'scripts/client/connect-ui.sh').write_text(ush, encoding='utf-8', newline='\n')

# bump version manually to .15 then publish will maybe bump again
(root/'scripts/client/windows/connect-version.txt').write_text('20260719.15', encoding='ascii')
cp_final = (root/'scripts/client/windows/connect.ps1').read_text(encoding='utf-8')
cp_final = re.sub(r"\$script:ConnectVersion = '20260719\.\d+'", "$script:ConnectVersion = '20260719.15'", cp_final, count=1)
(root/'scripts/client/windows/connect.ps1').write_text(cp_final, encoding='utf-8', newline='\n')
print('ALL PATCHES APPLIED v20260719.15')
