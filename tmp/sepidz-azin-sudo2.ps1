$ErrorActionPreference = 'Continue'
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$target = 'sepidz@192.168.250.70'
$cfg = Get-Content 'D:\Smart\Claude-Code-Server\publish\sepidz-deploy.local.ps1' -Raw
if ($cfg -notmatch "SepidzSudoPassword\s*=\s*'([^']+)'") { throw 'no pw' }
$pw = $Matches[1]
$pwJson = ConvertTo-Json $pw  # quoted safely

# 1) quick sudo test with timeout via Start-Process + files (no ReadToEnd deadlock)
$o = Join-Path $env:TEMP 'sepidz-sudo.out'
$e = Join-Path $env:TEMP 'sepidz-sudo.err'
$i = Join-Path $env:TEMP 'sepidz-sudo.in'
Set-Content -Path $i -Value $pw -NoNewline
# Use bash on Windows? use PowerShell to pipe:
$args = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=12',$target,"printf '%s\n' $pwJson | sudo -S -p '' id -un")
Remove-Item $o,$e -EA SilentlyContinue
$p = Start-Process -FilePath ssh -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
if (-not $p.WaitForExit(25000)) { try { $p.Kill() } catch {}; Write-Output 'sudo_test=TIMEOUT'; Get-Content $e -EA 0; exit 2 }
Write-Output "sudo_test_exit=$($p.ExitCode)"
Write-Output "sudo_out=$(Get-Content $o -Raw -EA 0)"
Write-Output "sudo_err=$(Get-Content $e -Raw -EA 0)"

if ($p.ExitCode -ne 0) { exit 3 }

# 2) upload list script via scp, then sudo run it
$bash = @"
#!/bin/bash
echo HOST=`$(hostname)
echo "=== passwd azin-like ==="
getent passwd | grep -iE 'azin|azeen|azhin|adin|nima' || true
echo "=== connect logs 14d ==="
find /home -path '*/.claude/logs/connect-*.log' -mtime -14 -printf '%T+ %u %p %s\n' 2>/dev/null | sort -r | head -60
echo "=== diag 14d ==="
find /home -path '*/.claude/logs/laptop-ssh*' -mtime -14 -printf '%T+ %u %p %s\n' 2>/dev/null | sort -r | head -30
echo "=== connect.conf ==="
for d in /home/*; do
  f="`$d/.claude-connect.conf"
  if [ -f "`$f" ]; then
    echo "---- `$(basename "`$d") ----"
    cat "`$f"
  fi
done
echo "=== last connect summary ==="
for d in /home/*; do
  u=`$(basename "`$d")
  latest=`$(ls -t "`$d"/.claude/logs/connect-*.log 2>/dev/null | head -1)
  if [ -n "`$latest" ]; then
    echo "USER=`$u FILE=`$latest"
    grep -E 'SERVER_USER|LAPTOP_USER|VERDICT|SESSION_STATUS|CLIENT_VERSION|ERROR|FAIL|WARN|CURSOR_NOT|Partial auth|tokens_only' "`$latest" 2>/dev/null | head -50
    echo "---"
  fi
done
"@
# Use single-quoted here-string to avoid PS expansion of $()
$bash = @'
#!/bin/bash
echo HOST=$(hostname)
echo "=== passwd azin-like ==="
getent passwd | grep -iE "azin|azeen|azhin|adin|nima" || true
echo "=== connect logs 14d ==="
find /home -path "*/.claude/logs/connect-*.log" -mtime -14 -printf "%T+ %u %p %s\n" 2>/dev/null | sort -r | head -60
echo "=== diag 14d ==="
find /home -path "*/.claude/logs/laptop-ssh*" -mtime -14 -printf "%T+ %u %p %s\n" 2>/dev/null | sort -r | head -30
echo "=== connect.conf ==="
for d in /home/*; do
  f="$d/.claude-connect.conf"
  if [ -f "$f" ]; then
    echo "---- $(basename "$d") ----"
    cat "$f"
  fi
done
echo "=== last connect summary ==="
for d in /home/*; do
  u=$(basename "$d")
  latest=$(ls -t "$d"/.claude/logs/connect-*.log 2>/dev/null | head -1)
  if [ -n "$latest" ]; then
    echo "USER=$u FILE=$latest"
    grep -E "SERVER_USER|LAPTOP_USER|VERDICT|SESSION_STATUS|CLIENT_VERSION|ERROR|FAIL|WARN|CURSOR_NOT|Partial auth|tokens_only" "$latest" 2>/dev/null | head -50
    echo "---"
  fi
done
'@
$sh = Join-Path $env:TEMP 'sepidz-azin-list.sh'
[IO.File]::WriteAllText($sh, $bash.Replace("`r`n","`n"))
scp -o ControlMaster=no -i $key -o BatchMode=yes -o ConnectTimeout=15 -q $sh "${target}:/tmp/sepidz-azin-list.sh"
Write-Output "scp_exit=$LASTEXITCODE"

$o2 = Join-Path $env:TEMP 'sepidz-list.out'
$e2 = Join-Path $env:TEMP 'sepidz-list.err'
$args2 = @('-o','ControlMaster=no','-i',$key,'-o','BatchMode=yes','-o','ConnectTimeout=20',$target,"printf '%s\n' $pwJson | sudo -S -p '' bash /tmp/sepidz-azin-list.sh")
Remove-Item $o2,$e2 -EA SilentlyContinue
$p2 = Start-Process -FilePath ssh -ArgumentList $args2 -NoNewWindow -PassThru -RedirectStandardOutput $o2 -RedirectStandardError $e2
if (-not $p2.WaitForExit(90000)) { try { $p2.Kill() } catch {}; Write-Output 'list=TIMEOUT'; Get-Content $e2 -EA 0; exit 4 }
Write-Output "list_exit=$($p2.ExitCode)"
Get-Content $o2 -Raw -EA 0
$err = Get-Content $e2 -Raw -EA 0
if ($err) { Write-Output '---stderr---'; ($err -replace [regex]::Escape($pw),'***') }
