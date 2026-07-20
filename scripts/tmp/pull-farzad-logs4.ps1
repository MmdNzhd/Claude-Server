$ErrorActionPreference = 'Continue'
Write-Output '=== T1 sepidz whoami sudo ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=12 -o IdentityAgent=none sepidz@192.168.250.70 "echo 'sepidz@Admin' | sudo -S -p '' whoami; hostname; cat /usr/local/share/claude-client/connect-version.txt"
Write-Output '=== T2 list logs ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=12 -o IdentityAgent=none sepidz@192.168.250.70 "echo 'sepidz@Admin' | sudo -S -p '' ls -lah /home/farzadb/.claude/logs/"
Write-Output '=== T3 conf ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=12 -o IdentityAgent=none sepidz@192.168.250.70 "echo 'sepidz@Admin' | sudo -S -p '' cat /home/farzadb/.claude-connect.conf"
Write-Output '=== T4 find ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=12 -o IdentityAgent=none sepidz@192.168.250.70 "echo 'sepidz@Admin' | sudo -S -p '' find /home/farzadb/.claude -name 'connect*' -type f -printf '%T+ %s %p\n' 2>/dev/null | sort"
Write-Output '=== DONE list phase ==='
