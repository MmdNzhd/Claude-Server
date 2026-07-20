# Kill frozen Smart connect client fighting Sepidz tunnel
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -match 'claude-code-client-.*\\windows\\connect\.ps1' } |
  ForEach-Object {
    Write-Host ("KILL pid={0} {1}" -f $_.ProcessId, $_.CommandLine.Substring(0,[Math]::Min(160,$_.CommandLine.Length)))
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
  }
Start-Sleep -Seconds 2
$ssh = @(Get-Process ssh -EA SilentlyContinue)
Write-Host ("ssh_count_after={0}" -f $ssh.Count)
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -match 'connect\.ps1' } |
  ForEach-Object { Write-Host ("still: pid={0} {1}" -f $_.ProcessId, $_.CommandLine.Substring(0,[Math]::Min(160,$_.CommandLine.Length))) }
