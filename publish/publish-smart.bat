@echo off
REM publish-smart.bat - Smart client folder/ZIP/EXE + deploy to Smart server only
REM After success: Desktop\Claude-Connect.exe is what you give to users.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" -SmartOnly %*
echo.
set "EXE_DESK=%USERPROFILE%\Desktop\Claude-Connect.exe"
if exist "%EXE_DESK%" (
  echo   GIVE TO USERS: %EXE_DESK%
  explorer.exe /select,"%EXE_DESK%"
) else (
  echo   EXE: not built
)
echo.
pause
