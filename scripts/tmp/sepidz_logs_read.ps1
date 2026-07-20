function SshOut($t,$c,[int]$ms=90000){
  $o=Join-Path $env:TEMP ('l'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.out')
  $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=12',$t,$c) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.err')
  if(-not $p.WaitForExit($ms)){ try{$p.Kill()}catch{}; return 'TIMEOUT' }
  $err=((Get-Content ($o+'.err') -Raw -ErrorAction SilentlyContinue)+'')
  $out=((Get-Content $o -Raw -ErrorAction SilentlyContinue)+'')
  if($err.Trim()){ return $out + "`nSTDERR:`n" + $err }
  return $out
}
$cmd = @'
set +e
echo "=== /var/log/claude* ==="
ls -lah /var/log/claude* 2>/dev/null
echo
echo "=== connect log dirs ==="
ls -lah /var/log/claude-connect 2>/dev/null
ls -lah /var/log/claude-connect-logs 2>/dev/null
ls -lah /usr/local/share/claude-connect-logs 2>/dev/null
find /var/log /usr/local/share /home -maxdepth 3 -type d -iname '*connect*log*' 2>/dev/null
find /var/log /usr/local/share -maxdepth 4 -type f -iname '*connect*' 2>/dev/null | head -50
echo
echo "=== activity last 40 ==="
tail -n 40 /var/log/claude-activity.jsonl 2>/dev/null
echo
echo "=== auth last 80 (errors/warn) ==="
tail -n 200 /var/log/claude-auth.log 2>/dev/null | grep -iE 'error|fail|warn|denied|invalid|bug|exception|timeout' | tail -n 80
echo
echo "=== auth last 40 raw ==="
tail -n 40 /var/log/claude-auth.log 2>/dev/null
echo
echo "=== per-user recent logs ==="
for u in alit aminb designer farzadb hosseinb hosseinm nimaz zahrak smart sepidz; do
  echo "-- $u --"
  ls -lah /home/$u/.config/claude-connect 2>/dev/null | head -20
  ls -lah /home/$u/.cache/claude-connect 2>/dev/null | head -20
  ls -lah /home/$u/mounts 2>/dev/null | head -15
  # server-side uploaded client logs often land here:
  ls -lah /home/$u/.claude-connect-logs 2>/dev/null | head -20
done
echo
echo "=== find client session logs under /home (mtime 3d) ==="
find /home -type f \( -name '*.log' -o -name '*.jsonl' \) \( -path '*claude-connect*' -o -path '*connect-log*' -o -name 'connect-*.log' -o -name 'session*.log' \) -mtime -3 2>/dev/null | head -80
'@
Write-Host (SshOut 'sepidz@192.168.250.70' $cmd)
