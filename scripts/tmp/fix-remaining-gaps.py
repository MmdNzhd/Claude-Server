# -*- coding: utf-8 -*-
from pathlib import Path
import re

root = Path('.')  # run from repo root on laptop via laptop-exec

def must_replace(path: Path, old: str, new: str, label: str):
    text = path.read_text(encoding='utf-8')
    if old not in text:
        # already applied?
        if new in text or new.strip() in text:
            print(f'SKIP already: {label}')
            return False
        raise SystemExit(f'MISS needle for {label} in {path}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
    print(f'OK {label}')
    return True

# --- 1) mutex fail-closed ---
ui = root / 'scripts/client/connect-ui.ps1'
must_replace(ui, """    } catch {
        $script:ConnectInstanceMutex = $null
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("SINGLE_INSTANCE: mutex error (continue): {0}" -f $_.Exception.Message) 'WARN'
        }
        return $true
    }
}""", """    } catch {
        $script:ConnectInstanceMutex = $null
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("SINGLE_INSTANCE: mutex error (block): {0}" -f $_.Exception.Message) 'ERROR'
        }
        Write-Host ''
        Write-Host '  [X] Could not acquire Connect lock - close other Claude Connect windows.' -ForegroundColor Red
        Write-Host ''
        return $false
    }
}""", 'mutex fail-closed')

# --- 2) Read-ConnectPrompt return coerced string ---
must_replace(ui, """    Write-ConnectLog ("{0}: prompt={1} answer={2}" -f $Tag, ($Prompt -replace '\\s+', ' ').Trim(), $safe)
    return $val
}""", """    Write-ConnectLog ("{0}: prompt={1} answer={2}" -f $Tag, ($Prompt -replace '\\s+', ' ').Trim(), $safe)
    return $shown
}""", 'Read-ConnectPrompt return shown')

# proxy Trim harden if present
ui_text = ui.read_text(encoding='utf-8')
old_proxy = "return ($s -split ';' | Select-Object -First 1).Trim()"
new_proxy = "return ([string](($s -split ';' | Select-Object -First 1) + '')).Trim()"
if old_proxy in ui_text:
    ui.write_text(ui_text.replace(old_proxy, new_proxy, 1), encoding='utf-8', newline='\n')
    print('OK proxy Trim harden')
else:
    print('SKIP proxy Trim (pattern absent or already)')

# --- 3) pushLine Trim ---
gm = root / 'scripts/client/git-mode.ps1'
must_replace(gm,
"""    $pushLine = (($pushOut | Where-Object { $_ -match 'PUSH_CONF_RESULT' } | Select-Object -Last 1) -replace '\\s+', ' ').Trim()
    $hasResult = [bool]($pushLine -and $pushLine -match 'PUSH_CONF_RESULT')
    if (-not $pushLine) { $pushLine = '(no result line)' }""",
"""    $pushRaw = ($pushOut | Where-Object { $_ -match 'PUSH_CONF_RESULT' } | Select-Object -Last 1)
    $pushLine = if ($null -eq $pushRaw -or "$pushRaw" -eq '') { '(no result line)' } else { ([string]$pushRaw -replace '\\s+', ' ').Trim() }
    if (-not $pushLine) { $pushLine = '(no result line)' }
    $hasResult = [bool]($pushLine -match 'PUSH_CONF_RESULT')""",
'pushLine null-safe Trim')

# --- 4) pubB windows connect.ps1 ---
cp = root / 'scripts/client/windows/connect.ps1'
must_replace(cp,
"""$pubB = ($lines | Where-Object { $_ -match '^ssh-' } | Select-Object -First 1).Trim()""",
"""$pubB = ([string](($lines | Where-Object { $_ -match '^ssh-' } | Select-Object -First 1) + '')).Trim()""",
'pubB windows Trim')

# designer if same pattern
des = root / 'scripts/client/users/designer/connect.ps1'
if des.exists():
    dt = des.read_text(encoding='utf-8')
    old = "$pubB = ($lines | Where-Object { $_ -match '^ssh-' } | Select-Object -First 1).Trim()"
    new = "$pubB = ([string](($lines | Where-Object { $_ -match '^ssh-' } | Select-Object -First 1) + '')).Trim()"
    if old in dt:
        des.write_text(dt.replace(old, new, 1), encoding='utf-8', newline='\n')
        print('OK pubB designer Trim')
    else:
        print('SKIP designer pubB')

# --- 5) connect.bat early mutex before start connect.ps1 ---
bat = root / 'scripts/client/windows/connect.bat'
bt = bat.read_text(encoding='utf-8')
marker = 'REM Hand off to connect.ps1 in its own window; close bootstrap cmd so update text does not hang.\r\nstart "" /D "%HERE%" powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%connect.ps1" %*\r\nexit /b 0'
# try LF only
marker_lf = marker.replace('\r\n', '\n')
insert = '''REM Early single-instance gate: avoid spawning a second connect.ps1 window.
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $m=New-Object System.Threading.Mutex($false,'Global\\ClaudeConnect'); if(-not $m.WaitOne(0)){ Write-Host ''; Write-Host '  [i] Claude Connect is already running - use the existing window.' -ForegroundColor Yellow; Write-Host ''; exit 3 }; $m.ReleaseMutex()|Out-Null; $m.Dispose() } catch { }" 2>nul
if errorlevel 3 (
    exit /b 0
)

REM Hand off to connect.ps1 in its own window; close bootstrap cmd so update text does not hang.
start "" /D "%HERE%" powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%connect.ps1" %*
exit /b 0
'''
if 'Early single-instance gate' in bt:
    print('SKIP bat early mutex already')
elif marker in bt:
    bat.write_text(bt.replace(marker, insert.replace('\n', '\r\n')), encoding='utf-8', newline='')
    print('OK bat early mutex CRLF')
elif marker_lf in bt:
    bat.write_text(bt.replace(marker_lf, insert), encoding='utf-8', newline='\n')
    print('OK bat early mutex LF')
else:
    # softer match
    old_tail = 'start "" /D "%HERE%" powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%connect.ps1" %*\nexit /b 0'
    old_tail_cr = old_tail.replace('\n', '\r\n')
    if old_tail_cr in bt and 'Early single-instance' not in bt:
        new_tail = insert
        bat.write_text(bt.replace(old_tail_cr, new_tail.replace('\n', '\r\n')), encoding='utf-8', newline='')
        print('OK bat early mutex soft CRLF')
    elif old_tail in bt and 'Early single-instance' not in bt:
        bat.write_text(bt.replace(old_tail, insert), encoding='utf-8', newline='\n')
        print('OK bat early mutex soft LF')
    else:
        raise SystemExit('MISS bat handoff tail')

# --- 6) bump version 20260720.20 -> 20260720.21 ---
ver = '20260720.21'
for p in [
    root / 'scripts/client/windows/connect-version.txt',
    root / 'scripts/client/mac/connect-version.txt',
]:
    if p.exists():
        p.write_text(ver + '\n', encoding='utf-8', newline='\n')
        print(f'OK version file {p}')

# connect.ps1 ConnectVersion
for p in [root / 'scripts/client/windows/connect.ps1', root / 'scripts/client/mac/connect.sh']:
    if not p.exists():
        continue
    t = p.read_text(encoding='utf-8')
    t2 = re.sub(r"20260720\.20", ver, t)
    if t2 != t:
        p.write_text(t2, encoding='utf-8', newline='\n')
        print(f'OK version bump in {p.name}')
    else:
        # try .8 leftover
        t2 = re.sub(r"ConnectVersion = '20260720\.\d+'", f"ConnectVersion = '{ver}'", t, count=1)
        if t2 != t:
            p.write_text(t2, encoding='utf-8', newline='\n')
            print(f'OK version regex bump in {p.name}')
        else:
            print(f'SKIP version in {p.name}')

# mac connect-version already done; bump CONNECT_VERSION in sh if present
sh = root / 'scripts/client/mac/connect.sh'
if sh.exists():
    t = sh.read_text(encoding='utf-8')
    t2 = re.sub(r'CONNECT_VERSION=20260720\.\d+', f'CONNECT_VERSION={ver}', t)
    if t2 != t:
        sh.write_text(t2, encoding='utf-8', newline='\n')
        print('OK mac CONNECT_VERSION')

print('DONE')
