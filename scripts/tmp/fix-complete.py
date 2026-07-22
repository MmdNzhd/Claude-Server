# -*- coding: utf-8 -*-
from pathlib import Path
import re

root = Path('.')
ver = '20260720.25'

# --- connect-boot.ps1 (atomic mutex + launch) ---
boot = r'''#Requires -Version 5.1
# connect-boot.ps1 - acquire Global\ClaudeConnect THEN run connect.ps1 in the same process.
# Closes the bat probe/release TOCTOU (WaitOne + ReleaseMutex before start).
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$mutexName = 'Global\ClaudeConnect'

$created = $false
$m = $null
try {
    $m = New-Object System.Threading.Mutex($false, $mutexName, [ref]$created)
} catch {
    Write-Host ''
    Write-Host '  [X] Could not check Connect lock.' -ForegroundColor Red
    Write-Host ''
    exit 0
}

$owned = $false
try {
    $owned = $m.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    $owned = $true
} catch {
    try { $m.Dispose() } catch { }
    Write-Host ''
    Write-Host '  [X] Could not check Connect lock.' -ForegroundColor Red
    Write-Host ''
    exit 0
}

if (-not $owned) {
    try { $m.Dispose() } catch { }
    Write-Host ''
    Write-Host '  [i] Claude Connect is already running - use the existing window.' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}

# Transfer ownership to connect-ui Enter/Exit (same process).
$global:ClaudeConnectBootMutex = $m
$env:CLAUDE_CONNECT_BOOT_MUTEX = '1'

$connectPs1 = Join-Path $here 'connect.ps1'
if (-not (Test-Path -LiteralPath $connectPs1)) {
    try { $m.ReleaseMutex() } catch { }
    try { $m.Dispose() } catch { }
    Write-Host ''
    Write-Host '  [X] connect.ps1 missing next to connect-boot.ps1.' -ForegroundColor Red
    Write-Host ''
    exit 1
}

try {
    & $connectPs1 @args
    $ec = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
} catch {
    $ec = 1
    Write-Host ("  [X] connect.ps1 failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
} finally {
    # If connect.ps1 never took ownership, release here.
    if ($global:ClaudeConnectBootMutex) {
        try { $global:ClaudeConnectBootMutex.ReleaseMutex() } catch { }
        try { $global:ClaudeConnectBootMutex.Dispose() } catch { }
        $global:ClaudeConnectBootMutex = $null
    }
    $env:CLAUDE_CONNECT_BOOT_MUTEX = $null
}
exit $ec
'''
(root / 'scripts/client/windows/connect-boot.ps1').write_text(boot, encoding='utf-8', newline='\n')
print('OK connect-boot.ps1')

# --- connect-ui.ps1: accept preheld mutex ---
ui_path = root / 'scripts/client/connect-ui.ps1'
ui = ui_path.read_text(encoding='utf-8')
old_enter = '''function Enter-ConnectSingleInstance {
    # One connect UI per machine (global mutex).
    param([string]$Name = '')
    if (-not $Name) { $Name = 'Global\\ClaudeConnect' }
    $script:ConnectInstanceMutex = $null
    try {
        $created = $false
        $m = New-Object System.Threading.Mutex($false, $Name, [ref]$created)
        $script:ConnectInstanceMutex = $m
        if (-not $m.WaitOne(0)) {'''
new_enter = '''function Enter-ConnectSingleInstance {
    # One connect UI per machine (global mutex).
    param([string]$Name = '')
    if (-not $Name) { $Name = 'Global\\ClaudeConnect' }
    # connect-boot.ps1 may already hold the mutex in this process (no TOCTOU).
    if ($env:CLAUDE_CONNECT_BOOT_MUTEX -eq '1' -and $global:ClaudeConnectBootMutex) {
        $script:ConnectInstanceMutex = $global:ClaudeConnectBootMutex
        $global:ClaudeConnectBootMutex = $null
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("SINGLE_INSTANCE: acquired pid={0} via=connect-boot" -f $PID) 'INFO'
        }
        return $true
    }
    $script:ConnectInstanceMutex = $null
    try {
        $created = $false
        $m = New-Object System.Threading.Mutex($false, $Name, [ref]$created)
        $script:ConnectInstanceMutex = $m
        if (-not $m.WaitOne(0)) {'''
if 'via=connect-boot' in ui:
    print('SKIP ui preheld already')
elif old_enter not in ui:
    raise SystemExit('MISS Enter-ConnectSingleInstance head')
else:
    ui_path.write_text(ui.replace(old_enter, new_enter, 1), encoding='utf-8', newline='\n')
    print('OK ui preheld mutex')

# --- connect.bat: use connect-boot, remove TOCTOU probe ---
bat_path = root / 'scripts/client/windows/connect.bat'
bat = bat_path.read_text(encoding='utf-8')
# add OUTDATED check for connect-boot.ps1
if 'connect-boot.ps1' not in bat.split('OUTDATED')[0] if 'OUTDATED' in bat else bat:
    pass
old_outdated_line = 'if not exist "%HERE%connect.ps1" set "OUTDATED=1"'
new_outdated_line = 'if not exist "%HERE%connect.ps1" set "OUTDATED=1"\nif not exist "%HERE%connect-boot.ps1" set "OUTDATED=1"'
if 'connect-boot.ps1" set "OUTDATED' in bat:
    print('SKIP bat outdated already')
elif old_outdated_line in bat:
    bat = bat.replace(old_outdated_line, new_outdated_line, 1)
    print('OK bat outdated includes boot')
else:
    print('WARN outdated needle')

old_tail = '''REM Pauses in this launcher: OUTDATED block only (pause+exit /b 1). Update paths never pause.
REM Early single-instance gate: avoid spawning a second connect.ps1 window.
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $m=New-Object System.Threading.Mutex($false,'Global\\ClaudeConnect'); if(-not $m.WaitOne(0)){ Write-Host ''; Write-Host '  [i] Claude Connect is already running - use the existing window.' -ForegroundColor Yellow; Write-Host ''; exit 3 }; $m.ReleaseMutex()|Out-Null; $m.Dispose(); exit 0 } catch { Write-Host ''; Write-Host '  [X] Could not check Connect lock.' -ForegroundColor Red; Write-Host ''; exit 3 }" 2>nul
if errorlevel 3 (
    exit /b 0
)

REM Hand off to connect.ps1 in its own window; close bootstrap cmd so update text does not hang.
start "" /D "%HERE%" powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%connect.ps1" %*
exit /b 0
'''
new_tail = '''REM Pauses in this launcher: OUTDATED block only (pause+exit /b 1). Update paths never pause.
REM Atomic single-instance: connect-boot.ps1 acquires Global\\ClaudeConnect THEN runs connect.ps1 (no probe/release TOCTOU).
start "" /D "%HERE%" powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%connect-boot.ps1" %*
exit /b 0
'''
if 'connect-boot.ps1" %*' in bat and 'TOCTOU' in bat:
    print('SKIP bat boot handoff already')
elif old_tail in bat:
    bat = bat.replace(old_tail, new_tail, 1)
    print('OK bat boot handoff')
elif old_tail.replace('\n', '\r\n') in bat:
    bat = bat.replace(old_tail.replace('\n', '\r\n'), new_tail.replace('\n', '\r\n'), 1)
    print('OK bat boot handoff CRLF')
else:
    # softer: replace start connect.ps1 line and remove probe block
    if 'connect-boot.ps1' in bat and 'Early single-instance gate' not in bat:
        print('SKIP bat already migrated')
    else:
        # remove early gate block by regex
        bat2, n = re.subn(
            r'REM Early single-instance gate:.*?\r?\nif errorlevel 3 \(\r?\n    exit /b 0\r?\n\)\r?\n\r?\n',
            'REM Atomic single-instance: connect-boot.ps1 acquires mutex then runs connect.ps1 (no TOCTOU).\r\n',
            bat,
            count=1,
            flags=re.S,
        )
        bat2 = bat2.replace(
            'start "" /D "%HERE%" powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%connect.ps1" %*',
            'start "" /D "%HERE%" powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%connect-boot.ps1" %*',
            1,
        )
        if bat2 == bat:
            raise SystemExit('MISS bat tail patterns')
        bat = bat2
        print('OK bat boot handoff soft')

bat_path.write_text(bat, encoding='utf-8', newline='\n')
print('OK bat written')

# --- Mac: flock before update ---
sh_path = root / 'scripts/client/mac/connect.sh'
sh = sh_path.read_text(encoding='utf-8')
early = '''export CLAUDE_CONNECT_RUN_ID
_bootstrap_log_dir="$HOME/.config/claude-connect/logs"
'''
# insert early flock after RUN_ID export, before bootstrap log / update
marker = '''export CLAUDE_CONNECT_RUN_ID
_bootstrap_log_dir="$HOME/.config/claude-connect/logs"
'''
insert_after_runid = '''export CLAUDE_CONNECT_RUN_ID

# Early single-instance (before update): same lockfile as enter_connect_single_instance.
_lockdir_early="$HOME/.config/claude-connect"
mkdir -p "$_lockdir_early" 2>/dev/null || true
exec 9>"$_lockdir_early/connect.lock" || true
if ! flock -n 9 2>/dev/null; then
    printf '\\n  [i] Claude Connect is already running - use the existing window.\\n\\n' >&2
    exit 0
fi
CONNECT_LOCK_HELD=1

_bootstrap_log_dir="$HOME/.config/claude-connect/logs"
'''
if 'flock -n 9' in sh.split('_update_script')[0]:
    print('SKIP mac early flock already')
elif marker in sh:
    sh = sh.replace(marker, insert_after_runid, 1)
    print('OK mac early flock')
else:
    print('WARN mac marker')

# enter_connect_single_instance honor preheld
ui_sh = root / 'scripts/client/connect-ui.sh'
uis = ui_sh.read_text(encoding='utf-8')
old_mac = '''enter_connect_single_instance() {
    # One connect UI per machine via flock on lock file.
    local lockdir="${HOME}/.config/claude-connect"
    local lockfile="${lockdir}/connect.lock"
    mkdir -p "$lockdir" 2>/dev/null || true
    exec 9>"$lockfile" || return 1
    if ! flock -n 9; then
'''
new_mac = '''enter_connect_single_instance() {
    # One connect UI per machine via flock on lock file.
    # connect.sh may already hold fd 9 (early flock before update).
    if [ "${CONNECT_LOCK_HELD:-0}" = 1 ]; then
        connect_log "SINGLE_INSTANCE: acquired pid=$$ via=early_flock" 'INFO'
        return 0
    fi
    local lockdir="${HOME}/.config/claude-connect"
    local lockfile="${lockdir}/connect.lock"
    mkdir -p "$lockdir" 2>/dev/null || true
    exec 9>"$lockfile" || return 1
    if ! flock -n 9; then
'''
if 'via=early_flock' in uis:
    print('SKIP mac enter preheld')
elif old_mac in uis:
    ui_sh.write_text(uis.replace(old_mac, new_mac, 1), encoding='utf-8', newline='\n')
    print('OK mac enter preheld')
else:
    print('WARN mac enter needle')

if marker in sh or 'CONNECT_LOCK_HELD=1' in sh.split('_update_script')[0]:
    sh_path.write_text(sh, encoding='utf-8', newline='\n')

# --- strip BOM from connect.ps1 if present ---
cp = root / 'scripts/client/windows/connect.ps1'
raw = cp.read_bytes()
if raw.startswith(b'\xef\xbb\xbf'):
    cp.write_bytes(raw[3:])
    print('OK stripped BOM from connect.ps1')
else:
    print('OK connect.ps1 no BOM')

# --- publish.ps1 include connect-boot ---
pub = root / 'publish/publish.ps1'
pt = pub.read_text(encoding='utf-8')
needle = '    @{ Src = "scripts\\client\\windows\\connect.bat";       Dst = "windows\\connect.bat";       PatchIp = $false }\n'
add = needle + '    @{ Src = "scripts\\client\\windows\\connect-boot.ps1";  Dst = "windows\\connect-boot.ps1";  PatchIp = $false }\n'
if 'connect-boot.ps1' in pt:
    print('SKIP publish already has boot')
elif needle in pt:
    pub.write_text(pt.replace(needle, add, 1), encoding='utf-8', newline='\n')
    print('OK publish lists connect-boot')
else:
    raise SystemExit('MISS publish needle')

# --- version bump ---
for p in [root / 'scripts/client/windows/connect-version.txt', root / 'scripts/client/mac/connect-version.txt']:
    p.write_text(ver + '\n', encoding='utf-8', newline='\n')
for p in [root / 'scripts/client/windows/connect.ps1', root / 'scripts/client/mac/connect.sh']:
    t = p.read_text(encoding='utf-8')
    t2 = re.sub(r'20260720\.\d+', ver, t)
    # only version-ish - careful not to replace too much in ps1
    if p.suffix == '.ps1':
        t2 = re.sub(r"ConnectVersion = '20260720\.\d+'", f"ConnectVersion = '{ver}'", t)
        t2 = re.sub(r'20260720\.\d+', ver, t2)  # may over-replace - check
        # safer: only ConnectVersion line
        t2 = re.sub(r"ConnectVersion = '20260720\.\d+'", f"ConnectVersion = '{ver}'", t)
    p.write_text(t2, encoding='utf-8', newline='\n')
    print(f'OK version in {p.name}')

# ensure mac CONNECT_VERSION
sh = sh_path.read_text(encoding='utf-8')
sh = re.sub(r"CONNECT_VERSION='20260720\.\d+'", f"CONNECT_VERSION='{ver}'", sh)
sh_path.write_text(sh, encoding='utf-8', newline='\n')

# --- tests ---
ht = root / 'scripts/client/tests/test-hard-multi-agent-regressions.ps1'
h = ht.read_text(encoding='utf-8')
h2 = h.replace(
    "Assert ($bat -match 'Early single-instance gate') 'connect.bat probes mutex before start connect.ps1'",
    "Assert ($bat -match 'connect-boot\\.ps1') 'connect.bat handoffs via connect-boot.ps1 (atomic mutex)'\n"
    "Assert ($bat -notmatch 'ReleaseMutex') 'connect.bat must not probe/release mutex (TOCTOU)'\n"
    "Assert (Test-Path (Join-Path $Client 'windows\\connect-boot.ps1')) 'connect-boot.ps1 exists'",
)
if 'connect-boot.ps1 (atomic mutex)' in h:
    print('SKIP hard asserts')
elif h2 != h:
    ht.write_text(h2, encoding='utf-8', newline='\n')
    print('OK hard asserts')
else:
    print('WARN hard assert needle')

# pipeline test may mention early gate
pp = root / 'scripts/client/tests/test-connect-pipeline.ps1'
if pp.exists():
    t = pp.read_text(encoding='utf-8')
    t2 = t.replace(
        "Assert ($connectBat -match 'Early single-instance gate') 'connect.bat probes mutex before spawning connect.ps1'",
        "Assert ($connectBat -match 'connect-boot\\.ps1') 'connect.bat handoffs via connect-boot.ps1'",
    )
    t2 = t2.replace(
        "Assert ($connectBat -match 'start \"\" /D \"%HERE%\" powershell.*connect\\.ps1') 'connect.bat async handoff starts connect.ps1'",
        "Assert ($connectBat -match 'start \"\" /D \"%HERE%\" powershell.*connect-boot\\.ps1') 'connect.bat async handoff starts connect-boot.ps1'",
    )
    if t2 != t:
        pp.write_text(t2, encoding='utf-8', newline='\n')
        print('OK pipeline asserts')

p0 = root / 'scripts/client/tests/test-p0-connect-fixes.ps1'
if p0.exists():
    t = p0.read_text(encoding='utf-8')
    t2 = re.sub(r'20260720\.\d+', ver, t)
    p0.write_text(t2, encoding='utf-8', newline='\n')
    print('OK p0 pins')

print('DONE', ver)
