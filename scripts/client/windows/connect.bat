@echo off
REM connect.bat - double-click launcher for Windows.
setlocal EnableDelayedExpansion
set "HERE=%~dp0"
set "HERE_NOTRAIL=%HERE:~0,-1%"
title Claude Connect

REM Stable run id: correlates BOOTSTRAP / UPDATE / session start in the day log
REM setlocal env vars inherit to child powershell -File (connect-update.ps1, connect.ps1).

if not defined CLAUDE_CONNECT_RUN_ID (

  for /f %%I in ('powershell -NoProfile -Command "[guid]::NewGuid().ToString('N').Substring(0,12)"') do set "CLAUDE_CONNECT_RUN_ID=%%I"

)

REM Log double-click immediately (before update) - durable local day log (BOM-less)

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [INFO] [{1}] BOOTSTRAP: connect.bat start here={2}' -f $ts, $sid, '%HERE%'); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul


if not defined CLAUDE_CONNECT_UPDATE_DEPTH set "CLAUDE_CONNECT_UPDATE_DEPTH=0"
if exist "%HERE%connect-update.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%connect-update.ps1" -ScriptDir "%HERE_NOTRAIL%"
    set "UPD_EC=!errorlevel!"
    if !UPD_EC! EQU 1 (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [ERROR] [{1}] FAIL UPDATE_BAT_EXIT: connect-update.ps1 exit=1 (update failed)' -f $ts, $sid); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
    )
    if !UPD_EC! EQU 2 (
        set /a CLAUDE_CONNECT_UPDATE_DEPTH+=1
        if !CLAUDE_CONNECT_UPDATE_DEPTH! GEQ 3 (
            echo.
            echo   [X] Update relaunch limit reached - continuing with current files.
            echo.
            powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $line=('[{0}] [ERROR] [{1}] FAIL UPDATE_RELAUNCH_LIMIT: depth>=3 continuing with current files' -f $ts, $sid); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
        ) else (
            echo.
            echo   Restarting with updated files...
            echo.
            call "%~f0" %*
            exit /b !errorlevel!
        )
    )
)

set "OUTDATED=0"
if not exist "%HERE%connect.ps1" set "OUTDATED=1"
if not exist "%HERE%connect-ui.ps1" set "OUTDATED=1"
if not exist "%HERE%editor-launch.ps1" set "OUTDATED=1"
if not exist "%HERE%git-mode.ps1" set "OUTDATED=1"
if not exist "%HERE%cursor-auth-laptop.ps1" set "OUTDATED=1"
if not exist "%HERE%connect-diagnostic.ps1" set "OUTDATED=1"
if not exist "%HERE%connect-version.txt" set "OUTDATED=1"
findstr /C:"Path.Combine" "%HERE%editor-launch.ps1" >nul 2>&1 || set "OUTDATED=1"
findstr /C:"@(Choose-Project" "%HERE%connect.ps1" >nul 2>&1 || set "OUTDATED=1"
findstr /C:"g git" "%HERE%connect.ps1" >nul 2>&1 || set "OUTDATED=1"
findstr /C:"Acquire-TunnelPort" "%HERE%git-mode.ps1" >nul 2>&1 || set "OUTDATED=1"
set "EXPECT_VER="
if exist "%HERE%connect-version.txt" (
    for /f "usebackq delims=" %%V in ("%HERE%connect-version.txt") do set "EXPECT_VER=%%V"
)
if not defined EXPECT_VER set "OUTDATED=1"
if defined EXPECT_VER findstr /C:"ConnectVersion = '!EXPECT_VER!'" "%HERE%connect.ps1" >nul 2>&1 || set "OUTDATED=1"

if "%OUTDATED%"=="1" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; $sid=$env:CLAUDE_CONNECT_RUN_ID; if (-not $sid) { $sid='-' }; $here='%HERE%'; $line=('[{0}] [ERROR] [{1}] FAIL OUTDATED_SCRIPTS: folder incomplete or mismatched version here={2}' -f $ts, $sid, $here); [IO.File]::AppendAllText($f, $line+[Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch {}" 2>nul
    echo.
    echo  [X] OUTDATED scripts in this folder.
    echo      Project select may fail with: Join-Path ChildPath
    echo      Need ALL of: connect-ui.ps1, connect-diagnostic.ps1, editor-launch.ps1 ^(Path.Combine^),
    echo                  git-mode.ps1, cursor-auth-laptop.ps1, connect-version.txt,
    echo                  connect.ps1 with @(Choose-Project^)[-1]
    echo.
    echo  Fix: run connect.bat from:
    echo    %USERPROFILE%\Desktop\Claude-Connect\connect.bat
    echo.
    echo  This folder: %HERE%
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%HERE%connect.ps1" %*
if %errorlevel% neq 0 pause
