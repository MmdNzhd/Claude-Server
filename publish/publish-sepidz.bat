@echo off
REM publish-sepidz.bat - Sepidz client ZIP + deploy to Sepidz server only
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" -SepidzOnly %*
pause
