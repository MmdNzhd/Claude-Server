$ErrorActionPreference='Continue'
$ssh=@('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','IdentitiesOnly=yes','-o','IdentityAgent=none')

function Invoke-Remote([string]$Target, [string]$Cmd, [string]$Out) {
  $err = "$Out.err"
  $p = Start-Process ssh -ArgumentList ($ssh+@($Target,$Cmd)) -NoNewWindow -PassThru -RedirectStandardOutput $Out -RedirectStandardError $err
  [void]$p.WaitForExit(20000)
  "=== $Target exit=$($p.ExitCode) ==="
  if (Test-Path $Out) { Get-Content $Out -Raw }
  if (Test-Path $err) { $e=Get-Content $err -Raw; if ($e.Trim()) { "STDERR: $e" } }
}

# Sepidz: need passwordless sudo via sepidz account - try with sudo -n for root reads of other homes
$szCmd = @'
echo VER=$(cat /usr/local/share/claude-client/connect-version.txt 2>/dev/null)
# list who has recent logs
for u in $(ls /home 2>/dev/null); do
  d=/home/$u/.claude/logs
  if [ -d "$d" ]; then
    newest=$(ls -t "$d"/connect-*.log 2>/dev/null | head -1)
    if [ -n "$newest" ]; then
      echo "USER=$u FILE=$newest SIZE=$(wc -c <"$newest") MTIME=$(stat -c %y "$newest" 2>/dev/null | cut -d. -f1)"
    fi
  fi
done
'@
Invoke-Remote 'sepidz@192.168.250.70' $szCmd 'D:\Smart\Claude-Code-Server\scripts\tmp\sz-users.txt'

# Farzad forensic local
$fz='D:\Smart\Claude-Code-Server\scripts\tmp\farzad-connect-20260719.log'
if (Test-Path $fz) {
  '=== FARZAD FORENSIC ERRORS ==='
  Select-String -Path $fz -Pattern 'ERROR|Unexpected|AA616|AUTH_|Disconnect|session start|already ok|soft_fail|PushConf|syntax' |
    Select-Object -Last 45 | ForEach-Object { $_.Line.Substring(0,[Math]::Min(220,$_.Line.Length)) }
} else { 'no farzad forensic' }

# Smart: list all users with logs
$smCmd = @'
echo VER=$(cat /usr/local/share/claude-client/connect-version.txt)
for u in $(ls /home 2>/dev/null); do
  d=/home/$u/.claude/logs
  if [ -d "$d" ]; then
    newest=$(ls -t "$d"/connect-*.log 2>/dev/null | head -1)
    if [ -n "$newest" ]; then
      echo "USER=$u FILE=$newest SIZE=$(wc -c <"$newest") MTIME=$(stat -c %y "$newest" 2>/dev/null | cut -d. -f1)"
    fi
  fi
done
# also laptop-side sync folder if any
ls -la /var/log/claude-connect 2>/dev/null | head -5 || true
'@
Invoke-Remote 'smart@192.168.210.240' $smCmd 'D:\Smart\Claude-Code-Server\scripts\tmp\sm-users.txt'
