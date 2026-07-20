$ErrorActionPreference='Continue'
function SshTarget([string]$target, [string]$bash, [int]$ms=30000) {
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
  $o="$env:TEMP\sf.out"; $e="$env:TEMP\sf.err"
  Remove-Item $o,$e -Force -EA SilentlyContinue
  $remote = "echo $b64 | base64 -d | bash"
  $p=Start-Process ssh -ArgumentList @('-n','-o','BatchMode=yes','-o','ConnectTimeout=10',$target,$remote) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  if(-not $p.WaitForExit($ms)){ try{$p.Kill()}catch{}; Write-Host "TIMEOUT $target"; return }
  Write-Host "target=$target exit=$($p.ExitCode)"
  if(Test-Path $o){ Get-Content $o }
  if(Test-Path $e){ $err=Get-Content $e | Select-Object -Last 8; if($err){ Write-Host "ERR: $($err -join ' | ')" } }
}

$script = @'
set -e
echo HOST=$(hostname) ME=$(whoami)
# try passwordless sudo
if sudo -n true 2>/dev/null; then echo SUDO_OK; else echo SUDO_NEED_PASS; fi
echo '===== farzadb listing via sudo ====='
sudo -n ls -la /home/farzadb 2>&1 | head -30
echo '===== .claude logs ====='
sudo -n ls -la /home/farzadb/.claude/logs 2>&1 | head -20
sudo -n bash -c 'ls -lt /home/farzadb/.claude/logs/connect-*.log 2>/dev/null | head -10'
echo '===== connect log tails ====='
sudo -n bash -c 'for f in /home/farzadb/.claude/logs/connect-*.log; do [ -f "$f" ] || continue; echo FILE=$f; tail -n 100 "$f"; echo ----; done'
echo '===== cursor logs ====='
sudo -n bash -c 'ls -lt /home/farzadb/.cursor-server/data/logs 2>/dev/null | head -8'
sudo -n bash -c 'd=$(ls -td /home/farzadb/.cursor-server/data/logs/* 2>/dev/null | head -1); echo D=$d; if [ -n "$d" ]; then find "$d" -name remoteagent.log -exec tail -n 100 {} \;; find "$d" -name "*.log" -print0 | xargs -0 grep -iE "error|fail|refused|timeout|ECONN|Could not|disconnected|ENOTFOUND" 2>/dev/null | tail -50; fi'
echo '===== auth farzadb ====='
sudo -n bash -c 'grep -i farzadb /var/log/auth.log 2>/dev/null | tail -50'
sudo -n bash -c 'journalctl -u ssh --since today --no-pager 2>/dev/null | grep -i farzad | tail -40'
echo '===== other users with connect logs ====='
sudo -n bash -c 'ls -lt /home/*/.claude/logs/connect-2026071*.log 2>/dev/null'
echo DONE
'@

Write-Host '--- try sepidz@ ---'
SshTarget 'sepidz@192.168.250.70' $script 45000
Write-Host '--- try claude-server-sepidz with sudo -n ---'
SshTarget 'claude-server-sepidz' $script 45000
