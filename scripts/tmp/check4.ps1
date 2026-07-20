$ErrorActionPreference='Continue'

Write-Host "========== SEPIDZ LOGS (via laptop SSH) =========="
$remote = @'
set +e
echo "HOST=$(hostname) USER=$(whoami) DATE=$(date -Is)"
echo "--- homes ---"
ls /home 2>/dev/null
echo "--- connect logs today ---"
ls -lt /home/*/.claude/logs/connect-20260719.log 2>/dev/null
ls -lt /root/.claude/logs/connect-20260719.log 2>/dev/null
ls -lt ~/.claude/logs/connect-20260719.log 2>/dev/null
echo "--- farzad-ish users ---"
getent passwd | cut -d: -f1 | grep -iE 'farz|faz|farzad' || echo '(no farzad passwd)'
ls /home | grep -iE 'farz|faz' || echo '(no farzad home)'
echo "--- last session starts across users ---"
for f in /home/*/.claude/logs/connect-20260719.log ~/.claude/logs/connect-20260719.log; do
  [ -f "$f" ] || continue
  echo "== $f =="
  grep -E 'session start v|Connection refused|timed out|Permission denied|TUNNEL: recovering|ERROR|failed' "$f" 2>/dev/null | tail -20
done
echo "--- sshd recent (sudo if possible) ---"
journalctl -u ssh --since 'today' --no-pager 2>/dev/null | tail -30 || tail -30 /var/log/auth.log 2>/dev/null | grep sshd | tail -20
echo "--- listening 2100x ---"
ss -ltn | grep 210 || true
'@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
$out = & ssh -n -o BatchMode=yes -o ConnectTimeout=10 claude-server-sepidz "echo $b64 | base64 -d | bash" 2>&1
Write-Host ($out -join "`n")

Write-Host "`n========== LOCAL LOG (tunnel death) =========="
$today = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')
Write-Host "mtime=$((Get-Item $today).LastWriteTime) size=$([math]::Round((Get-Item $today).Length/1MB,2))MB"
Write-Host '--- sessions ---'
Select-String -Path $today -Pattern 'session start v' | Select-Object -Last 5 | ForEach-Object { $_.Line }
Write-Host '--- script_dir / mutex ---'
Select-String -Path $today -Pattern 'script_dir:|SINGLE_INSTANCE' | Select-Object -Last 10 | ForEach-Object { $_.Line.Substring(0,[Math]::Min(230,$_.Line.Length)) }
Write-Host '--- tunnel events ---'
Select-String -Path $today -Pattern 'TUNNEL: recovering|ORPHAN_TUNNEL|ENSURE_TUNNEL|killing orphan|killing local|RECOVERY_BEGIN|RECOVERY_END|EXIT_WAIT|claude-code-client|claude-code-sepidz' |
  Select-Object -Last 45 | ForEach-Object { $_.Line.Substring(0,[Math]::Min(230,$_.Line.Length)) }

Write-Host "`n========== LIVE =========="
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'connect\.ps1' } | ForEach-Object {
  Write-Host ("CONNECT {0}" -f $_.CommandLine.Substring(0,[Math]::Min(220,$_.CommandLine.Length)))
}
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match '-R' } | ForEach-Object {
  Write-Host ("TUNNEL {0}" -f $_.CommandLine.Substring(0,[Math]::Min(200,$_.CommandLine.Length)))
}
Write-Host ("ssh_total={0}" -f @(Get-Process ssh -EA SilentlyContinue).Count)
