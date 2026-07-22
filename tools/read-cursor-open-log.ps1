$ErrorActionPreference='Continue'
$logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
$day = Get-Date -Format 'yyyyMMdd'
$log = Join-Path $logDir ("connect-{0}.log" -f $day)
Write-Host ("log={0}" -f $log)
if (-not (Test-Path $log)) {
  $log = (Get-ChildItem $logDir -Filter 'connect-*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
  Write-Host ("fallback={0}" -f $log)
}
# Last ~200 lines focusing on editor/cursor/auth/tunnel/project select
Get-Content $log -Tail 250 | Where-Object {
  $_ -match 'CURSOR|EDITOR|Opening|auth|AUTH|mount|TUNNEL|GITMODE|PROXY|project|Ai Gap|gap-summay|FAIL|ERROR|WARN|hang|timeout|skip_remount|Syncing|Ready|slot|port 20028|Remote'
} | Select-Object -Last 120

Write-Host ''
Write-Host '=== last 40 raw ==='
Get-Content $log -Tail 40

Write-Host ''
Write-Host '=== cursor processes ==='
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $cl=[string]$_.CommandLine
  $n=$_.Name
  $n -match 'Cursor|cursor' -or $cl -match 'Cursor\.exe|ClaudeServerCursorProfile|Ai Gap|ai-gap'
} | ForEach-Object {
  $c=[string]$_.CommandLine
  if ($c.Length -gt 200) { $c = $c.Substring(0,200)+'...' }
  Write-Host ("pid={0} name={1} {2}" -f $_.ProcessId, $_.Name, $c)
}
