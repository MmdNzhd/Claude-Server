@echo off
REM connect.bat - double-click launcher for Windows.
REM Runs connect.ps1 (in the same folder) without changing the system ExecutionPolicy.
REM
REM First run : asks for server username + project path, sets up SSH keys (server password once).
REM Every run : opens reverse tunnel, mounts the project on the server, opens VSCode.

setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0connect.ps1" %*
if %ERRORLEVEL% neq 0 (
    echo.
    pause
) else (
    timeout /t 3 /nobreak >nul 2>&1
)
