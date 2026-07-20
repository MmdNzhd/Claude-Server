$ErrorActionPreference='Continue'
$local = 'publish\sepidz-deploy.local.ps1'
if(-not (Test-Path $local)){ Write-Host 'NO sepidz-deploy.local.ps1'; exit 2 }
# Show assignment LHS only
Select-String -Path $local -Pattern '=' | ForEach-Object {
  $lhs = ($_.Line -split '=',2)[0].Trim()
  if($lhs -and $lhs -notmatch '^\s*#'){ Write-Host "VAR $lhs" }
}
. $local
$pw = $null
foreach($n in @('SepidzSudoPassword','SudoPassword','DeploySudoPassword','Password','SEPIDZ_SUDO','SepidzPassword')){
  $v = Get-Variable -Name $n -EA SilentlyContinue
  if($v -and $v.Value){ $pw = [string]$v.Value; Write-Host "USING_VAR $n len=$($pw.Length)"; break }
}
if(-not $pw -and $env:SEPIDZ_SUDO_PASSWORD){ $pw = $env:SEPIDZ_SUDO_PASSWORD; Write-Host 'USING_ENV SEPIDZ_SUDO_PASSWORD' }
if(-not $pw){ Write-Host 'NO_PW'; exit 3 }

$bash = @'
set +e
echo HOST=$(hostname) ME=$(whoami) DATE=$(date -Is)
echo '===== HOMES ====='
ls /home
echo '===== CONNECT LOGS (all users, last 3 days) ====='
ls -lt /home/*/.claude/logs/connect-*.log 2>/dev/null
echo '===== PER-USER CONNECT SUMMARY ====='
for u in /home/*; do
  u=$(basename "$u")
  dir=/home/$u/.claude/logs
  if [ ! -d "$dir" ]; then echo "NO_CLAUDE_LOGS user=$u"; continue; fi
  echo "==== USER=$u ===="
  ls -lt "$dir"/connect-*.log 2>/dev/null | head -5
  for f in "$dir"/connect-20260719.log "$dir"/connect-20260718.log; do
    [ -f "$f" ] || continue
    echo "-- file=$f bytes=$(wc -c <"$f") --"
    grep -E 'session start v|ERROR|failed|Connection refused|timed out|Permission denied|TUNNEL: recovering|network' "$f" 2>/dev/null | tail -25
  done
done
echo '===== FARZADB DETAIL ====='
ls -la /home/farzadb/.claude/logs 2>&1 | head -20
for f in /home/farzadb/.claude/logs/connect-*.log; do
  [ -f "$f" ] || continue
  echo "FULLTAIL $f"
  tail -n 150 "$f"
  echo '----'
done
echo '===== FARZADB CURSOR ====='
d=$(ls -td /home/farzadb/.cursor-server/data/logs/* 2>/dev/null | head -1)
echo "cursor_dir=$d"
if [ -n "$d" ]; then
  find "$d" -name remoteagent.log -exec tail -n 100 {} \;
  find "$d" -name '*.log' -print0 | xargs -0 grep -iE 'error|fail|refused|timeout|ECONN|Could not|disconnected|ENOTFOUND' 2>/dev/null | tail -40
fi
echo '===== AUTH farzadb / fails today ====='
grep -iE 'farzadb|Failed password|Invalid user|Connection closed' /var/log/auth.log 2>/dev/null | tail -80
echo DONE_ALL
'@

$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
# Pass password via env on remote carefully - use printf to sudo -S
$pwEsc = $pw.Replace("'","'""'""'")
$remote = "printf '%s\n' '$pwEsc' | sudo -S -p '' bash -c 'echo $b64 | base64 -d | bash'"

$o="$env:TEMP\allu.out"; $e="$env:TEMP\allu.err"
Remove-Item $o,$e -Force -EA SilentlyContinue
$p=Start-Process ssh -ArgumentList @('-n','-o','BatchMode=yes','-o','ConnectTimeout=12','sepidz@192.168.250.70',$remote) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
if(-not $p.WaitForExit(90000)){ try{$p.Kill()}catch{}; Write-Host 'TIMEOUT_90s' }
else { Write-Host "ssh_exit=$($p.ExitCode)" }
Write-Host '===== STDOUT ====='
if(Test-Path $o){ Get-Content $o }
Write-Host '===== STDERR (no secrets) ====='
if(Test-Path $e){ Get-Content $e | Select-Object -Last 25 }
