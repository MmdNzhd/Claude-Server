from pathlib import Path
import re

p = Path('scripts/client/mac/connect-update.sh')
c = p.read_text(encoding='utf-8')
old_mac = '''    WIN_DIR="$ROOT_DIR/windows"
    [ -d "$WIN_DIR" ] || WIN_DIR="$ROOT_DIR"
'''
new_mac = '''    WIN_DIR="$ROOT_DIR/windows"
    [ -d "$WIN_DIR" ] || WIN_DIR="$ROOT_DIR"
    # Flat layout: never nest BAK under WIN_DIR (subdirectory mv bug).
    if [ "$WIN_DIR" = "$ROOT_DIR" ]; then
      _ext="${TMPDIR:-/tmp}/claude-client-update-$$"
      NEW_ROOT="$_ext/new"
      BAK_ROOT="$_ext/bak"
      mkdir -p "$NEW_ROOT/windows" "$NEW_ROOT/mac" "$BAK_ROOT" 2>/dev/null || true
      _day="$HOME/.config/claude-connect/logs/connect-$(date +%Y%m%d).log"
      mkdir -p "$(dirname "$_day")" 2>/dev/null || true
      printf '[%s] [INFO] [%s] UPDATE: flat_layout staging_ext=%s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${CLAUDE_CONNECT_RUN_ID:--}" "$_ext" >> "$_day" 2>/dev/null || true
    fi
'''
if old_mac not in c:
    raise SystemExit('mac block not found repr=' + repr(c[c.find('WIN_DIR'):c.find('WIN_DIR')+120]))
c = c.replace(old_mac, new_mac, 1)
p.write_text(c, encoding='utf-8', newline='\n')
print('OK mac')

p = Path('scripts/client/windows/connect.bat')
c = p.read_text(encoding='utf-8')
if 'FAIL OUTDATED_SCRIPTS' not in c:
    old = '''if "%OUTDATED%"=="1" (
    echo.
    echo  [X] OUTDATED scripts in this folder.
'''
    new = '''if "%OUTDATED%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\\claude-connect\\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $here='%HERE%'; $line=('[{0}] [ERROR] [{1}] FAIL OUTDATED_SCRIPTS: folder incomplete or mismatched version here={2}' -f $ts, $sid, $here); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
    echo.
    echo  [X] OUTDATED scripts in this folder.
'''
    if old not in c:
        raise SystemExit('bat outdated not found')
    c = c.replace(old, new, 1)
    p.write_text(c, encoding='utf-8', newline='\r\n')
    print('OK bat')
else:
    print('bat already')

# hard suite F
p = Path('scripts/client/tests/test-hard-multi-agent-regressions.ps1')
c = p.read_text(encoding='utf-8')
if 'flat_layout staging_ext' not in c:
    insert = r'''
Write-Host '--- F) Update swap must not nest bak under live (flat layout) ---' -ForegroundColor Cyan
Assert ($upd -match 'flat_layout staging_ext') 'connect-update.ps1 guards flat Desktop layout bak outside live'
Assert ($upd -match 'windowsDir -eq \$packageRoot') 'connect-update.ps1 detects windowsDir -eq packageRoot'
$macUpd = Get-Content (Join-Path $Client 'mac\connect-update.sh') -Raw
Assert ($macUpd -match 'flat_layout') 'mac connect-update.sh guards flat layout bak outside live'
Assert ($bat -match 'FAIL OUTDATED_SCRIPTS') 'connect.bat logs FAIL OUTDATED_SCRIPTS'

'''
    marker = "Write-Host ''\nWrite-Host (\"Hard regressions:"
    if marker not in c:
        raise SystemExit('hard marker not found')
    c = c.replace(marker, insert + marker, 1)
    p.write_text(c, encoding='utf-8', newline='\n')
    print('OK hard F')
else:
    print('hard F already')

ver = '20260720.4'
for rel, pat, rep in [
    ('scripts/client/windows/connect.ps1', r"ConnectVersion = '\d{8}\.\d+'", f"ConnectVersion = '{ver}'"),
    ('scripts/client/mac/connect.sh', r"CONNECT_VERSION='\d{8}\.\d+'", f"CONNECT_VERSION='{ver}'"),
]:
    pp = Path(rel)
    t = pp.read_text(encoding='utf-8')
    t2, n = re.subn(pat, rep, t, count=1)
    if n != 1:
        raise SystemExit(f'ver {rel} n={n}')
    pp.write_text(t2, encoding='utf-8', newline='\n')
for vp in [Path('scripts/client/windows/connect-version.txt'), Path('scripts/client/mac/connect-version.txt')]:
    vp.write_text(ver + '\n', encoding='utf-8')
print('OK', ver)

Path('scripts/tmp/SCOREBOARD-HARD-HONEST.md').write_text('''# HARD testing — honest postmortem (2026-07-20)

## What user asked
Hard multi-agent tests so shipped bugs do not reach them.

## What HARD10 actually did
- Mostly source-grep contracts + mid-race agent reports marked STALE
- Parent scoreboard said CODE READY while single-instance mutex, call-before-define, weak FAIL logging, and flat swap remained

## Bugs that hit the user (proof HARD10 was insufficient)
1. Single-instance block
2. Ensure-ConnectRunId CommandNotFound
3. Failures not greppable as FAIL in day log
4. UPDATE swap_fail subdirectory on flat/temp layouts

## Gate now
- `test-hard-multi-agent-regressions.ps1` (wired in run-all.ps1)
- Parallel gap reports under scripts/tmp/HARD-GAP-*.md
- Do not claim HARD PASS / CODE READY without this suite green
''', encoding='utf-8')
print('DONE')
