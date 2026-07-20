$ErrorActionPreference='Continue'
# kill stuck ssh from previous tests (not -R tunnel)
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -EA SilentlyContinue | ForEach-Object {
  $cl=$_.CommandLine
  if($cl -match '-R\s+210'){ Write-Host "KEEP tunnel pid=$($_.ProcessId)"; return }
  if($cl -match '250\.70|claude-server-sepidz|ConnectTimeout'){
    Write-Host "KILL hung ssh pid=$($_.ProcessId)"
    Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue
  }
}
Start-Sleep 1

Write-Host "`n=== ssh -v brief to sepidz ==="
$p = Start-Process -FilePath ssh -ArgumentList @('-v','-n','-o','BatchMode=yes','-o','ConnectTimeout=6','-o','ConnectionAttempts=1','-o','IdentitiesOnly=yes','claude-server-sepidz','echo OK_HOST; hostname; whoami') -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\ssh-sepidz.out" -RedirectStandardError "$env:TEMP\ssh-sepidz.err"
if(-not $p.WaitForExit(12000)){ try{$p.Kill()}catch{}; Write-Host 'SSH_TIMEOUT_12s' }
else { Write-Host "exit=$($p.ExitCode)" }
Write-Host '--- stdout ---'; Get-Content "$env:TEMP\ssh-sepidz.out" -EA SilentlyContinue
Write-Host '--- stderr last 30 ---'; Get-Content "$env:TEMP\ssh-sepidz.err" -EA SilentlyContinue | Select-Object -Last 30

Write-Host "`n=== connect log forensics ==="
$today = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')
Write-Host "exists=$(Test-Path $today) path=$today"
if(Test-Path $today){
  $fi=Get-Item $today; Write-Host "size_MB=$([math]::Round($fi.Length/1MB,2)) mtime=$($fi.LastWriteTime)"
  Write-Host 'SESSION STARTS:'
  Select-String $today 'session start v' | Select-Object -Last 5 | % { $_.Line }
  Write-Host 'SCRIPT_DIR / MUTEX:'
  Select-String $today 'script_dir:|SINGLE_INSTANCE' | Select-Object -Last 8 | % { $_.Line.Substring(0,[Math]::Min(220,$_.Line.Length)) }
  Write-Host 'TUNNEL EVENTS:'
  Select-String $today 'TUNNEL: recovering|ORPHAN_TUNNEL|ENSURE_TUNNEL|killing orphan|killing local|CLEAR_MOUNT|RECOVERY_BEGIN|RECOVERY_END|EXIT_WAIT|Connection refused|port 21002' |
    Select-Object -Last 40 | % { $_.Line.Substring(0,[Math]::Min(220,$_.Line.Length)) }
}

Write-Host "`n=== live procs ==="
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'connect\.ps1' } | ForEach-Object {
  Write-Host ("connect pid={0} age={1:N0}s {2}" -f $_.ProcessId, ((Get-Date)-$_.CreationDate).TotalSeconds, $_.CommandLine.Substring(0,[Math]::Min(180,$_.CommandLine.Length)))
}
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -EA SilentlyContinue | Where-Object { $_.CommandLine -match '-R' } | ForEach-Object {
  Write-Host ("tunnel pid={0} {1}" -f $_.ProcessId, $_.CommandLine.Substring(0,[Math]::Min(180,$_.CommandLine.Length)))
}
