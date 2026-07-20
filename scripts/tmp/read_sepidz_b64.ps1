$ErrorActionPreference='Continue'
function SshB64([string]$bash, [int]$ms=25000) {
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
  $o="$env:TEMP\sb.out"; $e="$env:TEMP\sb.err"
  Remove-Item $o,$e -Force -EA SilentlyContinue
  $remote = "echo $b64 | base64 -d | bash"
  $p=Start-Process ssh -ArgumentList @('-n','-o','BatchMode=yes','-o','ConnectTimeout=10','claude-server-sepidz',$remote) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  if(-not $p.WaitForExit($ms)){ try{$p.Kill()}catch{}; Write-Host 'TIMEOUT'; return }
  Write-Host "exit=$($p.ExitCode)"
  if(Test-Path $o){ Get-Content $o }
  if(Test-Path $e){ $err=Get-Content $e | Where-Object { $_ -and $_ -notmatch '^Warning:' }; if($err){ Write-Host "ERR: $($err -join ' | ')" } }
}

Write-Host '===== FARZADB HOME ====='
SshB64 @'
echo USER=$(whoami) HOST=$(hostname)
echo '--- farzadb home top ---'
ls -la /home/farzadb 2>&1 | head -40
echo '--- .claude ---'
ls -laR /home/farzadb/.claude 2>&1 | head -50
echo '--- .cursor-server ---'
ls -lt /home/farzadb/.cursor-server/data/logs 2>&1 | head -10
echo '--- find logs ---'
find /home/farzadb -name '*.log' -mtime -3 2>/dev/null | head -40
'@

Write-Host '===== FARZADB CURSOR REMOTEAGENT ====='
SshB64 @'
latest=$(ls -td /home/farzadb/.cursor-server/data/logs/* 2>/dev/null | head -1)
echo LATEST=$latest
if [ -n "$latest" ]; then
  find "$latest" -type f -name '*.log' 2>/dev/null | head -30
  echo '--- remoteagent tail ---'
  find "$latest" -name 'remoteagent.log' -exec tail -n 80 {} \; 2>/dev/null
  echo '--- exthost errors ---'
  find "$latest" -name '*.log' -print0 2>/dev/null | xargs -0 grep -iE 'error|fail|refused|timeout|disconnect|ECONN|ENOTFOUND|network' 2>/dev/null | tail -40
fi
'@ 35000

Write-Host '===== ALL USERS CURSOR ERRORS TODAY ====='
SshB64 @'
for u in farzadb alit aminb hosseinb hosseinm nimaz zahrak designer sepidz smart; do
  d=$(ls -td /home/$u/.cursor-server/data/logs/* 2>/dev/null | head -1)
  [ -n "$d" ] || continue
  echo "==== $u dir=$d ===="
  find "$d" -name 'remoteagent.log' 2>/dev/null | while read f; do
    echo "-- $f --"
    grep -iE 'error|fail|refused|timeout|ECONN|Could not|disconnected' "$f" 2>/dev/null | tail -15
  done
done
echo DONE_USERS
'@ 40000

Write-Host '===== SSHD / AUTH FARZAD ====='
SshB64 @'
echo '--- auth farzadb today ---'
grep -i farzadb /var/log/auth.log 2>/dev/null | tail -40
journalctl -u ssh --since today --no-pager 2>/dev/null | grep -i farzad | tail -40
echo '--- last ssh fails ---'
grep -iE 'Failed|Invalid|Connection closed|farzad|Disconnected' /var/log/auth.log 2>/dev/null | tail -50
echo DONE_AUTH
'@ 20000
