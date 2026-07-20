$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'sepidz@192.168.250.70'
$cfg = Get-Content 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1' -Raw
if ($cfg -notmatch "SepidzSudoPassword\s*=\s*'([^']+)'") { throw 'no pw' }
$pwJson = ConvertTo-Json $Matches[1]

$bash = @'
#!/bin/bash
set +e
U=hosseinm
echo "=== HOST $(hostname) $(date -Is) ==="
echo "=== conf ==="
cat /home/$U/.claude-connect.conf 2>/dev/null || echo NO_CONF
echo "=== tunnel ports ==="
ss -tlnp 2>/dev/null | grep -E '210|220' || true
echo "=== conf TUNNEL ==="
PORT=$(grep TUNNEL_PORT /home/$U/.claude-connect.conf 2>/dev/null | cut -d= -f2)
echo "configured_port=$PORT"
if [ -n "$PORT" ]; then
  ss -tlnp 2>/dev/null | grep ":$PORT" || echo "port $PORT NOT listening"
  ss -tnp 2>/dev/null | grep ":$PORT" | head -8
fi
echo "=== sshd recent hosseinm ==="
grep -E "hosseinm|h\.mohammadi" /var/log/auth.log 2>/dev/null | tail -30
echo "=== last login ==="
last -n 5 $U 2>/dev/null
echo "=== .claude recent ==="
ls -lt /home/$U/.claude/ 2>/dev/null | head -15
ls -lt /home/$U/.claude/logs/ 2>/dev/null | head -10
echo "=== mounts ==="
ls -la /home/$U/mounts 2>/dev/null | head -20
mount | grep "/home/$U/mounts" | head -10
echo "=== cursor state ==="
ls -lt /home/$U/.config/Cursor/User/globalStorage/state.vscdb 2>/dev/null
stat /home/$U/.config/Cursor/User/globalStorage/state.vscdb 2>/dev/null | head -8
echo "=== machineid ==="
MID=/home/$U/.config/Cursor/machineid
if [ -f "$MID" ]; then
  echo "user_machineid=$(cat "$MID")"
  echo "golden_machineid=$(cat /etc/cursor-auth/golden/machine-id.txt 2>/dev/null)"
  if [ "$(cat "$MID" 2>/dev/null)" = "$(cat /etc/cursor-auth/golden/machine-id.txt 2>/dev/null)" ]; then echo machineid=MATCH; else echo machineid=MISMATCH; fi
else
  echo NO_MACHINEID
fi
echo "=== processes ==="
ps -u $U -o pid,etime,cmd --sort=-etime 2>/dev/null | head -25
echo "=== claude-mount list ==="
sudo -u $U -H bash -lc 'claude-mount list 2>&1' | head -30
echo "=== recent connect logs on server (if any) ==="
ls -lt /home/$U/.claude/logs/connect-*.log 2>/dev/null | head -5
for f in $(ls -t /home/$U/.claude/logs/connect-*.log 2>/dev/null | head -1); do
  echo "FILE=$f"
  grep -E "VERDICT_|SESSION_STATUS|ERROR|WARN|CURSOR_NOT|Partial|FAIL|SERVER_USER|CLIENT_VERSION" "$f" | tail -40
done
'@

$sh = Join-Path $env:TEMP 'sepidz-hosseinm.sh'
[IO.File]::WriteAllText($sh, ($bash -replace "`r`n","`n"))
scp -o ControlMaster=no -i $key -o BatchMode=yes -o ConnectTimeout=15 -q $sh "${target}:/tmp/sepidz-hosseinm.sh" | Out-Null
$o = Join-Path $env:TEMP 'sepidz-hosseinm.out'
$e = Join-Path $env:TEMP 'sepidz-hosseinm.err'
$args = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=25',$target,"printf '%s\n' $pwJson | sudo -S -p '' bash /tmp/sepidz-hosseinm.sh")
Remove-Item $o,$e -EA SilentlyContinue
$p = Start-Process ssh -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
if (-not $p.WaitForExit(60000)) { try{$p.Kill()}catch{}; Write-Output TIMEOUT; Get-Content $e -EA 0; exit 4 }
Write-Output "exit=$($p.ExitCode)"
Get-Content $o -Raw -EA 0
$err = Get-Content $e -Raw -EA 0
if ($err) { Write-Output '---stderr---'; ($err -replace [regex]::Escape($Matches[1]),'***') }
