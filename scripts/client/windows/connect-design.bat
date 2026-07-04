@echo off
REM connect-design.bat - double-click launcher for Claude Design (Windows).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0connect-design.ps1" %*
if %errorlevel% neq 0 pause
