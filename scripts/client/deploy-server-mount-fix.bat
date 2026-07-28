@echo off
REM deploy-server-mount-fix.bat - admin only, run from repo scripts\client\
REM Published client ZIPs do NOT include server scripts.
setlocal
cd /d "%~dp0"
set SERVER=smart@192.168.210.240
set DEPLOY=claude-mount-deploy
set REPO=%~dp0..\.. 

echo.
echo   Deploy mount + automount fix to ALL server users
echo   Server: %SERVER%
echo   Repo:   %REPO%
echo.

where ssh >nul 2>&1 || (echo [X] ssh not found & pause & exit /b 1)
where scp >nul 2>&1 || (echo [X] scp not found & pause & exit /b 1)

if not exist "%REPO%\scripts\server\claude-mount.sh" (
    echo [X] scripts\server\claude-mount.sh not found
    echo     Run from repo: scripts\client\deploy-server-mount-fix.bat
    pause
    exit /b 1
)

echo   Uploading from repo...
ssh -o BatchMode=yes -o ConnectTimeout=15 %SERVER% "mkdir -p ~/%DEPLOY%"
scp -o BatchMode=yes -o ConnectTimeout=30 -q "%REPO%\scripts\server\claude-mount.sh" "%SERVER%:~/%DEPLOY%/"
scp -o BatchMode=yes -o ConnectTimeout=30 -q "%REPO%\scripts\server\claude-automount.sh" "%SERVER%:~/%DEPLOY%/"
scp -o BatchMode=yes -o ConnectTimeout=30 -q "%REPO%\scripts\server\claude-watchdog.sh" "%SERVER%:~/%DEPLOY%/"
scp -o BatchMode=yes -o ConnectTimeout=30 -q "%REPO%\scripts\server\claude-self-heal.sh" "%SERVER%:~/%DEPLOY%/"
scp -o BatchMode=yes -o ConnectTimeout=30 -q "%REPO%\scripts\server\claude-mount-reaper.sh" "%SERVER%:~/%DEPLOY%/"
scp -o BatchMode=yes -o ConnectTimeout=30 -q "%REPO%\scripts\server\claude-tunnel-reacquire.sh" "%SERVER%:~/%DEPLOY%/"
scp -o BatchMode=yes -o ConnectTimeout=30 -q "%REPO%\scripts\server\commands\deploy-mount-fix.sh" "%SERVER%:~/%DEPLOY%/deploy-mount-fix.sh"
echo   Upload ok.
echo.
echo   Running deploy via sudo-from-laptop (no interactive password)...
echo.

ssh -o BatchMode=yes -o ConnectTimeout=30 %SERVER% "chmod +x ~/%DEPLOY%/deploy-mount-fix.sh && sudo-from-laptop --smart -- bash ~/%DEPLOY%/deploy-mount-fix.sh"
echo.
if errorlevel 1 (
    echo   [X] Deploy failed.
) else (
    echo   Done - all users updated.
)
echo.
pause
