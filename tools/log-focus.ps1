$log = Join-Path $env:USERPROFILE ('.config\claude-connect\logs\connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
# Find last "Ready" or project select / Opening Cursor block
$all = Get-Content $log -Tail 400
$idx = -1
for ($i=$all.Count-1; $i -ge 0; $i--) {
  if ($all[$i] -match 'Opening Cursor|OPEN_EDITOR|EDITOR_LAUNCH|skip_remount|Projects|Ai Gap|select project|Ready') { $idx = $i; if ($all[$i] -match 'Opening Cursor|OPEN_EDITOR|EDITOR_LAUNCH') { break } }
}
Write-Host ("focus_from_offset={0} total_tail={1}" -f $idx, $all.Count)
# print last 60 lines always
Write-Host '=== LAST 60 ==='
$all | Select-Object -Last 60 | ForEach-Object { $_ }

Write-Host ''
Write-Host '=== EDITOR/CURSOR/ERROR in last 400 ==='
$all | Where-Object { $_ -match 'EDITOR|Cursor|OPEN_|launch|FAIL|ERROR|timeout|AUTH|sidecar|skip_remount|MOUNT|Tunnel' } | Select-Object -Last 50 | ForEach-Object { $_ }
