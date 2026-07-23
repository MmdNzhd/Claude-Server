$ErrorActionPreference = 'Continue'
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260722.log'
Write-Output '==== MULTI_INSTANCE last 40 ===='
Select-String -LiteralPath $log -Pattern 'MULTI_INSTANCE' | Select-Object -Last 40 | ForEach-Object { $_.Line }
Write-Output '==== session 6acbca full ERROR/WARN/STEP ===='
Select-String -LiteralPath $log -Pattern '\[6acbca330f4c\]' |
  Where-Object { $_.Line -match 'STEP end|ERROR|WARN|FAIL|EXIT|REMOTE_USER|CONNECT_VERSION|session start|smarttest|Path is required|AUTH' } |
  ForEach-Object { $_.Line }
Write-Output '==== sidecar watchdog count ===='
@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'claude-connect-sidecar' }).Count
Write-Output '==== Claude-Connect.exe processes ===='
Get-Process -Name 'Claude-Connect' -EA SilentlyContinue | Format-Table Id,StartTime -AutoSize | Out-String
