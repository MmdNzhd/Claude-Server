@echo off
REM connect.bat - double-click launcher for Windows.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0connect.ps1" %*
if %errorlevel% neq 0 pause
