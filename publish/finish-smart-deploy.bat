@echo off
REM finish-smart-deploy.bat - install auto-update bundle on Smart server only
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0finish-smart-deploy.ps1"
pause
