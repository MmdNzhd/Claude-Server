@echo off
setlocal
REM Canonical day-to-day client deploy: scripts + bump version, KEEP server EXE.
REM Does NOT rebuild Claude-Connect.exe. Does NOT run laptop update.
REM Full EXE rebuild: publish.bat
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-scripts-only.ps1" %*
set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" (
  echo.
  echo DEPLOY FAILED exit=%EC%
  exit /b %EC%
)
exit /b 0
