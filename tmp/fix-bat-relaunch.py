from pathlib import Path
import re

ROOT = Path(r"D:\Smart\Claude-Code-Server")
bat = ROOT / "scripts/client/windows/connect.bat"
t = bat.read_text(encoding="utf-8")

old = '''    if !UPD_EC! EQU 2 (
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
            start "" /D "%HERE%" "%~f0" %*
            exit 0
        )
    )'''

new = '''    if !UPD_EC! EQU 2 (
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
            REM /D must use HERE_NOTRAIL: trailing backslash in "dir\" escapes the quote and
            REM silently breaks start (Aria got exit=2 but no second BOOTSTRAP).
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\\claude-connect\\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [INFO] [{1}] UPDATE: bat_relaunch depth={2} dir={3}' -f $ts, $sid, $env:CLAUDE_CONNECT_UPDATE_DEPTH, '%HERE_NOTRAIL%'); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
            REM Brief delay so inplace-copied files release locks from this cmd instance.
            ping -n 2 127.0.0.1 >nul
            start "Claude Connect" /D "%HERE_NOTRAIL%" cmd /c ""%~f0" %*"
            exit 0
        )
    )'''

if old not in t:
    raise SystemExit('relaunch block not found in connect.bat')
bat.write_text(t.replace(old, new, 1), encoding="utf-8", newline="\r\n")
print("OK connect.bat relaunch fixed")

# bump .44
TARGET = "20260721.44"
for rel in ["scripts/client/windows/connect-version.txt", "scripts/client/mac/connect-version.txt"]:
    (ROOT / rel).write_text(TARGET + "\n", encoding="utf-8", newline="\n")
for path, pat, repl in [
    (ROOT / "scripts/client/windows/connect.ps1", r"ConnectVersion = '20260721\.\d+'", f"ConnectVersion = '{TARGET}'"),
    (ROOT / "scripts/client/mac/connect.sh", r"CONNECT_VERSION='20260721\.\d+'", f"CONNECT_VERSION='{TARGET}'"),
]:
    tt = path.read_text(encoding="utf-8")
    tt2, n = re.subn(pat, repl, tt, count=1)
    if n != 1:
        raise SystemExit(f"bump fail {path}")
    path.write_text(tt2, encoding="utf-8", newline="\n")
    print(f"bumped {path.name}")
print("DONE", TARGET)
