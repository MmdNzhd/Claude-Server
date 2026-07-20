$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'
Write-Host "bytes=$((Get-Item $log).Length) mtime=$((Get-Item $log).LastWriteTime)"
Write-Host '=== after 12:53 ==='
Get-Content $log | Where-Object { $_ -match '2026-07-20 12:5[3-9]|2026-07-20 13:|2026-07-20 12:5[4-9]' }
Write-Host '=== FAIL/UPDATE/MULTI/session recent ==='
Select-String -Path $log -Pattern 'FAIL |UPDATE:|MULTI_INSTANCE|session start|BOOTSTRAP|NEED_ADMIN|admin_fix|20260720\.[234]|EXIT_WAIT' |
  Select-Object -Last 40 | ForEach-Object { $_.Line }
Write-Host '=== connect procs ==='
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'connect\.(bat|ps1)' } |
  ForEach-Object { "{0} {1}" -f $_.ProcessId, ($_.CommandLine.Substring(0,[Math]::Min(140,$_.CommandLine.Length))) }
Write-Host '=== task status ==='
cmd /c 'schtasks /Query /TN ClaudeConnectManualTrack /V /FO LIST' | Select-String 'Status|Last Run|Last Result|Task To Run'
Write-Host '=== local ver now ==='
Get-Content 'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect-version.txt'
