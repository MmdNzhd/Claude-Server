$ErrorActionPreference='Continue'
Write-Host '=== Invoke-SshXCore (why no mux) ==='
$lines = Get-Content scripts\client\windows\connect.ps1
for ($i=530; $i -lt 580 -and $i -lt $lines.Count; $i++) {
  Write-Host ('{0,4}|{1}' -f ($i+1), $lines[$i])
}

Write-Host ''
Write-Host '=== Who does 3 separate greps for LAPTOP_USER/OS/PORT? ==='
Select-String -Path scripts\client\git-mode.ps1,scripts\client\windows\connect.ps1 -Pattern "LAPTOP_USER=|LAPTOP_OS=|TUNNEL_PORT=|Get-ServerConnectConf|Read-ServerConf" |
  Select-Object -First 40 |
  ForEach-Object { '{0}:{1}: {2}' -f $_.Filename, $_.LineNumber, $_.Line.Trim() }

Write-Host ''
Write-Host '=== Push-ServerConnectConf + self-heal call sites ==='
Select-String -Path scripts\client\git-mode.ps1 -Pattern 'Push-ServerConnectConf|claude-self-heal|function Push-Server' |
  Select-Object -First 30 |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }

Write-Host ''
Write-Host '=== Initialize-ServerSession / parallel? ==='
Select-String -Path scripts\client\windows\connect.ps1,scripts\client\git-mode.ps1 -Pattern 'Initialize-ServerSession|Prepare-ServerSession|Get-LaptopUserFromServer|function Initialize' |
  Select-Object -First 25 |
  ForEach-Object { '{0}:{1}: {2}' -f $_.Filename, $_.LineNumber, $_.Line.Trim() }

Write-Host ''
Write-Host '=== Why session died: any EXIT/error after last line? ==='
$today = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-' + (Get-Date -Format 'yyyyMMdd') + '.log')
Select-String -Path $today -Pattern 'b25d17344291.*(EXIT|session end|ERROR|WARN|killed|crash)|13:45:1[7-9]|13:45:[2-5]' |
  Select-Object -First 40 |
  ForEach-Object { $_.Line.Substring(0,[Math]::Min(200,$_.Line.Length)) }

Write-Host ''
Write-Host '=== SSH config for claude-server-sepidz (ControlPath?) ==='
$ssh = Join-Path $env:USERPROFILE '.ssh\config'
$in=$false
Get-Content $ssh | ForEach-Object {
  if ($_ -match '^Host claude-server-sepidz') { $in=$true }
  elseif ($_ -match '^Host ' -and $in) { $in=$false }
  if ($in) { Write-Host $_ }
}

Write-Host ''
Write-Host '=== Measure one cold SSH RTT now ==='
$sw=[Diagnostics.Stopwatch]::StartNew()
$p=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no','claude-server-sepidz','echo ok') -NoNewWindow -PassThru -RedirectStandardOutput ($env:TEMP+'\rtt.out') -RedirectStandardError ($env:TEMP+'\rtt.err')
$null=$p.WaitForExit(15000)
$sw.Stop()
Write-Host ("cold_ssh_ms={0} exit={1} out={2}" -f $sw.ElapsedMilliseconds, $p.ExitCode, ((Get-Content ($env:TEMP+'\rtt.out') -Raw)+'').Trim())

# second immediate call
$sw2=[Diagnostics.Stopwatch]::StartNew()
$p2=Start-Process ssh -ArgumentList @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','ControlMaster=no','claude-server-sepidz','echo ok2') -NoNewWindow -PassThru -RedirectStandardOutput ($env:TEMP+'\rtt2.out') -RedirectStandardError ($env:TEMP+'\rtt2.err')
$null=$p2.WaitForExit(15000)
$sw2.Stop()
Write-Host ("2nd_ssh_ms={0} exit={1}" -f $sw2.ElapsedMilliseconds, $p2.ExitCode)
