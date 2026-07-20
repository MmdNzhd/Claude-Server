$ErrorActionPreference='Continue'
function Ssh([string]$Cmd){
  $args=@('-o','BatchMode=yes','-o','ConnectTimeout=15','-o','IdentitiesOnly=yes','-o','IdentityAgent=none','claude-server-sepidz',$Cmd)
  $out=Join-Path $env:TEMP 'sz-log-out.txt'; $err=Join-Path $env:TEMP 'sz-log-err.txt'
  $p=Start-Process -FilePath ssh -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  if($p.ExitCode -ne 0){ Write-Output "SSH_EXIT=$($p.ExitCode)"; Get-Content $err -EA SilentlyContinue }
  Get-Content $out -EA SilentlyContinue
}
$day=(Get-Date).ToString('yyyyMMdd')
Write-Output "DAY=$day"
Write-Output '=== log inventory ==='
Ssh @"
ls -la /home/*/.claude/logs/connect-$day.log 2>/dev/null
ls -la /root/.claude/logs/connect-$day.log 2>/dev/null
find /home -maxdepth 3 -path '*/.claude/logs/connect-*.log' -mtime -1 2>/dev/null | head -40
"@
Write-Output '=== per-user version / session start (today) ==='
Ssh @"
for f in /home/*/.claude/logs/connect-$day.log; do
  [ -f \"\$f\"] || continue
  u=\$(echo \"\$f\" | cut -d/ -f3)
  sz=\$(wc -c < \"\$f\" | tr -d ' ')
  lines=\$(wc -l < \"\$f\" | tr -d ' ')
  echo \"===== \$u size=\$sz lines=\$lines =====\"
  grep -E 'session start|ConnectVersion|CONNECT_VERSION|v2026|UPDATE|PUSH_CONF|SESSION_KEY|CLEAR_MOUNT|elif|syntax error|user_quit|fallthrough|ORPHAN|soft_fail|applied_ok' \"\$f\" 2>/dev/null | tail -80
  echo
done
"@
