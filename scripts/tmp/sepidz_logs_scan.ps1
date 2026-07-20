function SshOut($t,$c,[int]$ms=60000){
  $o=Join-Path $env:TEMP ('l'+[guid]::NewGuid().ToString('N').Substring(0,6)+'.out')
  $p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ControlMaster=no','-o','ConnectTimeout=12',$t,$c) -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o+'.err')
  if(-not $p.WaitForExit($ms)){ try{$p.Kill()}catch{}; return 'TIMEOUT' }
  return ((Get-Content $o -Raw -ErrorAction SilentlyContinue)+'')
}
$cmd = @'
set +e
echo "=== HOST ==="
hostname; date; whoami
echo "=== LOG LOCATIONS ==="
ls -la /var/log/claude* 2>/dev/null
ls -la /home/sepidz/.claude* 2>/dev/null | head -40
ls -la /tmp/claude* 2>/dev/null | head -20
find /home /var/log /var/tmp -maxdepth 4 \( -name '*connect*.log' -o -name '*claude*log*' -o -path '*/.claude-connect/*' -o -path '*/claude-connect/*' \) 2>/dev/null | head -80
echo "=== HOME USERS ==="
ls /home
echo "=== RECENT CONNECT LOGS (find) ==="
find /home -type f \( -name 'connect*.log' -o -name '*.connect.log' -o -path '*/.config/claude-connect/*' -o -path '*/.cache/claude-connect/*' -o -path '*/claude-connect/logs/*' \) 2>/dev/null | head -100
'@
Write-Host (SshOut 'sepidz@192.168.250.70' $cmd)
