$ErrorActionPreference='Continue'
$cmd = @'
wc -c /home/smart/.claude/logs/connect-20260719.log
echo ==== LAST20 ====
tail -n 20 /home/smart/.claude/logs/connect-20260719.log
echo ==== GREP ====
grep -E 'session start|SINGLE_INSTANCE|BOOTSTRAP|v20260719|CONNECT_VERSION|False' /home/smart/.claude/logs/connect-20260719.log | tail -30
echo ==== COUNTS_TAIL2000 ====
tail -n 2000 /home/smart/.claude/logs/connect-20260719.log | grep -c PERF || true
tail -n 2000 /home/smart/.claude/logs/connect-20260719.log | grep -c TUNNEL_SYNC || true
'@
$out = Join-Path $env:TEMP 'slog3.txt'
$p = Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ControlMaster=no','smart@192.168.250.70',$cmd) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError ($out+'.err')
$null = $p.WaitForExit(20000)
Get-Content $out
