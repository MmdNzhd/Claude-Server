$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
for f in /home/hosseinb/.claude/logs/.connect-buf-33008.tmp /home/hosseinb/.claude/logs/.connect-buf-33376.tmp; do
  echo "#### $f ####"
  S head -n 20 "$f"
  echo ----
  S grep -iE '\[ERROR\]|\[WARN\]|STATUS_|auth|AUTH_|mount fail|failed|UNHANDLED|Update source|version' "$f" | tail -n 40
  echo ---- tail ----
  S tail -n 25 "$f"
  echo
done
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'sep-bn.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/bn.sh && bash /tmp/bn.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
[void]$p.WaitForExit(90000)
Write-Host ((Get-Content $out -Raw -ErrorAction SilentlyContinue)+'')
