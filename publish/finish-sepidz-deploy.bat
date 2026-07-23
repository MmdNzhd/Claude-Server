@echo off
REM finish-sepidz-deploy.bat - install auto-update bundle on Sepidz server only
setlocal
set "FROZEN=%~dp0SEPIDZ_PUBLISH_FROZEN"
set "ALLOW=0"
echo.%*|find /I "-ForceUnfreeze" >nul && set "ALLOW=1"
if exist "%FROZEN%" if "%ALLOW%"=="0" (
  echo.
  echo Sepidz server deploy is FROZEN.
  echo Marker: publish\SEPIDZ_PUBLISH_FROZEN
  echo To unfreeze: delete that file and pass -ForceUnfreeze
  echo.
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0finish-sepidz-deploy.ps1" %*
pause
