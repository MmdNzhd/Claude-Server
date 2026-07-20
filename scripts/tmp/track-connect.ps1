$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'
Write-Host "bytes=$((Get-Item $log).Length) mtime=$((Get-Item $log).LastWriteTime)"
Write-Host '=== lines after 12:52 ==='
Get-Content $log | Where-Object { $_ -match '2026-07-20 12:5[2-9]|2026-07-20 13:' } | ForEach-Object { $_ }
Write-Host '=== last 25 any ==='
Get-Content $log -Tail 25
Write-Host '=== connect processes ==='
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '^(cmd|powershell)\.exe$' -and $_.CommandLine -match 'connect' } |
  ForEach-Object { "{0} {1}" -f $_.ProcessId, $_.CommandLine.Substring(0, [Math]::Min(160, $_.CommandLine.Length)) }
try { Get-Process -Id 46836 -ErrorAction Stop | Format-List Id,ProcessName } catch { Write-Host 'pid 46836 gone' }
