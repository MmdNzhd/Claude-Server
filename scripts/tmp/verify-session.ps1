$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'
$sid = '537b012c92c0'
Write-Host "=== ALL lines for session $sid ==="
Get-Content $log | Where-Object { $_ -match "\[$sid\]" }
Write-Host ''
Write-Host '=== lines after 12:58:54 (any session) ==='
Get-Content $log | Where-Object { $_ -match '2026-07-20 12:59|2026-07-20 13:|2026-07-20 12:5[89]' } | Select-Object -Last 80
Write-Host ''
Write-Host '=== FAIL/ERROR/admin/Ready recent ==='
Select-String -Path $log -Pattern 'FAIL |\[ERROR\]|admin_fix|ADMIN_|waiting_uac|Ready|MULTI_INSTANCE|session start|session end|EXIT_WAIT|TUNNEL|STEP end' |
  Where-Object { $_.Line -match '2026-07-20 12:5[89]|2026-07-20 13:' } |
  ForEach-Object { $_.Line }
Write-Host ''
Write-Host '=== connect procs ==='
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'connect\.(bat|ps1)' -and $_.CommandLine -match 'claude-code-client' } |
  ForEach-Object { "{0} {1}" -f $_.ProcessId, $_.CommandLine.Substring(0,[Math]::Min(130,$_.CommandLine.Length)) }
Write-Host ''
Write-Host '=== version on disk ==='
Get-Content 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect-version.txt'
$adminAk = 'C:\ProgramData\ssh\administrators_authorized_keys'
Write-Host "admin_keys_exists=$(Test-Path $adminAk)"
if (Test-Path $adminAk) {
  $pub = (Get-Content (Join-Path $env:USERPROFILE '.ssh\claude_laptop.pub') -ErrorAction SilentlyContinue)
  # server key is on server; check file non-empty
  Write-Host "admin_keys_bytes=$((Get-Item $adminAk).Length)"
  Write-Host "admin_keys_lines=$((Get-Content $adminAk | Measure-Object).Count)"
}
# tunnel
try {
  $tcp = New-Object Net.Sockets.TcpClient
  $ok = $tcp.BeginConnect('127.0.0.1',21002,$null,$null).AsyncWaitHandle.WaitOne(1500)
  if ($ok) { $tcp.EndConnect($tcp) } else { }
  Write-Host "tunnel_21002_open=$($tcp.Connected)"
  $tcp.Close()
} catch { Write-Host "tunnel_21002_open=False err=$($_.Exception.Message)" }
