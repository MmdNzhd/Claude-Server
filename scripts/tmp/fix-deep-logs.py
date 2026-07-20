from pathlib import Path
import re

# ========== Windows connect.ps1 ==========
p = Path('scripts/client/windows/connect.ps1')
c = p.read_text(encoding='utf-8')

# 1) SshX SSH_END levels + quote FAIL
old_ssh = '''    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "SSH_END exit=$($result.Exit) ms=$($result.Ms) out=$truncOut"
    }
'''
new_ssh = '''    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        $sshLevel = 'INFO'
        if ($result.Exit -eq 124) { $sshLevel = 'ERROR' }
        elseif ($result.Exit -ne 0) { $sshLevel = 'WARN' }
        Write-ConnectLog "SSH_END exit=$($result.Exit) ms=$($result.Ms) out=$truncOut" $sshLevel
        if ($truncOut -match 'unexpected EOF while looking for matching') {
            Write-ConnectLog ("FAIL SSH_QUOTE: exit={0} cmd={1} out={2}" -f $result.Exit, $truncCmd, $truncOut) 'ERROR'
        } elseif ($result.Exit -ne 0 -and $result.Exit -ne 124 -and $truncOut -match '(?i)Permission denied|Connection refused|Could not resolve|No route to host|Connection timed out') {
            Write-ConnectLog ("FAIL SSH_END: exit={0} cmd={1}" -f $result.Exit, $truncCmd) 'ERROR'
        }
    }
'''
if old_ssh not in c:
    raise SystemExit('SshX SSH_END block not found')
c = c.replace(old_ssh, new_ssh, 1)

# 2) Connect retry logging
old_retry = '''for ($attempt = 1; $attempt -le 10; $attempt++) {
    Write-Host -NoNewline ("    Connecting $attempt/10").PadRight(46, '.') -ForegroundColor DarkCyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=15 $Alias "true" 2>$null
    $sw.Stop()
    $connT = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if ($LASTEXITCODE -eq 0) {
        Write-Host " $RemoteUser@$ServerIP" -ForegroundColor Green
        $connected = $true; break
    }
    if (PortOpen $ServerIP 22) {
        Write-Host " auth failed (${connT}s) - no key, installing now" -ForegroundColor DarkYellow
        $needsKey = $true; break
    }
    Write-Host " no response (${connT}s)" -ForegroundColor DarkGray
    if ($attempt -lt 10) {
        Write-Host "    Waiting 5s (VPN on? Server up?)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
    }
}

if (-not $connected -and -not $needsKey) {
    Write-Host ""
    Warn "Cannot reach $ServerIP after 10 attempts"
    Warn "VPN connected? Server running?"
    Wait-ConnectExit -Reason 'require_fail' -Code 1
}
'''
new_retry = '''for ($attempt = 1; $attempt -le 10; $attempt++) {
    Write-Host -NoNewline ("    Connecting $attempt/10").PadRight(46, '.') -ForegroundColor DarkCyan
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("CONNECT_ATTEMPT n={0}/10 alias={1} target={2}@{3}" -f $attempt, $Alias, $RemoteUser, $ServerIP)
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=15 $Alias "true" 2>$null
    $sw.Stop()
    $connT = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if ($LASTEXITCODE -eq 0) {
        Write-Host " $RemoteUser@$ServerIP" -ForegroundColor Green
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("CONNECT_OK attempt={0} sec={1} target={2}@{3}" -f $attempt, $connT, $RemoteUser, $ServerIP)
        }
        $connected = $true; break
    }
    if (PortOpen $ServerIP 22) {
        Write-Host " auth failed (${connT}s) - no key, installing now" -ForegroundColor DarkYellow
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("CONNECT_AUTH_NEEDED attempt={0} sec={1} port22=open" -f $attempt, $connT) 'WARN'
        }
        $needsKey = $true; break
    }
    Write-Host " no response (${connT}s)" -ForegroundColor DarkGray
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("CONNECT_NO_RESPONSE attempt={0} sec={1}" -f $attempt, $connT) 'WARN'
    }
    if ($attempt -lt 10) {
        Write-Host "    Waiting 5s (VPN on? Server up?)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
    }
}

if (-not $connected -and -not $needsKey) {
    Write-Host ""
    Warn "Cannot reach $ServerIP after 10 attempts"
    Warn "VPN connected? Server running?"
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("FAIL CONNECT_UNREACHABLE: target={0}@{1} attempts=10" -f $RemoteUser, $ServerIP) 'ERROR'
    }
    Wait-ConnectExit -Reason 'require_fail' -Code 1
}
'''
if old_retry not in c:
    raise SystemExit('retry block not found')
c = c.replace(old_retry, new_retry, 1)

# 3) Ensure-LaptopSshReady + project menu
old_menu = '''$null = Ensure-LaptopSshReady -PubB $PubB
$script:LaptopSshVerified = $false
$script:SessionBgTunnel = $null
$null = Initialize-SessionBgTunnel -Alias $Alias -SshCfgPath $sshCfg -Quiet

$script:tunnelAuthAdminFixAttempted = $false
$exitRequested = $false
:menuLoop while (-not $exitRequested) {
    Step "Loading projects"
    $null = ($allMounts = @(Get-Mounts))
    StepOk (Get-MountListStepLabel -Os 'windows' -Mounts $allMounts)
    $go = @(Choose-Project -Mounts $allMounts)[-1]
    if (-not $go) { break }
    Write-ConnectLog "PROJECT: id=$($go.Id) server_path=$($go.Path) laptop_path=$($go.Rpath)"
'''
new_menu = '''$laptopReady = Ensure-LaptopSshReady -PubB $PubB
if (-not $laptopReady) {
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'FAIL LAPTOP_SSH_BOOT: Ensure-LaptopSshReady returned false (continuing; tunnel auth may still work)' 'ERROR'
    }
    Warn 'Laptop SSH admin fix incomplete - continuing; tunnel auth may fail until fixed'
} else {
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'LAPTOP_SSH: boot_ready ok'
    }
}
$script:LaptopSshVerified = $false
$script:SessionBgTunnel = $null
$null = Initialize-SessionBgTunnel -Alias $Alias -SshCfgPath $sshCfg -Quiet

$script:tunnelAuthAdminFixAttempted = $false
$exitRequested = $false
:menuLoop while (-not $exitRequested) {
    Step "Loading projects"
    $null = ($allMounts = @(Get-Mounts))
    StepOk (Get-MountListStepLabel -Os 'windows' -Mounts $allMounts)
    if (Get-Command Show-ConnectConsoleIfHidden -ErrorAction SilentlyContinue) { Show-ConnectConsoleIfHidden }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("INTERACTIVE: project_menu_shown mounts={0}" -f @($allMounts).Count) 'INFO'
    }
    $go = @(Choose-Project -Mounts $allMounts)[-1]
    if (-not $go) {
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog 'FAIL MENU_ABORT: Choose-Project returned empty (user quit or no selection)' 'ERROR'
        }
        break
    }
    Write-ConnectLog "PROJECT: id=$($go.Id) server_path=$($go.Path) laptop_path=$($go.Rpath)"
    if (Get-Command Write-ConnectDecision -ErrorAction SilentlyContinue) {
        Write-ConnectDecision 'project_selected' $go.Id
    }
'''
if old_menu not in c:
    raise SystemExit('menu block not found')
c = c.replace(old_menu, new_menu, 1)

# 4) push fail log
old_push = '''if ($boot.ContainsKey('PushOk') -and -not $boot.PushOk) {
    Write-Host '    [!] server script push failed (continuing)' -ForegroundColor Yellow
}
'''
new_push = '''if ($boot.ContainsKey('PushOk') -and -not $boot.PushOk) {
    Write-Host '    [!] server script push failed (continuing)' -ForegroundColor Yellow
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'FAIL SERVER_SCRIPT_PUSH: continuing without refreshed server scripts' 'ERROR'
    }
}
'''
if old_push not in c:
    raise SystemExit('push fail block not found')
c = c.replace(old_push, new_push, 1)

ver = '20260720.7'
c, n = re.subn(r"ConnectVersion = '\d{8}\.\d+'", f"ConnectVersion = '{ver}'", c, count=1)
if n != 1:
    raise SystemExit('ver bump fail win')
p.write_text(c, encoding='utf-8', newline='\n')
print('OK connect.ps1')

# ========== Mac connect-ui.sh timestamps ==========
p = Path('scripts/client/connect-ui.sh')
c = p.read_text(encoding='utf-8')
# Add helper for ms timestamp near top after shebang area - find connect_log printf
old_printf = '''printf '[%s] [%s] [%s] %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "${CONNECT_SESSION_ID:--}" "$msg" >> "$CONNECT_LOG_PATH" 2>/dev/null || true'''
# actual file may use different escaping
if "date '+%Y-%m-%d %H:%M:%S'" not in c:
    raise SystemExit('mac date format not found')

# Insert helper function before connect_log if missing
if 'connect_log_ts()' not in c:
    c = c.replace(
        'connect_log() {',
        '''connect_log_ts() {
    # Milliseconds for parity with Windows Write-ConnectLog (.fff).
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import time; t=time.time(); print(time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)) + ".%03d" % int((t%1)*1000))' 2>/dev/null && return 0
    fi
    date '+%Y-%m-%d %H:%M:%S.000'
}

connect_log() {''',
        1,
    )
c = c.replace(
    "printf '[%s] [%s] [%s] %s\\n' \"$(date '+%Y-%m-%d %H:%M:%S')\" \"$level\" \"${CONNECT_SESSION_ID:--}\" \"$msg\" >> \"$CONNECT_LOG_PATH\" 2>/dev/null || true",
    "printf '[%s] [%s] [%s] %s\\n' \"$(connect_log_ts)\" \"$level\" \"${CONNECT_SESSION_ID:--}\" \"$msg\" >> \"$CONNECT_LOG_PATH\" 2>/dev/null || true",
)
c = c.replace(
    "printf '[%s] [INFO] [%s] %s\\n' \"$(date '+%Y-%m-%d %H:%M:%S')\" \"${CONNECT_SESSION_ID:--}\" '======== session end ========' >> \"$CONNECT_LOG_PATH\" 2>/dev/null || true",
    "printf '[%s] [INFO] [%s] %s\\n' \"$(connect_log_ts)\" \"${CONNECT_SESSION_ID:--}\" '======== session end ========' >> \"$CONNECT_LOG_PATH\" 2>/dev/null || true",
)
p.write_text(c, encoding='utf-8', newline='\n')
print('OK connect-ui.sh ts')

# ========== Mac connect.sh EXIT traps ==========
p = Path('scripts/client/mac/connect.sh')
c = p.read_text(encoding='utf-8')
c = c.replace(
    'connect_log "UNHANDLED: exit=$ec" "ERROR"',
    'connect_log "FAIL UNHANDLED: exit=$ec" "ERROR"; connect_log "FAIL EXIT reason=trap_exit code=$ec" "ERROR"',
)
c = c.replace(
    'connect_log "UNHANDLED: exit=$ec line=$LINENO cmd=$BASH_COMMAND" "ERROR"',
    'connect_log "FAIL UNHANDLED: exit=$ec line=$LINENO cmd=$BASH_COMMAND" "ERROR"',
)
# bare exit after echo "" - add connect_log where declare -F works
# Fix update relaunch [X]
c2 = c.replace(
    '''printf '  [X] Update relaunch limit reached - continuing with current files.\\n' ''',
    '''printf '  [X] Update relaunch limit reached - continuing with current files.\\n'
  if declare -F connect_log >/dev/null 2>&1; then connect_log 'FAIL UPDATE_RELAUNCH_LIMIT: depth>=3 continuing with current files' 'ERROR'; fi
''',
)
# maybe different quote style
if c2 == c:
    # try without escape
    old_rel = "printf '  [X] Update relaunch limit reached - continuing with current files.\\n'"
    if old_rel not in c:
        # find line
        for i, line in enumerate(c.splitlines()):
            if 'Update relaunch limit' in line:
                print('RELAUNCH LINE', i+1, repr(line))
    else:
        c = c.replace(old_rel, old_rel + "\n  if declare -F connect_log >/dev/null 2>&1; then connect_log 'FAIL UPDATE_RELAUNCH_LIMIT: depth>=3 continuing with current files' 'ERROR'; fi")
else:
    c = c2

c, n = re.subn(r"CONNECT_VERSION='\d{8}\.\d+'", f"CONNECT_VERSION='{ver}'", c, count=1)
p.write_text(c, encoding='utf-8', newline='\n')
print('OK connect.sh', 'ver', n)

# ========== Mac connect-update.sh FAIL UPDATE ==========
p = Path('scripts/client/mac/connect-update.sh')
c = p.read_text(encoding='utf-8')
# find _update_file_log and ensure FAIL on exit 1 checksum
if 'FAIL UPDATE_' not in c:
    # patch common exit patterns - checksum
    for old, new in [
        ("exit 1\n", None),  # too broad
    ]:
        pass
    # After functions that log errors, upgrade messages containing fail to FAIL UPDATE_
    c = c.replace(
        '_update_file_log "',
        '_UPDATE_FILE_LOG_MARKER "',  # noop marker first - skip
    )
    c = c.replace('_UPDATE_FILE_LOG_MARKER "', '_update_file_log "')  # revert

    # Simpler: wrap _update_file_log to prefix FAIL UPDATE_ for ERROR level
    if 'FAIL UPDATE_PREFIX' not in c and '_update_file_log()' in c:
        # find function body end - inject at start of function
        old_fn = None
        m = re.search(r'_update_file_log\(\)\s*\{', c)
        if m:
            # insert after {
            pos = m.end()
            inject = '''
  # Harden: ERROR lines always carry FAIL UPDATE_ for greppable day log.
  if [ "${2:-INFO}" = "ERROR" ]; then
    case "$1" in
      FAIL\ UPDATE_*) ;;
      *) set -- "FAIL UPDATE_: $1" "$2" ;;
    esac
  fi
'''
            c = c[:pos] + inject + c[pos:]
            print('OK update.sh FAIL prefix inject')
p.write_text(c, encoding='utf-8', newline='\n')

# ========== Designer Win Die/StepFail ==========
p = Path('scripts/client/users/designer/connect.ps1')
c = p.read_text(encoding='utf-8')
if 'FAIL DIE:' not in c:
    # find function Die
    old_die = None
    m = re.search(r'function Die\([^\)]*\)\s*\{[^}]+\}', c, re.S)
    if m:
        print('designer Die:', m.group(0)[:200])
    # simple replace common pattern
    if 'function Die' in c and 'Write-ConnectLog' not in c[c.find('function Die'):c.find('function Die')+400]:
        c = c.replace(
            'function Die($m) {\n    Write-Host ""; Write-Host "  [X] $m" -ForegroundColor Red\n',
            'function Die($m) {\n    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) { Write-ConnectLog "FAIL DIE: $m" \'ERROR\' }\n    Write-Host ""; Write-Host "  [X] $m" -ForegroundColor Red\n',
            1,
        )
        # StepFail
        if "function StepFail" in c:
            c = c.replace(
                "Write-Host \" failed\" -ForegroundColor Red\n",
                "if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) { Write-ConnectLog (\"FAIL STEP name={0} detail={1}\" -f $script:currentStepName, $d) 'ERROR' }\n    Write-Host \" failed\" -ForegroundColor Red\n",
                1,
            )
        p.write_text(c, encoding='utf-8', newline='\n')
        print('OK designer connect.ps1')
    else:
        print('designer Die already has log or pattern differ')
else:
    print('designer already FAIL DIE')

# version files
for vp in [Path('scripts/client/windows/connect-version.txt'), Path('scripts/client/mac/connect-version.txt')]:
    vp.write_text(ver + '\n', encoding='utf-8')
print('DONE', ver)
