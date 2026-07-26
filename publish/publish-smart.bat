@echo off
REM publish-smart.bat - Smart client only (folder + ZIP + EXE + server deploy).
REM Syncs Desktop\Claude-Connect and writes Desktop\Claude-Connect-VERSION.exe

setlocal EnableExtensions
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" -SmartOnly %*
set "PUB_EC=%ERRORLEVEL%"

echo.
if not "%PUB_EC%"=="0" (
  echo   [X] Publish exited with code %PUB_EC%
  echo.
  pause
  exit /b %PUB_EC%
)

set "DESK=%USERPROFILE%\Desktop"
set "FOLDER=%DESK%\Claude-Connect"
set "VER="
if exist "%FOLDER%\connect-version.txt" (
  set /p VER=<"%FOLDER%\connect-version.txt"
)
set "EXE_VER=%DESK%\Claude-Connect-%VER%.exe"

echo   ============================================
echo   DEPLOY FOLDER:  %FOLDER%
if defined VER echo   VERSION:        %VER%
echo   RUN:            %FOLDER%\connect.bat
if exist "%EXE_VER%" echo   EXE:            %EXE_VER%
echo   ============================================
echo.

if exist "%FOLDER%\connect.bat" (
  explorer.exe /select,"%FOLDER%\connect.bat"
) else if exist "%EXE_VER%" (
  explorer.exe /select,"%EXE_VER%"
)

pause
exit /b 0
