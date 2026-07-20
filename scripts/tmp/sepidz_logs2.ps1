function SshOut($t,$c,[int]$ms=120000){
  $o=Join-Path $env:TEMP ('l'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.out')
  $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=12',$t,$c) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.err')
  if(-not $p.WaitForExit($ms)){ try{$p.Kill()}catch{}; return 'TIMEOUT' }
  return ((Get-Content $o -Raw -ErrorAction SilentlyContinue)+'')
}
$cmd = @'
set +e
echo === FIND LOG ROOTS ===
ls -lah /var/log/claude-connect-logs 2>/dev/null
ls -lah /usr/local/share/claude-connect-logs 2>/dev/null
ls -lah /home/*/claude-connect-logs 2>/dev/null
find /var /usr/local /home -maxdepth 4 -type d -name 'claude-connect-logs' 2>/dev/null
find /var /usr/local /home -maxdepth 5 -type f -name 'connect-*.log' 2>/dev/null | head -60
find /var /usr/local /home -maxdepth 5 -type f -name '*connect*.log' 2>/dev/null | head -60
echo === AUTH ERRORS RECENT ===
grep -iE 'error|fail|denied|invalid|timeout|401|403|PROBE_FAIL' /var/log/claude-auth.log | tail -n 60
echo === AUTH TAIL ===
tail -n 30 /var/log/claude-auth.log
echo === USER MOUNTS STATUS ===
for u in alit aminb designer farzadb hosseinb hosseinm nimaz zahrak; do
  echo -- $u --
  ls /home/$u/mounts 2>/dev/null
  ls -lah /home/$u/.claude-connect.conf 2>/dev/null
  ls /home/$u/.claude-mounts.d 2>/dev/null
  # last login-ish
  last -n 2 $u 2>/dev/null | head -3
done
echo === JOURNAL CONNECT RECENT ===
journalctl --since "2 days ago" 2>/dev/null | grep -iE 'claude|fuse|sshfs|connect' | tail -n 40
echo === DMESG FUSE ===
dmesg 2>/dev/null | grep -iE 'fuse|sshfs' | tail -n 20
'@
Write-Host (SshOut 'sepidz@192.168.250.70' $cmd)
