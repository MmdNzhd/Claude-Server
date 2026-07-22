@echo off
REM publish.bat - double-click to build the client distribution package.
REM Output (Desktop\claude-publish\):
REM   claude-code-client\     folder (dev/debug)
REM   claude-code-client.zip  ZIP (optional archive)
REM   Claude-Connect.exe      GIVE THIS TO USERS (also copied to Desktop\)
REM Pass -NoZip / -NoExe / -SkipServerDeploy as args to skip those steps.
REM
REM How others get updates after first install:
REM   They keep using Desktop\Claude-Connect\connect.bat (or re-run the EXE once).
REM   On each launch, client auto-pulls new files from the server bundle.
REM   You do NOT need to re-send bat/zip every version — publish + server deploy is enough.
REM   Re-send Claude-Connect.exe only for brand-new PCs / cold install.

setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" %*
set "PUB_EC=%ERRORLEVEL%"
echo.
set "EXE_DESK=%USERPROFILE%\Desktop\Claude-Connect.exe"
set "EXE_PUB=%USERPROFILE%\Desktop\claude-publish\Claude-Connect.exe"
if exist "%EXE_DESK%" (
  echo   ============================================
  echo   GIVE TO USERS:  %EXE_DESK%
  echo   Also at:        %EXE_PUB%
  echo   ============================================
  echo.
  echo   Opening Explorer on the EXE so you can see/copy it...
  explorer.exe /select,"%EXE_DESK%"
) else if exist "%EXE_PUB%" (
  echo   ============================================
  echo   GIVE TO USERS:  %EXE_PUB%
  echo   ============================================
  echo.
  echo   Opening Explorer on the EXE so you can see/copy it...
  explorer.exe /select,"%EXE_PUB%"
) else (
  echo   EXE: not built (passed -NoExe, or Sepidz-only, or build failed^)
)
echo.
if not "%PUB_EC%"=="0" (
  echo   Publish exited with code %PUB_EC%
)
pause
