@echo off
REM publish.bat - build Smart+Sepidz client packages, sync Desktop\Claude-Connect, make versioned EXE.
REM
REM After success you have:
REM   Desktop\Claude-Connect\              <- ONE deploy folder (run connect.bat)
REM   Desktop\Claude-Connect-VERSION.exe   <- optional cold-install EXE (version in name)
REM   Desktop\claude-publish\              <- build output / ZIP / server bundle source
REM
REM Daily use: Desktop\Claude-Connect\connect.bat
REM Do NOT keep unversioned Desktop\Claude-Connect.exe (removed by publish).

setlocal EnableExtensions
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" %*
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
set "EXE_PUB=%DESK%\claude-publish\Claude-Connect.exe"

echo   ============================================
echo   DEPLOY FOLDER:  %FOLDER%
if defined VER echo   VERSION:        %VER%
if exist "%FOLDER%\connect.bat" (
  echo   RUN:            %FOLDER%\connect.bat
) else (
  echo   RUN:            connect.bat missing - publish may have failed
)
if exist "%EXE_VER%" (
  echo   EXE ^(versioned^): %EXE_VER%
) else if exist "%EXE_PUB%" (
  echo   EXE ^(publish^):  %EXE_PUB%
) else (
  echo   EXE:            not built ^(-NoExe or build failed^)
)
echo   ============================================
echo.

if exist "%FOLDER%\connect.bat" (
  explorer.exe /select,"%FOLDER%\connect.bat"
) else if exist "%EXE_VER%" (
  explorer.exe /select,"%EXE_VER%"
)

pause
exit /b 0
