@echo off
REM connect.bat - double-click launcher for Windows.
setlocal
set "HERE=%~dp0"
title Claude Connect

set "OUTDATED=0"
if not exist "%HERE%connect.ps1" set "OUTDATED=1"
if not exist "%HERE%connect-ui.ps1" set "OUTDATED=1"
if not exist "%HERE%editor-launch.ps1" set "OUTDATED=1"
if not exist "%HERE%git-mode.ps1" set "OUTDATED=1"
if not exist "%HERE%cursor-auth-laptop.ps1" set "OUTDATED=1"
findstr /C:"Path.Combine" "%HERE%editor-launch.ps1" >nul 2>&1 || set "OUTDATED=1"
findstr /C:"@(Choose-Project" "%HERE%connect.ps1" >nul 2>&1 || set "OUTDATED=1"
findstr /C:"g git" "%HERE%connect.ps1" >nul 2>&1 || set "OUTDATED=1"
findstr /C:"ConnectVersion = '20260703.12'" "%HERE%connect.ps1" >nul 2>&1 || set "OUTDATED=1"
findstr /C:"Acquire-TunnelPort" "%HERE%git-mode.ps1" >nul 2>&1 || set "OUTDATED=1"

if "%OUTDATED%"=="1" (
    echo.
    echo  [X] OUTDATED scripts in this folder.
    echo      Project select may fail with: Join-Path ChildPath
    echo      Need ALL of: connect-ui.ps1, editor-launch.ps1 ^(Path.Combine^), git-mode.ps1,
    echo                  cursor-auth-laptop.ps1, connect.ps1 v20260703.12 with @(Choose-Project^)[-1]
    echo.
    echo  Fix: run connect.bat from:
    echo    %USERPROFILE%\Desktop\Claude-Connect\connect.bat
    echo.
    echo  This folder: %HERE%
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%HERE%connect.ps1" %*
if %errorlevel% neq 0 pause
