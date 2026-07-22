$ErrorActionPreference='Continue'
$logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$day = Get-Date -Format 'yyyyMMdd'
$log = Join-Path $logDir ("connect-{0}.log" -f $day)
Write-Host ("log={0}" -f $log)
if (-not (Test-Path $log)) {
  $log = (Get-ChildItem $logDir -Filter 'connect-*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
  Write-Host ("fallback={0}" -f $log)
}
Write-Host ("size={0}" -f (Get-Item $log).Length)
Write-Host ''
Write-Host '=== last 120 lines (Cursor/open/mount/tunnel/FAIL) ==='
Get-Content $log -Tail 250 | Where-Object {
  $_ -match 'Cursor|OPEN|editor|launch|mount|tunnel|FAIL|ERROR|WARN|AUTH|PROXY|GITMODE|skip_remount|Opening|Ready|project|Ai Gap|stuck|timeout|sidecar|SSH'
} | Select-Object -Last 120

Write-Host ''
Write-Host '=== last 40 raw lines ==='
Get-Content $log -Tail 40

Write-Host ''
Write-Host '=== cursor processes ==='
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $n=$_.Name; $c=[string]$_.CommandLine
  $n -match '(?i)cursor' -or $c -match '(?i)Cursor|claude-connect|connect-boot|connect\.ps1'
} | ForEach-Object {
  $c=[string]$_.CommandLine
  if ($c.Length -gt 160) { $c = $c.Substring(0,160)+'...' }
  Write-Host ("pid={0} name={1} {2}" -f $_.ProcessId, $_.Name, $c)
}
