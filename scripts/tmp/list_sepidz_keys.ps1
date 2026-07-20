$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote=@'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
printf '%s\n' "$PW" | sudo -S -p '' bash -c '
echo "=== home users with keys ==="
for d in /home/*; do
  u=$(basename "$d")
  [ -f "$d/.ssh/authorized_keys" ] || continue
  n=$(grep -cE "^(ssh-|ecdsa-)" "$d/.ssh/authorized_keys" 2>/dev/null || echo 0)
  echo "$u keys=$n"
done
echo "=== sepidz keys fingerprints ==="
ssh-keygen -lf /home/sepidz/.ssh/authorized_keys 2>/dev/null || true
'
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'lk.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d | bash")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(60000)
Get-Content $out -Raw
