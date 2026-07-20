function SshOut($t,$c,[int]$ms=180000){
  $o=Join-Path $env:TEMP ('l'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.out')
  $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=12',$t,$c) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.err')
  if(-not $p.WaitForExit($ms)){ try{$p.Kill()}catch{}; return 'TIMEOUT' }
  return ((Get-Content $o -Raw -ErrorAction SilentlyContinue)+'')
}
# Use base64 remote script to avoid quoting hell
$remote = @'
#!/bin/bash
set +e
users="alit aminb designer farzadb hosseinb hosseinm nimaz zahrak sepidz smart"
echo "=== PER-USER CONNECT LOG FILES ==="
for u in $users; do
  d="/home/$u/.claude/logs"
  if [ -d "$d" ]; then
    echo "-- $u --"
    ls -lah "$d" 2>/dev/null
  else
    echo "-- $u -- NO_LOG_DIR"
  fi
done
echo
echo "=== RECENT ERRORS WARN FAIL across users last 7d ==="
for u in $users; do
  d="/home/$u/.claude/logs"
  [ -d "$d" ] || continue
  hits=$(grep -h -E 'ERROR|WARN|FAIL|failed|exception|denied|timeout|UNHANDLED|PROBE_FAIL|auth' "$d"/connect-*.log 2>/dev/null | tail -n 30)
  if [ -n "$hits" ]; then
    echo "#### $u ####"
    echo "$hits"
    echo
  fi
done
echo
echo "=== TODAY LOG TAILS ==="
day=$(date +%Y%m%d)
yday=$(date -d yesterday +%Y%m%d 2>/dev/null || date -v-1d +%Y%m%d 2>/dev/null)
for u in $users; do
  for dayf in "$day" "$yday"; do
    f="/home/$u/.claude/logs/connect-${dayf}.log"
    if [ -f "$f" ]; then
      echo "#### $u connect-${dayf}.log bytes=$(wc -c < "$f") ####"
      # show last 80 lines emphasizing problems
      tail -n 120 "$f" | grep -E 'ERROR|WARN|FAIL|failed|UNHANDLED|session|Update|version|auth|mount|SSH_|STEP end:.*fail|timeout|denied' || true
      echo "---- raw tail 40 ----"
      tail -n 40 "$f"
      echo
    fi
  done
done
echo "=== AUTH SUMMARY ==="
echo "probe fails last 24h:" 
grep '"event": "PROBE_FAIL"' /var/log/claude-auth.log | awk -F'"timestamp": "' '{print $2}' | cut -c1-13 | sort | uniq -c | tail -n 20
echo "latest probe message:"
grep '"event": "PROBE_FAIL"' /var/log/claude-auth.log | tail -n 1 | python3 -c 'import sys,json,re; s=sys.stdin.read();
m=re.search(r"message\\":\\"([^\\"]+)", s); print(m.group(1) if m else s[:200])'
'@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($remote -replace "`r",'')))
$wrap = "echo $b64 | base64 -d > /tmp/read_logs.sh && bash /tmp/read_logs.sh"
Write-Host (SshOut 'sepidz@192.168.250.70' $wrap)
