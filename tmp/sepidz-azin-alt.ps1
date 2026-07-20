$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'sepidz@192.168.250.70'
$cfg = Get-Content 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1' -Raw
if ($cfg -notmatch "SepidzSudoPassword\s*=\s*'([^']+)'") { throw 'no pw' }
$pwJson = ConvertTo-Json $Matches[1]
$bash = @'
#!/bin/bash
set +e
echo "=== /var/log claude/cursor ==="
ls -lt /var/log/claude* /var/log/cursor* 2>/dev/null | head -20
echo "=== /tmp connect ==="
ls -lt /tmp/claude* /tmp/connect* /tmp/*claude* 2>/dev/null | head -20
echo "=== designer home top ==="
ls -la /home/designer 2>/dev/null | head -30
ls -la /home/designer/.claude 2>/dev/null | head -20
echo "=== any .claude under home maxdepth 3 (no mounts) ==="
for u in /home/*; do
  echo "-- $(basename "$u") --"
  ls -la "$u/.claude" 2>/dev/null | head -10
  ls -la "$u/.local/share/claude"* 2>/dev/null | head -5
done
echo "=== lastlog / w ==="
who 2>/dev/null; last -n 15 2>/dev/null | head -20
'@
$sh = Join-Path $env:TEMP 'sepidz-azin-alt.sh'
[IO.File]::WriteAllText($sh, ($bash -replace "`r`n","`n"))
scp -o ControlMaster=no -i $key -o BatchMode=yes -q $sh "${target}:/tmp/sepidz-azin-alt.sh" | Out-Null
$o = Join-Path $env:TEMP 'sepidz-alt.out'
$e = Join-Path $env:TEMP 'sepidz-alt.err'
$args = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=20',$target,"printf '%s\n' $pwJson | sudo -S -p '' bash /tmp/sepidz-azin-alt.sh")
Remove-Item $o,$e -EA SilentlyContinue
$p = Start-Process ssh -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
if (-not $p.WaitForExit(45000)) { try{$p.Kill()}catch{}; Write-Output TIMEOUT; exit 4 }
Get-Content $o -Raw
