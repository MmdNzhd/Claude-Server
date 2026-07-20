$ErrorActionPreference='Continue'
Write-Host "========== 1) SEPIDZ FROM LAPTOP =========="
function PingHost($h){
  $r = Test-Connection -ComputerName $h -Count 2 -TimeoutSeconds 2 -ErrorAction SilentlyContinue
  if($r){ Write-Host ("PING_OK {0} avg_ms={1}" -f $h, [int](($r | Measure-Object ResponseTime -Average).Average)) }
  else { Write-Host ("PING_FAIL {0}" -f $h) }
}
PingHost '192.168.250.70'
PingHost '192.168.250.1'
PingHost '192.168.210.240'
PingHost 'api.cursor.com'

Write-Host "`n--- TCP 22 ---"
foreach($h in @('192.168.250.70','192.168.210.240')){
  try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $iar = $tcp.BeginConnect($h,22,$null,$null)
    $ok = $iar.AsyncWaitHandle.WaitOne(3000,$false)
    if($ok -and $tcp.Connected){ Write-Host ("TCP22_OK {0}" -f $h); $tcp.Close() }
    else { Write-Host ("TCP22_FAIL {0}" -f $h); try{$tcp.Close()}catch{} }
  } catch { Write-Host ("TCP22_FAIL {0} {1}" -f $h, $_.Exception.Message) }
}

Write-Host "`n--- curl Cursor API ---"
try {
  $r = Invoke-WebRequest -Uri 'https://api.cursor.com/' -Method Head -TimeoutSec 8 -UseBasicParsing
  Write-Host ("CURL_CURSOR status={0}" -f $r.StatusCode)
} catch {
  Write-Host ("CURL_CURSOR fail={0}" -f $_.Exception.Message)
}

Write-Host "`n--- SSH to Sepidz (BatchMode) ---"
foreach($target in @('smart@192.168.250.70','sepidz@192.168.250.70','claude-server-sepidz')){
  Write-Host ("ssh try {0}" -f $target)
  $out = & ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new $target 'echo OK; hostname; date; whoami; uptime' 2>&1
  Write-Host ("  exit={0} out={1}" -f $LASTEXITCODE, (($out -join ' ') -replace '\s+',' ').Substring(0,[Math]::Min(250,(($out -join ' ') -replace '\s+',' ').Length)))
}

Write-Host "`n========== 2) LOCAL TUNNEL STATE =========="
$ssh = Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -EA SilentlyContinue
Write-Host ("ssh_count={0}" -f @($ssh).Count)
$ssh | ForEach-Object {
  $cl = $_.CommandLine
  if($cl -match '-R|250\.70|2100|claude-server'){
    Write-Host ("  pid={0} {1}" -f $_.ProcessId, $cl.Substring(0,[Math]::Min(180,$cl.Length)))
  }
}

$ps = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'connect\.ps1' }
Write-Host "`nconnect.ps1 processes:"
if(-not $ps){ Write-Host '  (none)' }
$ps | ForEach-Object {
  $age = ((Get-Date)-$_.CreationDate).TotalSeconds
  Write-Host ("  pid={0} age_s={1:N0} {2}" -f $_.ProcessId, $age, $_.CommandLine.Substring(0,[Math]::Min(200,$_.CommandLine.Length)))
}

Write-Host "`n========== 3) RECENT CONNECT LOG (tunnel death) =========="
$today = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')
Write-Host ("log={0} exists={1}" -f $today, (Test-Path $today))
if(Test-Path $today){
  $fi=Get-Item $today
  Write-Host ("size_MB={0:N2} mtime={1}" -f ($fi.Length/1MB), $fi.LastWriteTime)
  Write-Host '--- last 6 session starts ---'
  Select-String -Path $today -Pattern 'session start v' | Select-Object -Last 6 | ForEach-Object { $_.Line }
  Write-Host '--- tunnel die / recover / kill / DOWN keywords (last 40) ---'
  Select-String -Path $today -Pattern 'TUNNEL: recovering|tunnel.*down|ORPHAN_TUNNEL|ENSURE_TUNNEL|killing|CLEAR_MOUNT|Connection refused|timed out|EXIT|SINGLE_INSTANCE|script_dir' |
    Select-Object -Last 40 | ForEach-Object { $_.Line.Substring(0,[Math]::Min(220,$_.Line.Length)) }
  Write-Host '--- last 25 non-TRACE lines ---'
  Get-Content $today -Tail 80 | Where-Object { $_ -notmatch '\[TRACE\]|PERF\[cim' } | Select-Object -Last 25
}
