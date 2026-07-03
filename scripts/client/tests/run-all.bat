@echo off
REM run-all.bat — run all client connect regression tests
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-all.ps1"
if %errorlevel% neq 0 pause
