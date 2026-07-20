$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
cat >/tmp/fzv.sh <<'INNER'
#!/bin/bash
echo "=== LIVE BUNDLE ==="
cat /usr/local/share/claude-client/connect-version.txt
ls -la /usr/local/share/claude-client/connect-version.txt /usr/local/share/claude-client/windows/connect-version.txt 2>/dev/null
echo "=== FARZADB CONF ==="
cat /home/farzadb/.claude-connect.conf
echo "=== FARZAD TUNNEL ==="
port=$(grep ^TUNNEL_PORT= /home/farzadb/.claude-connect.conf|cut -d= -f2|tr -d '\r')
echo port=$port
ss -tln | grep -E ":$port |:21006 " || echo no_listen
echo "=== FARZAD CONNECT LOGS / CURSOR HINTS ==="
ls -lah /home/farzadb/.claude/logs 2>/dev/null || echo no_logs
# any version string in home
grep -r "2026071\|ConnectVersion\|CONNECT_VERSION" /home/farzadb/.claude 2>/dev/null | head -20 || true
echo "=== UPDATE BUNDLE MANIFEST ==="
ls -la /usr/local/share/claude-client/ | head -40
head -5 /usr/local/share/claude-client/connect.bat 2>/dev/null || head -5 /usr/local/share/claude-client/windows/connect.bat 2>/dev/null
grep -n "ConnectVersion\|20260719" /usr/local/share/claude-client/windows/connect.ps1 2>/dev/null | head -5
grep -n "ConnectVersion\|20260719" /usr/local/share/claude-client/connect.ps1 2>/dev/null | head -5
INNER
printf '%s\n' "$PW" | sudo -S -p '' bash /tmp/fzv.sh
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'fzv.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/fzv0.sh && bash /tmp/fzv0.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(90000)
Get-Content $out -Raw
