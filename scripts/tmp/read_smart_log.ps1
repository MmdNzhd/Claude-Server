$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
printf '%s\n' "$PW" | sudo -S -p '' bash -c '
U=smart
DAY=$(date +%Y%m%d)
LG=/home/$U/.claude/logs/connect-$DAY.log
echo "=== META ==="
echo USER=$U DAY=$DAY
ls -la /home/$U/.claude/logs/ 2>/dev/null | tail -20
echo "BYTES=$(wc -c <"$LG" 2>/dev/null || echo 0)"
echo "LINES=$(wc -l <"$LG" 2>/dev/null || echo 0)"
echo
echo "=== FIRST 80 ==="
head -80 "$LG" 2>/dev/null
echo
echo "=== MARKERS (session/update/false/git/perf/tunnel) ==="
grep -nE "session start|BOOTSTRAP|UPDATE:|DECISION:|False|GIT|git_mode|PERF|TUNNEL|Connection dropped|recover|MOUNT|LAUNCH|session end|EXIT|SSH_STAGE|watermark|STEP end|STEP begin" "$LG" 2>/dev/null | head -120
echo
echo "=== PERF / TIMING lines ==="
grep -nE "PERF|ms=|STEP end|elapsed|session_open" "$LG" 2>/dev/null | tail -80
echo
echo "=== LAST 60 ==="
tail -60 "$LG" 2>/dev/null
echo
echo "=== CONF ==="
cat /home/$U/.claude-connect.conf 2>/dev/null
echo
echo "=== git.conf if any on server mounts? ==="
# laptop git.conf is local - show server ACTIVE
'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'smartlog.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=20','sepidz@192.168.250.70',("echo $b64 | base64 -d | bash")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(120000)
Get-Content $out -Raw
