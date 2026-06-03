@echo off
REM connect.bat - double-click launcher for Windows.
start "" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0connect.ps1" %*
