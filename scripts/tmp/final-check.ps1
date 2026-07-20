$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'
Write-Host "mtime=$((Get-Item $log).LastWriteTime)"
Write-Host '=== after 13:04 ==='
Get-Content $log | Where-Object { $_ -match '2026-07-20 13:0[4-9]|2026-07-20 13:1' }
Write-Host ''
Write-Host '=== verdict keys ==='
$lines = Get-Content $log | Where-Object { $_ -match '2026-07-20 13:0[4-9]|2026-07-20 13:1' }
$checks = @{
  'session_v6' = ($lines | Where-Object { $_ -match 'session start v20260720\.6' } | Measure-Object).Count -gt 0
  'multi' = ($lines | Where-Object { $_ -match 'MULTI_INSTANCE' } | Measure-Object).Count -gt 0
  'no_need_admin' = ($lines | Where-Object { $_ -match 'FAIL NEED_ADMIN' } | Measure-Object).Count -eq 0
  'ak_unreadable_skip' = ($lines | Where-Object { $_ -match 'admin_ak unreadable|cannot_read_ak' } | Measure-Object).Count -gt 0
  'has_fail_error' = ($lines | Where-Object { $_ -match '\[ERROR\].*FAIL ' } | Measure-Object).Count
  'ready_or_project' = ($lines | Where-Object { $_ -match 'Ready|Choose-Project|STEP end:.*ok|editor|Tunnel up|Ensure-SessionTunnel' } | Select-Object -Last 5)
}
$checks.GetEnumerator() | ForEach-Object { if ($_.Key -ne 'ready_or_project') { Write-Host ("{0}={1}" -f $_.Key, $_.Value) } }
Write-Host 'progress_tail:'
$checks['ready_or_project'] | ForEach-Object { $_ }
Write-Host ''
Write-Host '=== last 15 of newest session ==='
$sid = ($lines | Where-Object { $_ -match 'session start' } | Select-Object -Last 1)
if ($sid -match '\[([0-9a-f]{12})\]') {
  $s = $Matches[1]
  Write-Host "SID=$s"
  Get-Content $log | Where-Object { $_ -match "\[$s\]" } | Select-Object -Last 20
}
# tunnel
try {
  $tcp = New-Object Net.Sockets.TcpClient
  $ok = $tcp.BeginConnect('127.0.0.1',21002,$null,$null).AsyncWaitHandle.WaitOne(2000)
  if ($ok) { try { $tcp.EndConnect($tcp.Client) } catch {} }
  Write-Host "tunnel_21002=$($tcp.Connected)"
  $tcp.Close()
} catch { Write-Host 'tunnel_21002=False' }
