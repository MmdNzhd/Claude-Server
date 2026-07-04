@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync-desktop.ps1" %*
if errorlevel 1 pause
exit /b %errorlevel%
