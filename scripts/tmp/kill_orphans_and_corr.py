# -*- coding: utf-8 -*-
from pathlib import Path
import re

root = Path(r'D:\Smart\Claude-Code-Server')

# --- connect.bat: stable RUN_ID for BOOTSTRAP + child processes ---
bat = root / 'scripts/client/windows/connect.bat'
bt = bat.read_text(encoding='utf-8')
old_boot = '''REM Log double-click immediately (before update) — durable local day log
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\\claude-connect\\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; Add-Content -LiteralPath $f -Value ('[{0}] [INFO] [{1}] BOOTSTRAP: connect.bat start here={2}' -f $ts, ([guid]::NewGuid().ToString('N').Substring(0,12)), '%HERE%') -Encoding UTF8 } catch {}" 2>nul
'''
# Use ASCII hyphen in comment to avoid encoding issues matching
# Match more flexibly
m = re.search(r'REM Log double-click.*?2>nul\r?\n', bt, re.S)
if not m:
    raise SystemExit('bootstrap block not found')
new_boot = (
    'REM Stable run id: correlates BOOTSTRAP / UPDATE / session start in the day log\r\n'
    'if not defined CLAUDE_CONNECT_RUN_ID (\r\n'
    '  for /f %%I in (\'powershell -NoProfile -Command "[guid]::NewGuid().ToString(\'N\').Substring(0,12)"\') do set "CLAUDE_CONNECT_RUN_ID=%%I"\r\n'
    ')\r\n'
    'REM Log double-click immediately (before update) - durable local day log (BOM-less)\r\n'
    'powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE \'.config\\claude-connect\\logs\'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d (\'connect-{0}.log\' -f (Get-Date -Format \'yyyyMMdd\')); $ts=Get-Date -Format \'yyyy-MM-dd HH:mm:ss.fff\'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid=\'-\' }; $line=(\'[{0}] [INFO] [{1}] BOOTSTRAP: connect.bat start here={2}\' -f $ts, $sid, \'%HERE%\'); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul\r\n'
)
bt = bt[:m.start()] + new_boot + bt[m.end():]
bat.write_text(bt, encoding='utf-8', newline='\r\n')
print('patched connect.bat')

# --- connect-ui: reuse RUN_ID as session id ---
ui = root / 'scripts/client/connect-ui.ps1'
ut = ui.read_text(encoding='utf-8')
old = '''    if (-not $script:ConnectSessionId) {
        $script:ConnectSessionId = [guid]::NewGuid().ToString('N').Substring(0, 12)
    }'''
new = '''    if (-not $script:ConnectSessionId) {
        if ($env:CLAUDE_CONNECT_RUN_ID -and $env:CLAUDE_CONNECT_RUN_ID.Trim().Length -ge 8) {
            $script:ConnectSessionId = $env:CLAUDE_CONNECT_RUN_ID.Trim()
        } else {
            $script:ConnectSessionId = [guid]::NewGuid().ToString('N').Substring(0, 12)
        }
    }'''
if old not in ut:
    raise SystemExit('ConnectSessionId block not found')
ut = ut.replace(old, new, 1)
ui.write_text(ut, encoding='utf-8', newline='\n')
print('patched connect-ui.ps1')

# --- connect-update: sid in UPDATE lines ---
upd = root / 'scripts/client/windows/connect-update.ps1'
upt = upd.read_text(encoding='utf-8')
old_w = '''function Write-UpdateFileLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $line = "[$ts] [$Level] UPDATE: $Message`n"
        [System.IO.File]::AppendAllText((Get-UpdateLogPath), $line, [System.Text.UTF8Encoding]::new($false))
    } catch { }
}'''
new_w = '''function Write-UpdateFileLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = if ($env:CLAUDE_CONNECT_RUN_ID) { $env:CLAUDE_CONNECT_RUN_ID.Trim() } else { '-' }
        $line = "[$ts] [$Level] [$sid] UPDATE: $Message`n"
        [System.IO.File]::AppendAllText((Get-UpdateLogPath), $line, [System.Text.UTF8Encoding]::new($false))
    } catch { }
}'''
if old_w not in upt:
    raise SystemExit('Write-UpdateFileLog not found for sid patch')
upt = upt.replace(old_w, new_w, 1)
upd.write_text(upt, encoding='utf-8', newline='\n')
print('patched connect-update.ps1')

# bump .16 -> .17
ver = '20260719.17'
(root / 'scripts/client/windows/connect-version.txt').write_text(ver + '\n', encoding='utf-8')
mac = root / 'scripts/client/mac/connect-version.txt'
if mac.exists():
    mac.write_text(ver + '\n', encoding='utf-8')
cp = root / 'scripts/client/windows/connect.ps1'
cpt = cp.read_text(encoding='utf-8')
cpt2, n = re.subn(r"\$script:ConnectVersion = '20260719\.16'", f"$script:ConnectVersion = '{ver}'", cpt, count=1)
if n != 1:
    raise SystemExit(f'version bump failed n={n}')
cp.write_text(cpt2, encoding='utf-8', newline='\n')
print('bumped', ver)
print('DONE')
