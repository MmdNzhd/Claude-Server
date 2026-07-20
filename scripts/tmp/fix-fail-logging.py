from pathlib import Path
import re

root = Path('.')

# ---------- connect-ui.ps1: Wait-ConnectExit + Write-ConnectUserFacingError ----------
p = root / 'scripts/client/connect-ui.ps1'
c = p.read_text(encoding='utf-8')

old_wait = '''function Wait-ConnectExit {
    param(
        [string]$Reason = 'user_close',
        [int]$Code = 1
    )
    # Do not prompt before UI is ready (early UAC/ssh/require fails must not hang or call this pre-load).
    Write-ConnectLog ("EXIT_WAIT: reason={0} code={1} uiReady={2}" -f $Reason, $Code, [bool]$script:ConnectUiReady) 'INFO'
    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer -Force | Out-Null }
    if ($script:ConnectUiReady) {
        try { Read-Host '    Press Enter to close' | Out-Null } catch { }
    }
    if (Get-Command Close-ConnectLog -ErrorAction SilentlyContinue) { Close-ConnectLog }
    exit $Code
}'''

new_wait = '''function Write-ConnectUserFacingError {
    # Every red [X] the user sees MUST land in the day log as ERROR (grep-able).
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Code = ''
    )
    $safe = (($Message + '') -replace '[\\r\\n]+', ' ').Trim()
    if ($safe.Length -gt 500) { $safe = $safe.Substring(0, 500) + '...' }
    $suffix = if ($Code) { " code=$Code" } else { '' }
    Write-ConnectLog ("USER_ERROR:{0} {1}" -f $suffix, $safe).Trim() 'ERROR'
}

function Wait-ConnectExit {
    param(
        [string]$Reason = 'user_close',
        [int]$Code = 1
    )
    # Non-zero exit = failure the operator must see in logs immediately (not INFO).
    $level = if ($Code -eq 0) { 'INFO' } else { 'ERROR' }
    Write-ConnectLog ("EXIT_WAIT: reason={0} code={1} uiReady={2}" -f $Reason, $Code, [bool]$script:ConnectUiReady) $level
    if ($Code -ne 0) {
        Write-ConnectLog ("FAIL EXIT reason={0} code={1}" -f $Reason, $Code) 'ERROR'
    }
    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer -Force | Out-Null }
    if ($script:ConnectUiReady) {
        try { Read-Host '    Press Enter to close' | Out-Null } catch { }
    }
    if (Get-Command Close-ConnectLog -ErrorAction SilentlyContinue) { Close-ConnectLog }
    exit $Code
}'''

if old_wait not in c:
    raise SystemExit('Wait-ConnectExit block not found')
c = c.replace(old_wait, new_wait, 1)
p.write_text(c, encoding='utf-8', newline='\n')
print('OK connect-ui.ps1 Wait-ConnectExit')

# ---------- connect.ps1: StepFail ERROR, admin logs, openssh, AdminFix ----------
p = root / 'scripts/client/windows/connect.ps1'
c = p.read_text(encoding='utf-8')

old_stepfail = '''        Write-ConnectLog "STEP end: $($script:currentStepName) failed ms=$ms detail=$detail" 'WARN'
'''
new_stepfail = '''        Write-ConnectLog "STEP end: $($script:currentStepName) failed ms=$ms detail=$detail" 'ERROR'
        Write-ConnectLog ("FAIL STEP name={0} detail={1}" -f $script:currentStepName, $detail) 'ERROR'
'''
if old_stepfail not in c:
    raise SystemExit('StepFail WARN line not found')
c = c.replace(old_stepfail, new_stepfail, 1)

# trap already logs UNHANDLED - also call Write-ConnectUserFacingError if available
old_trap = '''trap {
    Write-Host "  [X] Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
'''
# read actual trap
m = re.search(r'trap \{\n(?:.*\n){0,15}?\}', c)
if not m:
    raise SystemExit('trap not found')
# find exact lines around trap start
idx = c.find('trap {')
print('trap at', idx)

old_admin_wait = '''    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'LAPTOP_SSH: waiting_admin_prompt'
    }
    $yn = (Read-ConnectPrompt '    Allow administrator access? [Y/n]' -Tag 'ADMIN_UAC').Trim()
    Write-ConnectDecision 'admin_access' $yn
    if ($yn -match '^[Nn]') { return $false }
'''
new_admin_wait = '''    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'LAPTOP_SSH: waiting_admin_prompt' 'WARN'
        Write-ConnectLog 'FAIL NEED_ADMIN: Server laptop key missing from administrators_authorized_keys - prompting user' 'ERROR'
    }
    $yn = (Read-ConnectPrompt '    Allow administrator access? [Y/n]' -Tag 'ADMIN_UAC').Trim()
    Write-ConnectDecision 'admin_access' $yn
    if ($yn -match '^[Nn]') {
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog 'FAIL ADMIN_DENIED: user declined administrator access' 'ERROR'
        }
        return $false
    }
'''
if old_admin_wait not in c:
    raise SystemExit('admin wait block not found')
c = c.replace(old_admin_wait, new_admin_wait, 1)

old_uac = '''    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'LAPTOP_SSH: waiting_uac'
    }
    $proc = Start-Process powershell.exe -Verb RunAs -ArgumentList $elevArgs -Wait -PassThru
    $script:adminFixAttempted = $true
    return ($proc.ExitCode -eq 0)
'''
new_uac = '''    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'LAPTOP_SSH: waiting_uac' 'WARN'
    }
    $proc = Start-Process powershell.exe -Verb RunAs -ArgumentList $elevArgs -Wait -PassThru
    $script:adminFixAttempted = $true
    $ec = if ($null -eq $proc) { -1 } else { [int]$proc.ExitCode }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        if ($ec -eq 0) {
            Write-ConnectLog 'LAPTOP_SSH: admin_fix_ok' 'INFO'
        } else {
            Write-ConnectLog ("FAIL ADMIN_UAC: elevated fix exit={0} (user cancelled UAC or fix failed)" -f $ec) 'ERROR'
        }
    }
    return ($ec -eq 0)
'''
if old_uac not in c:
    raise SystemExit('uac block not found')
c = c.replace(old_uac, new_uac, 1)

old_openssh = '''    Write-Host "  [X] OpenSSH client (ssh.exe) not found." -ForegroundColor Red
'''
# need context - find Require-OpenSsh or similar
if 'OpenSSH client (ssh.exe) not found' in c:
    c = c.replace(
        'Write-Host "  [X] OpenSSH client (ssh.exe) not found." -ForegroundColor Red\n',
        '''if (Get-Command Write-ConnectUserFacingError -ErrorAction SilentlyContinue) {
        Write-ConnectUserFacingError 'OpenSSH client (ssh.exe) not found'
    } elseif (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'FAIL OpenSSH client (ssh.exe) not found' 'ERROR'
    }
    Write-Host "  [X] OpenSSH client (ssh.exe) not found." -ForegroundColor Red
''',
        1,
    )
    print('OK openssh log')

old_adminfix = "if (-not (Test-Path $fixFile)) { Write-Host '[X] No admin fix pending' -ForegroundColor Red; exit 1 }"
new_adminfix = """if (-not (Test-Path $fixFile)) {
        try {
            $d = Join-Path $env:USERPROFILE '.config\\claude-connect\\logs'
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            $f = Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
            $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
            $sid = if ($env:CLAUDE_CONNECT_RUN_ID) { $env:CLAUDE_CONNECT_RUN_ID } else { '-' }
            [IO.File]::AppendAllText($f, "[$ts] [ERROR] [$sid] FAIL ADMIN_FIX: No admin fix pending`n", [Text.UTF8Encoding]::new($false))
        } catch { }
        Write-Host '[X] No admin fix pending' -ForegroundColor Red
        exit 1
    }"""
if old_adminfix not in c:
    raise SystemExit('adminfix pending line not found')
c = c.replace(old_adminfix, new_adminfix, 1)

# Improve Die to also emit FAIL line (already has ERROR: )
old_die_log = '''        Write-ConnectLog "ERROR: $m" 'ERROR'
'''
if old_die_log in c:
    c = c.replace(old_die_log, '''        Write-ConnectLog "ERROR: $m" 'ERROR'
        Write-ConnectLog "FAIL DIE: $m" 'ERROR'
''', 1)
    print('OK Die FAIL')

p.write_text(c, encoding='utf-8', newline='\n')
print('OK connect.ps1')

# ---------- connect-update.ps1: trap ----------
p = root / 'scripts/client/windows/connect-update.ps1'
c = p.read_text(encoding='utf-8')
anchor = '''$null = Ensure-ConnectRunId

$RemoteBundle'''
insert = '''$null = Ensure-ConnectRunId

trap {
    $msg = $_.Exception.Message
    $pos = ''
    try { $pos = $_.InvocationInfo.PositionMessage } catch { }
    try { Write-UpdateFileLog ("UNHANDLED $msg at $pos") 'ERROR' } catch { }
    try {
        $d = Join-Path $env:USERPROFILE '.config\\claude-connect\\logs'
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        $f = Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = if ($env:CLAUDE_CONNECT_RUN_ID) { $env:CLAUDE_CONNECT_RUN_ID } else { '-' }
        $line = "[$ts] [ERROR] [$sid] FAIL UPDATE_UNHANDLED: $msg`n"
        [IO.File]::AppendAllText($f, $line, [Text.UTF8Encoding]::new($false))
    } catch { }
    Write-Host "  [X] Update error: $msg" -ForegroundColor Red
    continue
}

$RemoteBundle'''
# Problem: Write-UpdateFileLog defined later - trap calls it at runtime so OK if function exists by then.
# Early failures before Write-UpdateFileLog is defined still hit the direct AppendAllText.
if 'FAIL UPDATE_UNHANDLED' in c:
    print('update trap already present')
else:
    if anchor not in c:
        raise SystemExit('update anchor not found')
    c = c.replace(anchor, insert, 1)
    p.write_text(c, encoding='utf-8', newline='\n')
    print('OK connect-update.ps1 trap')

# Move Write-UpdateFileLog + Get-UpdateLogPath before trap? Trap at runtime uses them after functions defined.
# Early Ensure-ConnectRunId failures already fixed. Trap for later errors is fine.
# But trap is registered before Write-UpdateFileLog exists - when trap fires later, function exists. Good.
# When trap fires before function define, AppendAllText fallback works; Write-UpdateFileLog try catches.

# ---------- connect.bat: log update exit codes !=0,2 ----------
p = root / 'scripts/client/windows/connect.bat'
c = p.read_text(encoding='utf-8')
old_bat = '''if exist "%HERE%connect-update.ps1" (
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%connect-update.ps1" -ScriptDir "%HERE_NOTRAIL%"
if !errorlevel! EQU 2 (
'''
# Read actual bat section
print('--- bat update section ---')
for i, line in enumerate(c.splitlines(), 1):
    if 'connect-update' in line.lower() or 'errorlevel' in line.lower():
        if 20 <= i <= 45:
            print(f'{i}:{line}')

p.write_text(c, encoding='utf-8', newline='\n')  # no change yet until we see exact
print('bat inspect done')

# ---------- mac step_fail ERROR ----------
p = root / 'scripts/client/mac/connect.sh'
c = p.read_text(encoding='utf-8')
old_sf = """        connect_log \"STEP end: $CURRENT_STEP_NAME failed ms=$ms detail=$detail\" 'WARN'
"""
new_sf = """        connect_log \"STEP end: $CURRENT_STEP_NAME failed ms=$ms detail=$detail\" 'ERROR'
        connect_log \"FAIL STEP name=$CURRENT_STEP_NAME detail=$detail\" 'ERROR'
"""
if old_sf not in c:
    # try without escape
    old_sf2 = "        connect_log \"STEP end: $CURRENT_STEP_NAME failed ms=$ms detail=$detail\" 'WARN'\n"
    if old_sf2 not in c:
        raise SystemExit('mac step_fail not found: ' + repr(c[c.find('step_fail'):c.find('step_fail')+200]))
    c = c.replace(old_sf2, "        connect_log \"STEP end: $CURRENT_STEP_NAME failed ms=$ms detail=$detail\" 'ERROR'\n        connect_log \"FAIL STEP name=$CURRENT_STEP_NAME detail=$detail\" 'ERROR'\n", 1)
else:
    c = c.replace(old_sf, new_sf, 1)
old_die = '''        connect_log "ERROR: $*" 'ERROR' || true
'''
if old_die in c and 'FAIL DIE:' not in c:
    c = c.replace(old_die, '''        connect_log "ERROR: $*" 'ERROR' || true
        connect_log "FAIL DIE: $*" 'ERROR' || true
''', 1)
p.write_text(c, encoding='utf-8', newline='\n')
print('OK mac connect.sh')

# ---------- version bump to .3 ----------
ver = '20260720.3'
for rel, pat, rep in [
    ('scripts/client/windows/connect.ps1', r"ConnectVersion = '\d{8}\.\d+'", f"ConnectVersion = '{ver}'"),
    ('scripts/client/mac/connect.sh', r"CONNECT_VERSION='\d{8}\.\d+'", f"CONNECT_VERSION='{ver}'"),
]:
    pp = root / rel
    t = pp.read_text(encoding='utf-8')
    t2, n = re.subn(pat, rep, t, count=1)
    if n != 1:
        raise SystemExit(f'version replace fail {rel} n={n}')
    pp.write_text(t2, encoding='utf-8', newline='\n')
for vp in [root / 'scripts/client/windows/connect-version.txt', root / 'scripts/client/mac/connect-version.txt']:
    vp.write_text(ver + '\n', encoding='utf-8')
print('OK version', ver)
print('DONE phase1')
