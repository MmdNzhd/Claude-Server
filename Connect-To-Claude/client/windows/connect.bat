@echo off
REM connect.bat - double-click launcher for Windows.
REM Runs connect.ps1 (in the same folder) without changing the system ExecutionPolicy.
REM
REM First run : asks for server username + project path, sets up SSH keys (server password once).
REM Every run : opens reverse tunnel, mounts the project on the server, opens VSCode.
REM
REM To reconfigure username/project path: run "connect.bat -Setup"

setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0connect.ps1" %*
REM auto-close: VSCode is open; closing this window is fine (it does NOT close VSCode
REM or the tunnel - the tunnel rides VSCode's own connection now).
timeout /t 4 /nobreak >nul 2>&1
