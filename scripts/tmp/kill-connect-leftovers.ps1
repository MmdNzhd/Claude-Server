Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='cmd.exe'" |
  Where-Object { $_.CommandLine -match 'connect\.(bat|ps1|update)' -or $_.CommandLine -match 'Claude-Connect' } |
  ForEach-Object {
    Write-Host ("KILL pid=$($_.ProcessId) $($_.CommandLine.Substring(0,[Math]::Min(120,$_.CommandLine.Length)))")
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }
Write-Host 'Done kill scan'
