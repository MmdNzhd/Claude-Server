
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'ensure-bg|_verify-wmcp' } |
  ForEach-Object {
    Write-Output "KILL $($_.ProcessId)"
    Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue
  }
Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'claude-server' } |
  ForEach-Object {
    Write-Output "KILL_SSH $($_.ProcessId) $($_.CommandLine.Substring(0,[Math]::Min(100,$_.CommandLine.Length)))"
    Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue
  }
Write-Output 'CLEANED'
