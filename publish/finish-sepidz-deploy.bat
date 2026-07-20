@echo off
REM finish-sepidz-deploy.bat - install auto-update bundle on Sepidz server only
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0finish-sepidz-deploy.ps1"
pause
