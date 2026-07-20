$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'
Write-Host "mtime=$((Get-Item $log).LastWriteTime) bytes=$((Get-Item $log).Length)"
Write-Host '=== session 12:58+ ==='
Get-Content $log | Where-Object { $_ -match '2026-07-20 12:5[8-9]|2026-07-20 13:' }
Write-Host '=== FAIL lines today last 15 ==='
Select-String -Path $log -Pattern '\[ERROR\].*FAIL |FAIL NEED|FAIL ADMIN|MULTI_INSTANCE|swap_|up_to_date|available v|session start v20260720' |
  Select-Object -Last 20 | ForEach-Object { $_.Line }
Write-Host '=== procs ==='
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match '20260717\\windows\\connect' } |
  ForEach-Object { "{0} {1}" -f $_.ProcessId, $_.CommandLine.Substring(0,[Math]::Min(100,$_.CommandLine.Length)) }
