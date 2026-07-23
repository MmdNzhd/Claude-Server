@echo off
REM publish-sepidz.bat - Sepidz client ZIP only (bat package; no EXE; no server deploy by default)
setlocal
set "FROZEN=%~dp0SEPIDZ_PUBLISH_FROZEN"
set "ALLOW=0"
echo.%*|find /I "-ForceUnfreeze" >nul && set "ALLOW=1"
if exist "%FROZEN%" if "%ALLOW%"=="0" (
  echo.
  echo Sepidz client publish/deploy is FROZEN.
  echo Marker: publish\SEPIDZ_PUBLISH_FROZEN
  echo To unfreeze: delete that file and pass -ForceUnfreeze
  echo.
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" -SepidzOnly -NoExe -SkipServerDeploy %*
pause
