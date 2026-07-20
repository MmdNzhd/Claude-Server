$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'sepidz@192.168.250.70'
$cfg = Get-Content 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1' -Raw
if ($cfg -notmatch "SepidzSudoPassword\s*=\s*'([^']+)'") { throw 'no pw' }
$pwJson = ConvertTo-Json $Matches[1]

$bash = @'
#!/bin/bash
set +e
echo HOST=$(hostname) DATE=$(date -Is)
echo "=== homes ==="
ls /home
echo "=== per-user .claude/logs (no find into mounts) ==="
for u in /home/*; do
  name=$(basename "$u")
  logdir="$u/.claude/logs"
  if [ -d "$logdir" ]; then
    echo "## $name"
    ls -lt "$logdir"/connect-*.log 2>/dev/null | head -3
    ls -lt "$logdir"/laptop-ssh* 2>/dev/null | head -2
  else
    echo "## $name NO_LOGDIR"
  fi
done
echo "=== connect.conf ==="
for u in /home/*; do
  f="$u/.claude-connect.conf"
  [ -f "$f" ] && { echo "---- $(basename "$u") ----"; cat "$f"; }
done
echo "=== LAPTOP_USER mentions azin ==="
for u in /home/*; do
  logdir="$u/.claude/logs"
  [ -d "$logdir" ] || continue
  for f in "$logdir"/connect-*.log; do
    [ -f "$f" ] || continue
    if grep -qiE 'azin|azeen|اذین|LAPTOP_USER' "$f" 2>/dev/null; then
      hits=$(grep -iE 'azin|azeen|اذین|LAPTOP_USER=' "$f" 2>/dev/null | head -5)
      if echo "$hits" | grep -qiE 'azin|azeen|اذین'; then
        echo "HIT $(basename "$u") $f"
        echo "$hits"
      fi
    fi
  done
done
echo "=== latest summary all users ==="
for u in /home/*; do
  name=$(basename "$u")
  latest=$(ls -t "$u"/.claude/logs/connect-*.log 2>/dev/null | head -1)
  [ -n "$latest" ] || continue
  echo "USER=$name FILE=$latest MTIME=$(stat -c %y "$latest" 2>/dev/null | cut -d. -f1)"
  grep -E 'SERVER_USER|LAPTOP_USER|VERDICT_|SESSION_STATUS|CLIENT_VERSION|CURSOR_NOT|Partial auth|tokens_only|VERDICT_CODE|VERDICT_SUMMARY' "$latest" 2>/dev/null | head -30
  echo "---"
done
'@
$sh = Join-Path $env:TEMP 'sepidz-azin-list.sh'
[IO.File]::WriteAllText($sh, ($bash -replace "`r`n","`n"))
scp -o ControlMaster=no -i $key -o BatchMode=yes -o ConnectTimeout=15 -q $sh "${target}:/tmp/sepidz-azin-list.sh" | Out-Null

$o2 = Join-Path $env:TEMP 'sepidz-list.out'
$e2 = Join-Path $env:TEMP 'sepidz-list.err'
$args2 = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=20',$target,"printf '%s\n' $pwJson | sudo -S -p '' bash /tmp/sepidz-azin-list.sh")
Remove-Item $o2,$e2 -EA SilentlyContinue
$p2 = Start-Process -FilePath ssh -ArgumentList $args2 -NoNewWindow -PassThru -RedirectStandardOutput $o2 -RedirectStandardError $e2
if (-not $p2.WaitForExit(60000)) { try { $p2.Kill() } catch {}; Write-Output 'TIMEOUT'; Get-Content $e2 -EA 0; exit 4 }
Write-Output "exit=$($p2.ExitCode)"
Get-Content $o2 -Raw -EA 0
$err = Get-Content $e2 -Raw -EA 0
if ($err) { Write-Output '---stderr---'; $err }
