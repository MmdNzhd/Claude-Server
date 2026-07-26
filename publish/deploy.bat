@echo off
REM Canonical day-to-day deploy (alias → deploy-scripts-only.bat).
REM Bump + deploy-gate tests + stage + Smart upload + TEMP cleanup.
REM Does NOT rebuild EXE. Full EXE rebuild: publish.bat
cd /d "%~dp0"
call "%~dp0deploy-scripts-only.bat" %*
exit /b %ERRORLEVEL%
