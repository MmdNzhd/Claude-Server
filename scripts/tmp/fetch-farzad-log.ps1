$ErrorActionPreference = 'Stop'
$out = 'D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log'
ssh -n -o BatchMode=yes -o ConnectTimeout=20 -o IdentityAgent=none sepidz@192.168.250.70 "echo 'sepidz@Admin' | sudo -S -p '' cp -f /home/farzadb/.claude/logs/connect-20260719.log /tmp/farzad-connect-20260719.log; echo 'sepidz@Admin' | sudo -S -p '' chmod 644 /tmp/farzad-connect-20260719.log; echo 'sepidz@Admin' | sudo -S -p '' chown sepidz:sepidz /tmp/farzad-connect-20260719.log; wc -c /tmp/farzad-connect-20260719.log"
scp -o BatchMode=yes -o ConnectTimeout=20 -o IdentityAgent=none sepidz@192.168.250.70:/tmp/farzad-connect-20260719.log $out
Write-Output "saved=$out size=$((Get-Item $out).Length)"
