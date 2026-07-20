$ErrorActionPreference='Continue'
Write-Host "=== ping.exe ==="
foreach($h in @('192.168.250.70','192.168.250.1','192.168.210.240')){
  $o = & ping -n 2 -w 2000 $h 2>&1 | Out-String
  if($o -match 'TTL=|ttl='){ Write-Host "PING_OK $h" } else { Write-Host "PING_FAIL $h" }
  ($o -split "`n" | Select-Object -Last 3) | ForEach-Object { Write-Host "  $_" }
}

Write-Host "`n=== SSH quick (ConnectTimeout=5) ==="
$env:GIT_SSH_COMMAND=''
foreach($t in @('claude-server-sepidz','sepidz@192.168.250.70','smart@192.168.250.70')){
  Write-Host ">> $t"
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $out = & ssh -n -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 -o ServerAliveInterval=2 -o ServerAliveCountMax=2 -o StrictHostKeyChecking=accept-new $t 'echo OK; hostname; whoami; date' 2>&1
  $sw.Stop()
  $s = (($out|Out-String) -replace '\s+',' ').Trim()
  if($s.Length -gt 300){ $s=$s.Substring(0,300) }
  Write-Host ("   ms={0} exit={1} {2}" -f $sw.ElapsedMilliseconds, $LASTEXITCODE, $s)
}

Write-Host "`n=== tunnel procs ==="
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match '-R\s+210' } | ForEach-Object {
  Write-Host ("R-tunnel pid={0} {1}" -f $_.ProcessId, $_.CommandLine.Substring(0,[Math]::Min(160,$_.CommandLine.Length)))
}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'connect\.ps1' } | ForEach-Object {
  Write-Host ("connect pid={0} age={1:N0}s {2}" -f $_.ProcessId, ((Get-Date)-$_.CreationDate).TotalSeconds, $_.CommandLine.Substring(0,[Math]::Min(160,$_.CommandLine.Length)))
}

Write-Host "`n=== log tunnel death ==="
$today = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')
if(Test-Path $today){
  Write-Host "log=$today size=$((Get-Item $today).Length)"
  Select-String -Path $today -Pattern 'session start v' | Select-Object -Last 4 | ForEach-Object { $_.Line }
  Select-String -Path $today -Pattern 'TUNNEL: recovering|ORPHAN_TUNNEL|ENSURE_TUNNEL (ok|spawned|ok=0)|killing orphan|killing local|script_dir|SINGLE_INSTANCE|RECOVERY_BEGIN|Connection refused|timed out|EXIT_WAIT|mutex' |
    Select-Object -Last 35 | ForEach-Object { $_.Line.Substring(0,[Math]::Min(210,$_.Line.Length)) }
}
