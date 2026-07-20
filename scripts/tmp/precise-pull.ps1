$ErrorActionPreference='Continue'
Write-Output '=== VER ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 "cat /usr/local/share/claude-client/connect-version.txt"
Write-Output '=== CONF ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 "echo 'sepidz@Admin' | sudo -S -p '' cat /home/farzadb/.claude-connect.conf; echo '---'; echo 'sepidz@Admin' | sudo -S -p '' ls -la /home/farzadb/.claude/logs/; echo 'sepidz@Admin' | sudo -S -p '' stat -c '%y %s' /home/farzadb/.claude/logs/connect-20260719.log"
Write-Output '=== COPY ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=15 sepidz@192.168.250.70 "echo 'sepidz@Admin' | sudo -S -p '' cp -f /home/farzadb/.claude/logs/connect-20260719.log /tmp/farzad-connect-20260719.log; echo 'sepidz@Admin' | sudo -S -p '' chmod 644 /tmp/farzad-connect-20260719.log; echo 'sepidz@Admin' | sudo -S -p '' chown sepidz:sepidz /tmp/farzad-connect-20260719.log; wc -c /tmp/farzad-connect-20260719.log"
scp -o BatchMode=yes -o ConnectTimeout=15 sepidz@192.168.250.70:/tmp/farzad-connect-20260719.log D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log
Write-Output ("saved=" + (Get-Item D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log).Length)

# Dump exact deployed key logic
Write-Output '=== DEPLOYED KEY LOGIC ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 "sed -n '1567,1590p' /usr/local/share/claude-client/connect.ps1"
Write-Output '=== DEPLOYED PUSHCONF HEAD ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 "sed -n '1025,1060p' /usr/local/share/claude-client/git-mode.ps1"
