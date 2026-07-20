$ErrorActionPreference='Continue'
$idx = 'echo ''sepidz@Admin'' | sudo -S -p '''' bash -lc ''for u in alit aminb designer farzadb hosseinb hosseinm nimaz sepidz smart zahrak; do f=/home/$u/.claude/logs/connect-20260719.log; if [ -f $f ]; then echo USER=$u SIZE=$(stat -c%s $f) LINES=$(wc -l $f | awk "{print \$1}") MTIME=$(stat -c%Y $f); else echo USER=$u NO_LOG; fi; done'''
Write-Output '=== INDEX ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=20 -o IdentityAgent=none sepidz@192.168.250.70 $idx

Write-Output '=== FARZAD CONF ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=10 -o IdentityAgent=none sepidz@192.168.250.70 "echo 'sepidz@Admin' | sudo -S -p '' cat /home/farzadb/.claude-connect.conf"

Write-Output '=== COPY ==='
ssh -n -o BatchMode=yes -o ConnectTimeout=15 -o IdentityAgent=none sepidz@192.168.250.70 "echo 'sepidz@Admin' | sudo -S -p '' cp -f /home/farzadb/.claude/logs/connect-20260719.log /tmp/farzad-connect-20260719.log; echo 'sepidz@Admin' | sudo -S -p '' chmod 644 /tmp/farzad-connect-20260719.log; echo 'sepidz@Admin' | sudo -S -p '' chown sepidz:sepidz /tmp/farzad-connect-20260719.log; wc -c /tmp/farzad-connect-20260719.log"
scp -o BatchMode=yes -o ConnectTimeout=15 -o IdentityAgent=none sepidz@192.168.250.70:/tmp/farzad-connect-20260719.log "D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log"
Write-Output ("saved=" + (Get-Item 'D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log').Length)
