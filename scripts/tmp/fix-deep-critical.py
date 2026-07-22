# -*- coding: utf-8 -*-
from pathlib import Path
import re

root = Path('.')

def repl(path, old, new, label):
    p = Path(path)
    t = p.read_text(encoding='utf-8')
    if old not in t:
        if 'Enter-ConnectSingleInstance' in t and 'Wait-ConnectExit' in t and '-not (Enter-ConnectSingleInstance)' in t:
            print(f'SKIP already ok: {label}')
            return
        raise SystemExit(f'MISS {label} in {path}')
    p.write_text(t.replace(old, new, 1), encoding='utf-8', newline='\n')
    print(f'OK {label}')

# --- designer connect.ps1 ---
old_des = """if (Get-Command Enter-ConnectSingleInstance -ErrorAction SilentlyContinue) {
    $null = Enter-ConnectSingleInstance
"""
new_des = """if (Get-Command Enter-ConnectSingleInstance -ErrorAction SilentlyContinue) {
    if (-not (Enter-ConnectSingleInstance)) {
        if (Get-Command Wait-ConnectExit -ErrorAction SilentlyContinue) { Wait-ConnectExit -Reason 'single_instance' -Code 2 }
        else { exit 2 }
    }
"""
repl('scripts/client/users/designer/connect.ps1', old_des, new_des, 'designer mutex honor')

# --- connect-design.ps1 ---
old_cd = """    if (Get-Command Enter-ConnectSingleInstance -ErrorAction SilentlyContinue) {
        $null = Enter-ConnectSingleInstance
"""
new_cd = """    if (Get-Command Enter-ConnectSingleInstance -ErrorAction SilentlyContinue) {
        if (-not (Enter-ConnectSingleInstance)) {
            if (Get-Command Wait-ConnectExit -ErrorAction SilentlyContinue) { Wait-ConnectExit -Reason 'single_instance' -Code 2 }
            else { exit 2 }
        }
"""
repl('scripts/client/windows/connect-design.ps1', old_cd, new_cd, 'connect-design mutex honor')

# --- bat: fail-closed catch + keep probe but document; tighten catch to exit 3 ---
bat = Path('scripts/client/windows/connect.bat')
bt = bat.read_text(encoding='utf-8')
old_gate = '''powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $m=New-Object System.Threading.Mutex($false,'Global\\ClaudeConnect'); if(-not $m.WaitOne(0)){ Write-Host ''; Write-Host '  [i] Claude Connect is already running - use the existing window.' -ForegroundColor Yellow; Write-Host ''; exit 3 }; $m.ReleaseMutex()|Out-Null; $m.Dispose() } catch { }" 2>nul
if errorlevel 3 (
    exit /b 0
)'''
new_gate = '''powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $m=New-Object System.Threading.Mutex($false,'Global\\ClaudeConnect'); if(-not $m.WaitOne(0)){ Write-Host ''; Write-Host '  [i] Claude Connect is already running - use the existing window.' -ForegroundColor Yellow; Write-Host ''; exit 3 }; $m.ReleaseMutex()|Out-Null; $m.Dispose(); exit 0 } catch { Write-Host ''; Write-Host '  [X] Could not check Connect lock.' -ForegroundColor Red; Write-Host ''; exit 3 }" 2>nul
if errorlevel 3 (
    exit /b 0
)'''
if 'Could not check Connect lock' in bt:
    print('SKIP bat catch already')
elif old_gate in bt:
    bat.write_text(bt.replace(old_gate, new_gate, 1), encoding='utf-8', newline='\n')
    print('OK bat fail-closed catch')
else:
    # try CRLF
    if old_gate.replace('\n','\r\n') in bt:
        bat.write_text(bt.replace(old_gate.replace('\n','\r\n'), new_gate.replace('\n','\r\n'), 1), encoding='utf-8', newline='')
        print('OK bat fail-closed catch CRLF')
    else:
        print('WARN bat gate pattern miss - show context')
        idx = bt.find('Early single-instance')
        print(repr(bt[idx:idx+450]))

# --- Move mutex before Initialize-ConnectLog in connect.ps1 ---
cp = Path('scripts/client/windows/connect.ps1')
ct = cp.read_text(encoding='utf-8')
old_order = """. $_connectUi
Initialize-ConnectLog -ScriptDir $script:ConnectScriptDir -Version $script:ConnectVersion
if (Get-Command Enter-ConnectSingleInstance -ErrorAction SilentlyContinue) {
    if (-not (Enter-ConnectSingleInstance)) {
        if (Get-Command Wait-ConnectExit -ErrorAction SilentlyContinue) { Wait-ConnectExit -Reason 'single_instance' -Code 2 }
        else { exit 2 }
    }
}"""
new_order = """. $_connectUi
if (Get-Command Enter-ConnectSingleInstance -ErrorAction SilentlyContinue) {
    if (-not (Enter-ConnectSingleInstance)) {
        # Block before session-start log so blocked launches do not pollute day log.
        Write-Host ''
        Write-Host '  [i] Claude Connect is already running - use the existing window.' -ForegroundColor Yellow
        Write-Host ''
        try { Read-Host '    Press Enter to close' | Out-Null } catch { }
        exit 2
    }
}
Initialize-ConnectLog -ScriptDir $script:ConnectScriptDir -Version $script:ConnectVersion"""
if 'Block before session-start log' in ct:
    print('SKIP mutex-before-log already')
elif old_order in ct:
    cp.write_text(ct.replace(old_order, new_order, 1), encoding='utf-8', newline='\n')
    print('OK mutex before Initialize-ConnectLog')
else:
    print('WARN connect.ps1 order pattern miss')
    # show nearby
    m = re.search(r'Initialize-ConnectLog[\s\S]{0,350}Enter-ConnectSingleInstance', ct)
    if m:
        print(repr(m.group(0)[:400]))

# bump version .22 -> .23
ver = '20260720.23'
for p in [Path('scripts/client/windows/connect-version.txt'), Path('scripts/client/mac/connect-version.txt')]:
    p.write_text(ver + '\n', encoding='utf-8', newline='\n')
    print(f'OK {p}')

for p in [Path('scripts/client/windows/connect.ps1'), Path('scripts/client/mac/connect.sh')]:
    t = p.read_text(encoding='utf-8')
    t2 = re.sub(r'20260720\.22', ver, t)
    if t2 != t:
        p.write_text(t2, encoding='utf-8', newline='\n')
        print(f'OK bump {p.name}')

# hard test: designer must honor return
ht = Path('scripts/client/tests/test-hard-multi-agent-regressions.ps1')
h = ht.read_text(encoding='utf-8')
needle = "Assert ($desPs -match 'Enter-ConnectSingleInstance') 'Designer Win: shares main single-instance gate'"
add = """Assert ($desPs -match 'Enter-ConnectSingleInstance') 'Designer Win: shares main single-instance gate'
Assert ($desPs -match '(?s)Enter-ConnectSingleInstance[\\s\\S]{0,200}-not \\(Enter-ConnectSingleInstance\\)') 'Designer Win: honors mutex false (exits)'
Assert ($desPs -notmatch '\\$null = Enter-ConnectSingleInstance') 'Designer Win: must not discard mutex result'
"""
if 'honors mutex false' in h:
    print('SKIP hard designer asserts')
elif needle in h:
    ht.write_text(h.replace(needle, add.rstrip(), 1), encoding='utf-8', newline='\n')
    print('OK hard designer asserts')
else:
    print('WARN hard needle miss')

# p0 version pins to .23
p0 = Path('scripts/client/tests/test-p0-connect-fixes.ps1')
if p0.exists():
    t = p0.read_text(encoding='utf-8')
    t2 = re.sub(r'20260720\.2[12]', ver, t)
    p0.write_text(t2, encoding='utf-8', newline='\n')
    print('OK p0 pins')

print('DONE')
