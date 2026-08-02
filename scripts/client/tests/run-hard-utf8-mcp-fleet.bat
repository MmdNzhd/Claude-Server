@echo off
REM Hard UTF-8 / MCP / pipeline / live MCP / optional Smart fleet verify
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-hard-utf8-mcp-fleet.ps1" %*
set ERR=%ERRORLEVEL%
if %ERR% neq 0 (
  echo.
  echo HARD UTF-8 / MCP FLEET FAILED exit=%ERR%
  pause
)
exit /b %ERR%
