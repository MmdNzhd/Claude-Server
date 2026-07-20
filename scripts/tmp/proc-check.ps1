Write-Host 'Cursor processes:'
Get-Process -Name 'Cursor','cursor' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Id) $($_.ProcessName) started=$($_.StartTime)" }
Write-Host 'SSH processes:'
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
  ForEach-Object { "$($_.ProcessId) $($_.CommandLine.Substring(0, [Math]::Min(180, $_.CommandLine.Length)))" }
Write-Host 'sshd:'
Get-Service sshd -ErrorAction SilentlyContinue | Format-List Status,Name | Out-String
