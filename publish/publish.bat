@echo off
REM publish.bat - double-click to build the client distribution package.
REM Creates dist\claude-code-client-<date>\ and a ZIP next to it.
REM Pass -NoZip as argument to skip ZIP creation.

setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" %*
pause
