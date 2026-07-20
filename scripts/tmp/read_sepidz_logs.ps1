$ErrorActionPreference='Continue'
function Run([string]$cmd,[int]$ms=20000){
  $o="$env:TEMP\rz.out"; $e="$env:TEMP\rz.err"
  Remove-Item $o,$e -Force -EA SilentlyContinue
  $p=Start-Process ssh -ArgumentList @('-n','-o','BatchMode=yes','-o','ConnectTimeout=10','claude-server-sepidz',$cmd) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
  if(-not $p.WaitForExit($ms)){ try{$p.Kill()}catch{}; Write-Host "TIMEOUT: $cmd"; return }
  Write-Host "==== exit=$($p.ExitCode) ===="
  if(Test-Path $o){ Get-Content $o -Raw }
  if(Test-Path $e){ $err=@(Get-Content $e); if($err){ Write-Host "STDERR: $($err -join ' | ')" } }
}

Write-Host "=== 1 list all connect logs today+yesterday ==="
Run 'ls -la /home/farzadb/.claude/logs/ 2>/dev/null; ls -la /home/*/./.claude/logs/connect-2026071*.log 2>/dev/null; ls -la /home/smart/.claude/logs/connect-2026071*.log 2>/dev/null'

Write-Host "=== 2 farzadb last 80 lines any connect log ==="
Run 'for f in /home/farzadb/.claude/logs/connect-*.log; do echo FILE=$f; tail -n 80 "$f"; echo ----; done 2>/dev/null; ls /home/farzadb/.claude/logs/ 2>/dev/null || echo NO_FARZAD_LOG_DIR'

Write-Host "=== 3 farzadb cursor/ssh errors today ==="
Run 'grep -hE "session start|ERROR|failed|fail|timeout|timed out|Connection refused|Permission denied|TUNNEL|network|disconnect" /home/farzadb/.claude/logs/connect-20260719.log /home/farzadb/.claude/logs/connect-20260718.log 2>/dev/null | tail -60; echo DONE_FARZAD'

Write-Host "=== 4 other users today connect activity ==="
Run 'for u in alit aminb hosseinb hosseinm nimaz zahrak designer sepidz smart farzadb; do f=/home/$u/.claude/logs/connect-20260719.log; if [ -f "$f" ]; then echo "HAS $u $(wc -c < "$f") bytes mtime=$(stat -c %y "$f" 2>/dev/null)"; else echo "NO $u"; fi; done'

Write-Host "=== 5 any user errors last 2 days ==="
Run 'for f in /home/*/.claude/logs/connect-20260719.log /home/*/.claude/logs/connect-20260718.log; do [ -f "$f" ] || continue; c=$(grep -cE "ERROR|failed|Connection refused|timed out|Permission denied" "$f" 2>/dev/null || echo 0); echo "$c $f"; done | sort -rn | head -20'

Write-Host "=== 6 farzadb home recent cursor logs ==="
Run 'ls -lt /home/farzadb/.cursor-server/data/logs 2>/dev/null | head -5; find /home/farzadb/.cursor-server/data/logs -name "remoteagent.log" -mtime -2 2>/dev/null | head -5 | while read x; do echo FILE=$x; tail -40 "$x"; echo ----; done; echo DONE_CURSOR'
