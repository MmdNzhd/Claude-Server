$ErrorActionPreference='Continue'
function SshT([string]$cmd, [int]$ms=15000) {
  $id=[guid]::NewGuid().ToString('N').Substring(0,8)
  $o="$env:TEMP\s5-$id.out"; $e="$env:TEMP\s5-$id.err"
  $p=Start-Process ssh -ArgumentList @('-n','-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ConnectionAttempts=1','claude-server-sepidz',$cmd) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  if(-not $p.WaitForExit($ms)){ try{$p.Kill()}catch{}; Write-Host "TIMEOUT cmd=$cmd"; return $null }
  Write-Host "exit=$($p.ExitCode) cmd=$($cmd.Substring(0,[Math]::Min(60,$cmd.Length)))"
  if(Test-Path $o){ Get-Content $o }
  if(Test-Path $e){ $err=Get-Content $e | Select-Object -Last 5; if($err){ Write-Host "ERR: $($err -join ' | ')" } }
}

Write-Host '=== A host ==='
SshT 'hostname; whoami; date; uptime'

Write-Host '`n=== B homes ==='
SshT 'ls /home'

Write-Host '`n=== C connect logs list ==='
SshT 'ls -lt /home/*/.claude/logs/connect-20260719.log 2>/dev/null; ls -lt $HOME/.claude/logs/connect-20260719.log 2>/dev/null; echo DONE'

Write-Host '`n=== D farzad ==='
SshT 'getent passwd | cut -d: -f1 | grep -iE farz\|faz || true; ls /home | grep -iE farz\|faz || echo no_farzad_home'

Write-Host '`n=== E recent errors in all today logs ==='
SshT 'for f in /home/*/.claude/logs/connect-20260719.log $HOME/.claude/logs/connect-20260719.log; do [ -f "$f" ] || continue; echo ==== $f ====; grep -E "session start|ERROR|failed|timed out|Connection refused|Permission denied|TUNNEL: recovering" "$f" | tail -15; done; echo DONE' 25000

Write-Host '`n=== F local connect identity ==='
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'connect\.ps1' } | ForEach-Object { $_.CommandLine }
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match '-R' } | ForEach-Object { $_.CommandLine }

Write-Host '`n=== G local log sessions + kills ==='
$today = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')
Select-String -Path $today -Pattern 'session start v' | Select-Object -Last 5 | ForEach-Object { $_.Line }
Select-String -Path $today -Pattern 'script_dir:' | Select-Object -Last 5 | ForEach-Object { $_.Line.Substring(0,[Math]::Min(240,$_.Line.Length)) }
Select-String -Path $today -Pattern 'ORPHAN_TUNNEL|TUNNEL: recovering|killing orphan|killing local|ENSURE_TUNNEL spawned|ENSURE_TUNNEL ok' | Select-Object -Last 30 | ForEach-Object { $_.Line.Substring(0,[Math]::Min(220,$_.Line.Length)) }
