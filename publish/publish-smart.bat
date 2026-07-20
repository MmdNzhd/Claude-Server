@echo off
REM publish-smart.bat - Smart client ZIP + deploy to Smart server only
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" -SmartOnly %*
pause
