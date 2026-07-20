from pathlib import Path
import re

root = Path('.')
p = root / 'scripts/client/windows/connect.ps1'
c = p.read_text(encoding='utf-8')

# StepFail
old_stepfail = '''        Write-ConnectLog "STEP end: $($script:currentStepName) failed ms=$ms detail=$detail" 'WARN'
'''
new_stepfail = '''        Write-ConnectLog "STEP end: $($script:currentStepName) failed ms=$ms detail=$detail" 'ERROR'
        Write-ConnectLog ("FAIL STEP name={0} detail={1}" -f $script:currentStepName, $detail) 'ERROR'
'''
if old_stepfail not in c:
    raise SystemExit('StepFail WARN line not found')
c = c.replace(old_stepfail, new_stepfail, 1)

# trap: add FAIL UNHANDLED + UserFacing
old_trap_log = '''    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "UNHANDLED: $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)" 'ERROR'
    }
'''
new_trap_log = '''    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "UNHANDLED: $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)" 'ERROR'
        Write-ConnectLog ("FAIL UNHANDLED: {0}" -f $_.Exception.Message) 'ERROR'
    }
'''
if old_trap_log not in c:
    raise SystemExit('trap log block not found')
c = c.replace(old_trap_log, new_trap_log, 1)

# OpenSSH early fail (before connect-ui may load) - append to day log directly
old_ssh = '''if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Host "  [X] OpenSSH client (ssh.exe) not found." -ForegroundColor Red
    Write-Host "      Install it via: Settings -> Apps -> Optional Features -> OpenSSH Client" -ForegroundColor DarkGray
'''
new_ssh = '''if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    try {
        $d = Join-Path $env:USERPROFILE '.config\\claude-connect\\logs'
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        $f = Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = if ($env:CLAUDE_CONNECT_RUN_ID) { $env:CLAUDE_CONNECT_RUN_ID } else { '-' }
        [IO.File]::AppendAllText($f, "[$ts] [ERROR] [$sid] FAIL OpenSSH client (ssh.exe) not found`n", [Text.UTF8Encoding]::new($false))
    } catch { }
    Write-Host "  [X] OpenSSH client (ssh.exe) not found." -ForegroundColor Red
    Write-Host "      Install it via: Settings -> Apps -> Optional Features -> OpenSSH Client" -ForegroundColor DarkGray
'''
if old_ssh not in c:
    raise SystemExit('openssh block not found')
c = c.replace(old_ssh, new_ssh, 1)

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

old_die_log = '''        Write-ConnectLog "ERROR: $m" 'ERROR'
'''
if old_die_log not in c:
    raise SystemExit('Die log not found')
c = c.replace(old_die_log, '''        Write-ConnectLog "ERROR: $m" 'ERROR'
        Write-ConnectLog "FAIL DIE: $m" 'ERROR'
''', 1)

p.write_text(c, encoding='utf-8', newline='\n')
print('OK connect.ps1')

# connect-update trap - place AFTER Write-UpdateFileLog is defined so early path is safer
p = root / 'scripts/client/windows/connect-update.ps1'
c = p.read_text(encoding='utf-8')
if 'FAIL UPDATE_UNHANDLED' in c:
    print('update trap already present')
else:
    # Insert right after Write-UpdateFileLog function
    marker = '''function Write-UpdateFileLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = Ensure-ConnectRunId
        $line = "[$ts] [$Level] [$sid] UPDATE: $Message`n"
        [System.IO.File]::AppendAllText((Get-UpdateLogPath), $line, [System.Text.UTF8Encoding]::new($false))
    } catch { }
}

function Get-ConnectVersionParts {'''
    repl = '''function Write-UpdateFileLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = Ensure-ConnectRunId
        $line = "[$ts] [$Level] [$sid] UPDATE: $Message`n"
        [System.IO.File]::AppendAllText((Get-UpdateLogPath), $line, [System.Text.UTF8Encoding]::new($false))
    } catch { }
}

trap {
    $msg = $_.Exception.Message
    $pos = ''
    try { $pos = $_.InvocationInfo.PositionMessage } catch { }
    try { Write-UpdateFileLog ("UNHANDLED $msg at $pos") 'ERROR' } catch { }
    try { Write-UpdateFileLog ("FAIL UPDATE_UNHANDLED: $msg") 'ERROR' } catch { }
    Write-Host "  [X] Update error: $msg" -ForegroundColor Red
    continue
}

function Get-ConnectVersionParts {'''
    if marker not in c:
        raise SystemExit('Write-UpdateFileLog marker not found')
    c = c.replace(marker, repl, 1)
    p.write_text(c, encoding='utf-8', newline='\n')
    print('OK connect-update.ps1')

# connect.bat - log non-success update exits
p = root / 'scripts/client/windows/connect.bat'
c = p.read_text(encoding='utf-8')
old = '''if exist "%HERE%connect-update.ps1" (
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%connect-update.ps1" -ScriptDir "%HERE_NOTRAIL%"
if !errorlevel! EQU 2 (
'''
# get exact content around lines 23-40
lines = c.splitlines(True)
# find the block
text = ''.join(lines)
# Look for pattern after update invoke
if 'FAIL UPDATE_BAT_EXIT' in c:
    print('bat already patched')
else:
    # After update powershell, if errorlevel not 0 and not 2, log ERROR
    # Current structure from earlier:
    # if exist ...
    # powershell ...
    # if !errorlevel! EQU 2 (
    #   ...
    # )
    # Need to see full block
    import re as _re
    m = _re.search(r'if exist "%HERE%connect-update\.ps1" \(\r?\n(?:.*\r?\n){1,20}?\)\r?\n', c)
    if not m:
        # try without
        print('BAT BLOCK:')
        for i, line in enumerate(c.splitlines(), 1):
            if 20 <= i <= 45:
                print(f'{i}|{line}')
        raise SystemExit('bat block regex failed')
    block = m.group(0)
    print('FOUND BAT BLOCK LEN', len(block))
    print(block[:500])

# mac
p = root / 'scripts/client/mac/connect.sh'
c = p.read_text(encoding='utf-8')
old_sf = "        connect_log \"STEP end: $CURRENT_STEP_NAME failed ms=$ms detail=$detail\" 'WARN'\n"
new_sf = "        connect_log \"STEP end: $CURRENT_STEP_NAME failed ms=$ms detail=$detail\" 'ERROR'\n        connect_log \"FAIL STEP name=$CURRENT_STEP_NAME detail=$detail\" 'ERROR'\n"
if old_sf not in c:
    raise SystemExit('mac step_fail not found')
c = c.replace(old_sf, new_sf, 1)
old_die = '        connect_log "ERROR: $*" \'ERROR\' || true\n'
if 'FAIL DIE:' not in c:
    if old_die not in c:
        # alternate quotes
        idx = c.find('connect_log "ERROR:')
        print(repr(c[idx:idx+80]))
        raise SystemExit('mac die not found')
    c = c.replace(old_die, '        connect_log "ERROR: $*" \'ERROR\' || true\n        connect_log "FAIL DIE: $*" \'ERROR\' || true\n', 1)
p.write_text(c, encoding='utf-8', newline='\n')
print('OK mac')

# version
ver = '20260720.3'
for rel, pat, rep in [
    ('scripts/client/windows/connect.ps1', r"ConnectVersion = '\d{8}\.\d+'", f"ConnectVersion = '{ver}'"),
    ('scripts/client/mac/connect.sh', r"CONNECT_VERSION='\d{8}\.\d+'", f"CONNECT_VERSION='{ver}'"),
]:
    pp = root / rel
    t = pp.read_text(encoding='utf-8')
    t2, n = re.subn(pat, rep, t, count=1)
    if n != 1:
        raise SystemExit(f'version {rel} n={n}')
    pp.write_text(t2, encoding='utf-8', newline='\n')
for vp in [root / 'scripts/client/windows/connect-version.txt', root / 'scripts/client/mac/connect-version.txt']:
    vp.write_text(ver + '\n', encoding='utf-8')
print('OK', ver)
print('DONE')
