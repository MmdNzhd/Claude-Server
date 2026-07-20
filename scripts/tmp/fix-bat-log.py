from pathlib import Path
p = Path('scripts/client/windows/connect.bat')
c = p.read_text(encoding='utf-8')
old = '''if exist "%HERE%connect-update.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%connect-update.ps1" -ScriptDir "%HERE_NOTRAIL%"
    if !errorlevel! EQU 2 (
        set /a CLAUDE_CONNECT_UPDATE_DEPTH+=1
        if !CLAUDE_CONNECT_UPDATE_DEPTH! GEQ 3 (
            echo.
            echo   [X] Update relaunch limit reached - continuing with current files.
            echo.
        ) else (
            echo.
            echo   Restarting with updated files...
            echo.
            call "%~f0" %*
            exit /b !errorlevel!
        )
    )
)
'''
new = '''if exist "%HERE%connect-update.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%connect-update.ps1" -ScriptDir "%HERE_NOTRAIL%"
    set "UPD_EC=!errorlevel!"
    if !UPD_EC! EQU 1 (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\\claude-connect\\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [ERROR] [{1}] FAIL UPDATE_BAT_EXIT: connect-update.ps1 exit=1 (update failed)' -f $ts, $sid); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
    )
    if !UPD_EC! EQU 2 (
        set /a CLAUDE_CONNECT_UPDATE_DEPTH+=1
        if !CLAUDE_CONNECT_UPDATE_DEPTH! GEQ 3 (
            echo.
            echo   [X] Update relaunch limit reached - continuing with current files.
            echo.
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\\claude-connect\\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [ERROR] [{1}] FAIL UPDATE_RELAUNCH_LIMIT: depth>=3 continuing with current files' -f $ts, $sid); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
        ) else (
            echo.
            echo   Restarting with updated files...
            echo.
            call "%~f0" %*
            exit /b !errorlevel!
        )
    )
)
'''
if old not in c:
    raise SystemExit('bat block not found exact')
p.write_text(c.replace(old, new, 1), encoding='utf-8', newline='\r\n')
print('OK bat')

# Fix Write-ConnectUserFacingError formatting if broken
ui = Path('scripts/client/connect-ui.ps1')
t = ui.read_text(encoding='utf-8')
bad = 'Write-ConnectLog ("USER_ERROR:{0} {1}" -f $suffix, $safe).Trim() \'ERROR\''
# check actual
idx = t.find('function Write-ConnectUserFacingError')
print(t[idx:idx+450])
# Fix to cleaner form
old_fn = '''function Write-ConnectUserFacingError {
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
'''
# The regex in file might have single backslashes
import re
m = re.search(r'function Write-ConnectUserFacingError \{.*?\n\}', t, re.S)
if not m:
    raise SystemExit('fn not found')
print('FOUND FN')
new_fn = '''function Write-ConnectUserFacingError {
    # Every red [X] the user sees MUST land in the day log as ERROR (grep-able).
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Code = ''
    )
    $safe = (($Message + '') -replace '[\\r\\n]+', ' ').Trim()
    if ($safe.Length -gt 500) { $safe = $safe.Substring(0, 500) + '...' }
    if ($Code) {
        Write-ConnectLog ("USER_ERROR: code={0} {1}" -f $Code, $safe) 'ERROR'
    } else {
        Write-ConnectLog ("USER_ERROR: {0}" -f $safe) 'ERROR'
    }
}
'''
t2 = t[:m.start()] + new_fn + t[m.end():]
ui.write_text(t2, encoding='utf-8', newline='\n')
print('OK ui helper')

# Add pipeline asserts
tp = Path('scripts/client/tests/test-connect-pipeline.ps1')
tc = tp.read_text(encoding='utf-8')
needle = "Assert ($ui -match 'MULTI_INSTANCE: allowed') 'connect-ui.ps1 allows unlimited concurrent instances'"
add = """Assert ($ui -match 'MULTI_INSTANCE: allowed') 'connect-ui.ps1 allows unlimited concurrent instances'
Assert ($ui -match 'FAIL EXIT reason=') 'connect-ui.ps1 logs FAIL EXIT on non-zero Wait-ConnectExit'
Assert ($ui -match 'Write-ConnectUserFacingError') 'connect-ui.ps1 has Write-ConnectUserFacingError'
Assert ($winSrc -match \"FAIL STEP name=\") 'connect.ps1 logs FAIL STEP on StepFail'
Assert ($winSrc -match 'FAIL NEED_ADMIN') 'connect.ps1 logs FAIL NEED_ADMIN when prompting UAC'
Assert ($upd -match 'FAIL UPDATE_UNHANDLED') 'connect-update.ps1 traps unhandled as FAIL UPDATE_UNHANDLED'"""
# Need $winSrc and $upd variables - check if they exist in test file
if 'FAIL EXIT reason=' in tc:
    print('tests already have FAIL EXIT')
else:
    # find how ui/winSrc loaded
    for line in tc.splitlines():
        if 'connect-ui.ps1' in line and ('Get-Content' in line or '$ui' in line):
            print('LINE', line[:120])
    if needle not in tc:
        raise SystemExit('needle missing')
    # simpler asserts on $ui only + read files inline
    add2 = """Assert ($ui -match 'MULTI_INSTANCE: allowed') 'connect-ui.ps1 allows unlimited concurrent instances'
Assert ($ui -match 'FAIL EXIT reason=') 'connect-ui.ps1 logs FAIL EXIT on non-zero Wait-ConnectExit'
Assert ($ui -match 'Write-ConnectUserFacingError') 'connect-ui.ps1 has Write-ConnectUserFacingError'
Assert ((Get-Content (Join-Path $ClientRoot 'windows\\connect.ps1') -Raw) -match 'FAIL NEED_ADMIN') 'connect.ps1 logs FAIL NEED_ADMIN'
Assert ((Get-Content (Join-Path $ClientRoot 'windows\\connect.ps1') -Raw) -match 'FAIL STEP name=') 'connect.ps1 logs FAIL STEP'
Assert ((Get-Content (Join-Path $ClientRoot 'windows\\connect-update.ps1') -Raw) -match 'FAIL UPDATE_UNHANDLED') 'connect-update.ps1 traps FAIL UPDATE_UNHANDLED'"""
    # Check $ClientRoot
    if '$ClientRoot' not in tc and 'scripts\\client' in tc:
        add2 = """Assert ($ui -match 'MULTI_INSTANCE: allowed') 'connect-ui.ps1 allows unlimited concurrent instances'
Assert ($ui -match 'FAIL EXIT reason=') 'connect-ui.ps1 logs FAIL EXIT on non-zero Wait-ConnectExit'
Assert ($ui -match 'Write-ConnectUserFacingError') 'connect-ui.ps1 has Write-ConnectUserFacingError'
Assert ($src -match 'FAIL NEED_ADMIN') 'connect.ps1 logs FAIL NEED_ADMIN'
Assert ($src -match 'FAIL STEP name=') 'connect.ps1 logs FAIL STEP'
Assert ((Get-Content (Join-Path $PSScriptRoot '..\\windows\\connect-update.ps1') -Raw) -match 'FAIL UPDATE_UNHANDLED') 'connect-update.ps1 traps FAIL UPDATE_UNHANDLED'"""
    tp.write_text(tc.replace(needle, add2, 1), encoding='utf-8', newline='\n')
    print('OK tests')
print('DONE')
