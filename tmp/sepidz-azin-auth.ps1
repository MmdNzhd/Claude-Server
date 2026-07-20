$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'sepidz@192.168.250.70'
$cfg = Get-Content 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1' -Raw
if ($cfg -notmatch "SepidzSudoPassword\s*=\s*'([^']+)'") { throw 'no pw' }
$pwJson = ConvertTo-Json $Matches[1]
$bash = @'
#!/bin/bash
set +e
echo "=== auth log azin/grep users today ==="
grep -iE 'azin|azeen|اذین' /var/log/claude-auth.log 2>/dev/null | tail -20
echo "=== auth log last 40 lines ==="
tail -40 /var/log/claude-auth.log
echo "=== activity last 30 ==="
tail -30 /var/log/claude-activity.jsonl 2>/dev/null
echo "=== sshd accepted recent (auth.log) ==="
grep -E 'Accepted|Invalid user' /var/log/auth.log 2>/dev/null | tail -40
echo "=== reverse tunnels ss ==="
ss -tlnp 2>/dev/null | grep -E '210|220' | head -40
echo "=== nimaz recent files ==="
ls -lt /home/nimaz/.claude/ 2>/dev/null
stat /home/nimaz/.claude/.credentials.json /home/nimaz/.claude/settings.json 2>/dev/null
ls -lt /home/nimaz/mounts 2>/dev/null | head -15
ls -lt /home/nimaz/.cursor 2>/dev/null | head -10
'@
$sh = Join-Path $env:TEMP 'sepidz-azin-auth.sh'
[IO.File]::WriteAllText($sh, ($bash -replace "`r`n","`n"))
scp -o ControlMaster=no -i $key -o BatchMode=yes -q $sh "${target}:/tmp/sepidz-azin-auth.sh" | Out-Null
$o = Join-Path $env:TEMP 'sepidz-auth.out'
$e = Join-Path $env:TEMP 'sepidz-auth.err'
$args = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=20',$target,"printf '%s\n' $pwJson | sudo -S -p '' bash /tmp/sepidz-azin-auth.sh")
Remove-Item $o,$e -EA SilentlyContinue
$p = Start-Process ssh -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
if (-not $p.WaitForExit(45000)) { try{$p.Kill()}catch{}; Write-Output TIMEOUT; exit 4 }
Get-Content $o -Raw
