$ErrorActionPreference='Stop'
. 'D:\Smart\Claude-Code-Server\publish\Get-DeployCredentials.ps1'
$pwB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-SepidzSudoPassword)))
$remote = @'
#!/bin/bash
PW=$(echo __PWB64__ | base64 -d)
S(){ printf '%s\n' "$PW" | sudo -S -p '' "$@"; }
f=/home/hosseinb/.claude/logs/.connect-buf-5224.tmp
echo BYTES=$(S wc -c < "$f")
echo === HEAD 30 ===
S head -n 30 "$f"
echo === TAIL 80 ===
S tail -n 80 "$f"
echo === KEYWORD COUNTS ===
for k in ERROR WARN FAIL failed UNHANDLED timeout auth mount Update version SSH STEP; do
  c=$(S grep -c "$k" "$f" 2>/dev/null || echo 0)
  echo "$k=$c"
done
echo === SAMPLE LINES with fail/error/warn case insensitive ===
S grep -iE 'error|warn|fail|timeout|denied|unhandled|cannot|unable' "$f" 2>/dev/null | tail -n 60
echo === FARZADB PROC MOUNTS ===
S grep farzadb /proc/mounts || true
echo === ALL SSHFS ===
S grep sshfs /proc/mounts || true
'@
$remote=$remote.Replace('__PWB64__',$pwB64) -replace "`r",''
$b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out=Join-Path $env:TEMP 'sep-bt.out'
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=15','sepidz@192.168.250.70',("echo $b64 | base64 -d >/tmp/bt.sh && bash /tmp/bt.sh")) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
if(-not $p.WaitForExit(120000)){try{$p.Kill()}catch{}; throw 'TIMEOUT'}
Write-Host ((Get-Content $out -Raw -ErrorAction SilentlyContinue)+'')
