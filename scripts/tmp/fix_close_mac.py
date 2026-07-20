# -*- coding: utf-8 -*-
from pathlib import Path

ui_path = Path(r'D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1')
ui = ui_path.read_text(encoding='utf-8')
broken = '''function Close-ConnectLog {
    if (-not $script:ConnectLogWriter) {
        if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null
    Exit-ConnectSingleInstance }
        return
    }
    try {
        if (Get-Command Write-ConnectSessionContext -ErrorAction SilentlyContinue) {
            Write-ConnectSessionContext -Phase 'session_end'
        }
        Write-ConnectLog '======== session end ========'
        $script:ConnectLogWriter.Flush()
        $script:ConnectLogWriter.Dispose()
    } catch { }
    $script:ConnectLogWriter = $null
    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null }
    # Keep durable local day log so offline / failed-SSH sessions remain auditable.
    $script:ConnectLogPath = ''
    $script:ConnectLogSyncOffset = 0
}'''

fixed = '''function Close-ConnectLog {
    if (-not $script:ConnectLogWriter) {
        if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null }
        Exit-ConnectSingleInstance
        return
    }
    try {
        if (Get-Command Write-ConnectSessionContext -ErrorAction SilentlyContinue) {
            Write-ConnectSessionContext -Phase 'session_end'
        }
        Write-ConnectLog '======== session end ========'
        $script:ConnectLogWriter.Flush()
        $script:ConnectLogWriter.Dispose()
    } catch { }
    $script:ConnectLogWriter = $null
    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null }
    # Keep durable local day log so offline / failed-SSH sessions remain auditable.
    $script:ConnectLogPath = ''
    $script:ConnectLogSyncOffset = 0
    Exit-ConnectSingleInstance
}'''

if broken not in ui:
    # try find Close-ConnectLog anyway
    c0 = ui.find('function Close-ConnectLog')
    c1 = ui.find('\nfunction ', c0+10)
    print('CURRENT CLOSE:')
    print(repr(ui[c0:c1][:500]))
    raise SystemExit('broken block mismatch')
ui = ui.replace(broken, fixed, 1)
ui_path.write_text(ui, encoding='utf-8', newline='\n')
print('Close-ConnectLog fixed')

# Mac connect.sh after init_connect_log
csh = Path(r'D:\Smart\Claude-Code-Server\scripts\client\mac\connect.sh')
t = csh.read_text(encoding='utf-8')
old = 'init_connect_log "$SCRIPT_DIR" "$CONNECT_VERSION"\n'
new = '''init_connect_log "$SCRIPT_DIR" "$CONNECT_VERSION"
if declare -F enter_connect_single_instance >/dev/null 2>&1; then
  if ! enter_connect_single_instance; then
    exit 2
  fi
fi
'''
if 'enter_connect_single_instance' not in t[t.find('init_connect_log'):t.find('init_connect_log')+400]:
    if old not in t:
        raise SystemExit('mac init site missing')
    t = t.replace(old, new, 1)
    csh.write_text(t, encoding='utf-8', newline='\n')
    print('mac connect.sh wired')
else:
    print('mac already wired')

# ensure exit on cleanup_session if exists
if 'exit_connect_single_instance' in t and 'cleanup' in t.lower():
    # add to trap cleanup if not present
    if 'exit_connect_single_instance' not in Path(r'D:\Smart\Claude-Code-Server\scripts\client\mac\connect.sh').read_text(encoding='utf-8'):
        pass
t2 = csh.read_text(encoding='utf-8')
# find cleanup_session function and inject
import re
m = re.search(r'cleanup_session\(\)\s*\{', t2)
if m and 'exit_connect_single_instance' not in t2[m.start():m.start()+500]:
    insert_at = m.end()
    t2 = t2[:insert_at] + '\n  if declare -F exit_connect_single_instance >/dev/null 2>&1; then exit_connect_single_instance; fi\n' + t2[insert_at:]
    csh.write_text(t2, encoding='utf-8', newline='\n')
    print('mac cleanup wired')
else:
    print('mac cleanup skip or already')
