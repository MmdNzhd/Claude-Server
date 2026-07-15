@echo off
REM Admin: deploy laptop-exec + client auto-update bundle to ALL server users
echo Deploying to claude-server (sudo password required once)...
ssh -t claude-server "bash ~/deploy-all-now.sh"
pause
