$ErrorActionPreference='Continue'
$logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$day = Get-Date -Format 'yyyyMMdd'
$log = Join-Path $logDir ("connect-{0}.log" -f $day)
Write-Host ("log={0} exists={1}" -f $log, (Test-Path $log))
if (Test-Path $log) {
  $len = (Get-Item $log).Length
  Write-Host ("size={0}" -f $len)
  Write-Host '=== last 120 lines (filtered) ==='
  Get-Content $log -Tail 250 | Where-Object {
    $_ -match 'Cursor|EDITOR|OPEN|auth|LAUNCH|FAIL|ERROR|WARN|GITMODE|TUNNEL|mount|skip_remount|Ai Gap|ai-gap|Opening|proxy|SLOW|timeout|hang|stuck|READY|project'
  } | Select-Object -Last 120
  Write-Host ''
  Write-Host '=== last 40 raw ==='
  Get-Content $log -Tail 40
}

Write-Host ''
Write-Host '=== processes ==='
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $cl=[string]$_.CommandLine
  $n=$_.Name
  $cl -match 'connect-boot|connect\.ps1|Cursor\.exe|claude-connect' -or $n -match 'Cursor'
} | ForEach-Object {
  $c=[string]$_.CommandLine
  if ($c.Length -gt 160) { $c=$c.Substring(0,160)+'...' }
  Write-Host ("pid={0} name={1} {2}" -f $_.ProcessId, $_.Name, $c)
}

# also laptop ssh diag if any
$diag = Join-Path $env:USERPROFILE '.claude\logs\laptop-ssh-diag-latest.txt'
if (Test-Path $diag) {
  Write-Host ''
  Write-Host '=== laptop-ssh-diag-latest (tail) ==='
  Get-Content $diag -Tail 30
}
