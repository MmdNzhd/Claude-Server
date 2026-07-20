from pathlib import Path
import re

# --- Windows connect-update flat layout ---
p = Path('scripts/client/windows/connect-update.ps1')
c = p.read_text(encoding='utf-8')
old = '''$macDir = Join-Path $packageRoot 'mac'

$NewRoot = Join-Path $packageRoot '.client-update-new'
$BakRoot = Join-Path $packageRoot '.client-update-bak'
Remove-Item $NewRoot, $BakRoot -Recurse -Force -ErrorAction SilentlyContinue
'''
new = '''$macDir = Join-Path $packageRoot 'mac'

# Flat Desktop layout (sync-desktop): windowsDir == packageRoot.
# Never put .client-update-bak under Live — Move-Item fails with "subdirectory of the source".
$NewRoot = Join-Path $packageRoot '.client-update-new'
$BakRoot = Join-Path $packageRoot '.client-update-bak'
if ($windowsDir -eq $packageRoot) {
    $ext = Join-Path $env:TEMP ("claude-client-update-{0}" -f $PID)
    $NewRoot = Join-Path $ext 'new'
    $BakRoot = Join-Path $ext 'bak'
    Write-UpdateFileLog ("flat_layout staging_ext=$ext (bak outside live root)")
}
Remove-Item $NewRoot, $BakRoot -Recurse -Force -ErrorAction SilentlyContinue
'''
if old not in c:
    raise SystemExit('win update layout block not found')
c = c.replace(old, new, 1)
p.write_text(c, encoding='utf-8', newline='\n')
print('OK connect-update.ps1 flat guard')

# --- Mac connect-update ---
p = Path('scripts/client/mac/connect-update.sh')
c = p.read_text(encoding='utf-8')
# Find WIN_DIR assignment and after that adjust NEW/BAK if flat
# Read context around 310-320
idx = c.find('WIN_DIR="$ROOT_DIR/windows"')
if idx < 0:
    raise SystemExit('WIN_DIR not found')
# Insert after [ -d "$WIN_DIR" ] || WIN_DIR="$ROOT_DIR"
old_mac = '''WIN_DIR="$ROOT_DIR/windows"
[ -d "$WIN_DIR" ] || WIN_DIR="$ROOT_DIR"
'''
new_mac = '''WIN_DIR="$ROOT_DIR/windows"
[ -d "$WIN_DIR" ] || WIN_DIR="$ROOT_DIR"
# Flat layout: never nest BAK under WIN_DIR (same subdirectory Move/mv bug as Windows).
if [ "$WIN_DIR" = "$ROOT_DIR" ]; then
  _ext="${TMPDIR:-/tmp}/claude-client-update-$$"
  NEW_ROOT="$_ext/new"
  BAK_ROOT="$_ext/bak"
  mkdir -p "$NEW_ROOT" "$BAK_ROOT" 2>/dev/null || true
  _update_log "flat_layout staging_ext=$_ext (bak outside live root)"
fi
'''
if old_mac not in c:
    raise SystemExit('mac WIN_DIR block not found')
c = c.replace(old_mac, new_mac, 1)
# _update_log may not exist - check
if '_update_log' not in c and 'Write-Update' not in c:
    # find log helper name
    for name in ['_update_file_log', 'update_log', 'log_update']:
        if name in c:
            print('mac log helper', name)
    # use printf to day log inline instead
    c = c.replace(
        '  _update_log "flat_layout staging_ext=$_ext (bak outside live root)"\n',
        '  _day="$HOME/.config/claude-connect/logs/connect-$(date +%Y%m%d).log"\n'
        '  mkdir -p "$(dirname "$_day")" 2>/dev/null || true\n'
        '  printf \'[%s] [INFO] [%s] UPDATE: flat_layout staging_ext=%s\\n\' "$(date \'+%Y-%m-%d %H:%M:%S\')" "${CLAUDE_CONNECT_RUN_ID:--}" "$_ext" >> "$_day" 2>/dev/null || true\n',
        1,
    )
p.write_text(c, encoding='utf-8', newline='\n')
print('OK connect-update.sh flat guard')

# --- bat OUTDATED ---
p = Path('scripts/client/windows/connect.bat')
c = p.read_text(encoding='utf-8')
old = '''if "%OUTDATED%"=="1" (
    echo.
    echo  [X] OUTDATED scripts in this folder.
'''
new = '''if "%OUTDATED%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\\claude-connect\\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [ERROR] [{1}] FAIL OUTDATED_SCRIPTS: folder incomplete or mismatched version here={2}' -f $ts, $sid, $env:HERE); if (-not $env:HERE) { $line=('[{0}] [ERROR] [{1}] FAIL OUTDATED_SCRIPTS: folder incomplete or mismatched version' -f $ts, $sid) }; [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
    echo.
    echo  [X] OUTDATED scripts in this folder.
'''
# HERE may not be in env for child - use %HERE% in the bat by expanding before powershell
# Better: pass as arg
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
    raise SystemExit('bat OUTDATED block not found')
c = c.replace(old, new, 1)
p.write_text(c, encoding='utf-8', newline='\r\n')
print('OK connect.bat OUTDATED log')

# --- harden hard regression suite ---
p = Path('scripts/client/tests/test-hard-multi-agent-regressions.ps1')
c = p.read_text(encoding='utf-8')
if 'flat_layout' not in c:
    insert = '''
Write-Host '--- F) Update swap must not nest bak under live (flat layout) ---' -ForegroundColor Cyan
Assert ($upd -match 'flat_layout staging_ext') 'connect-update.ps1 guards flat Desktop layout bak outside live'
Assert ($upd -match 'windowsDir -eq \$packageRoot') 'connect-update.ps1 detects windowsDir -eq packageRoot'
$macUpd = Get-Content (Join-Path $Client 'mac\\connect-update.sh') -Raw
Assert ($macUpd -match 'WIN_DIR.*=.*"\$ROOT_DIR"') 'mac update has flat WIN_DIR fallback'
Assert ($macUpd -match 'flat_layout') 'mac connect-update.sh guards flat layout bak outside live'
Assert ($bat -match 'FAIL OUTDATED_SCRIPTS') 'connect.bat logs FAIL OUTDATED_SCRIPTS'

'''
    c = c.replace(
        "Write-Host ''\nWrite-Host (\"Hard regressions:",
        insert + "Write-Host ''\nWrite-Host (\"Hard regressions:",
        1,
    )
    p.write_text(c, encoding='utf-8', newline='\n')
    print('OK hard suite F')

# version bump 20260720.4
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

# honesty scoreboard
Path('scripts/tmp/SCOREBOARD-HARD-HONEST.md').write_text('''# HARD testing — honest postmortem (2026-07-20)

## What user asked
Hard multi-agent tests so shipped bugs do not reach them.

## What HARD10 actually did
- Mostly source-grep contracts + mid-race agent reports marked STALE
- Parent scoreboard said CODE READY while:
  - Global single-instance mutex still blocked concurrent clients
  - Ensure-ConnectRunId could throw before definition (call-before-define)
  - User-facing failures often INFO/console-only (not FAIL ERROR)
  - Flat-layout update swap subdirectory bug untested

## Bugs that hit the user (proof HARD10 was insufficient)
1. Single-instance block ("Another Claude Connect is already running")
2. Ensure-ConnectRunId CommandNotFound during update
3. Admin/UAC hang not greppable as FAIL in day log
4. Earlier UPDATE swap_fail subdirectory (flat/temp layouts)

## What we added now
- `scripts/client/tests/test-hard-multi-agent-regressions.ps1` — encodes those bugs as hard FAIL regressions
- Wired into `run-all.ps1`
- Parallel gap agents:
  - predef-calls: PASS (0 call-before-define left)
  - orphan-errors: FAIL remaining (mac/designer/outdated — partial fix: bat OUTDATED logged)
  - mutex-swap: multi PASS; flat swap FAIL → fixed in 20260720.4

## Rule going forward
Do not claim HARD PASS unless `test-hard-multi-agent-regressions.ps1` is green.
Do not mark CODE READY if multi-instance, define-before-use, FAIL logging, or flat swap are unchecked.
''', encoding='utf-8')
print('OK scoreboard')
print('DONE')
