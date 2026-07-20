$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
printf '%s\n' "$PW" | sudo -S -p '' bash -c '
echo "=== farzadb claude logs ==="
ls -la /home/farzadb/.claude/logs/ 2>/dev/null | tail -20
echo "=== hosseinb recent connect log lines ==="
lg=$(ls -t /home/hosseinb/.claude/logs/connect-*.log 2>/dev/null | head -1)
echo "file=$lg"
[ -n "$lg" ] && wc -l "$lg" && head -30 "$lg" && echo "..." && tail -20 "$lg"
echo "=== laptop-side: what clients write ==="
# show if any client logs mention phases
'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'cl.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','sepidz@192.168.250.70',("echo $b64 | base64 -d | bash")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(60000)
Get-Content $out -Raw
