$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'sepidz@192.168.250.70'
$cfg = Get-Content 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1' -Raw
if ($cfg -notmatch "SepidzSudoPassword\s*=\s*'([^']+)'") { throw 'no pw' }
$pwJson = ConvertTo-Json $Matches[1]
$bash = @'
#!/bin/bash
set +e
echo "=== Invalid user azin* ==="
grep -iE 'Invalid user|Failed password|azin|azeen|adin' /var/log/auth.log 2>/dev/null | tail -50
echo "=== journal ssh today azin ==="
journalctl -u ssh --since "7 days ago" 2>/dev/null | grep -iE 'azin|azeen|Invalid user' | tail -30
echo "=== nimaz reverse tunnel who ==="
ss -tnp | grep 21010 | head -10
ps -ef | grep -E 'sshd: nimaz|sshd:.*21010' | grep -v grep | head -10
'@
$sh = Join-Path $env:TEMP 'sepidz-azin-inv.sh'
[IO.File]::WriteAllText($sh, ($bash -replace "`r`n","`n"))
scp -o ControlMaster=no -i $key -o BatchMode=yes -q $sh "${target}:/tmp/sepidz-azin-inv.sh" | Out-Null
$o = Join-Path $env:TEMP 'sepidz-inv.out'
$e = Join-Path $env:TEMP 'sepidz-inv.err'
$args = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=20',$target,"printf '%s\n' $pwJson | sudo -S -p '' bash /tmp/sepidz-azin-inv.sh")
Remove-Item $o,$e -EA SilentlyContinue
$p = Start-Process ssh -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
if (-not $p.WaitForExit(45000)) { try{$p.Kill()}catch{}; Write-Output TIMEOUT; exit 4 }
Get-Content $o -Raw
