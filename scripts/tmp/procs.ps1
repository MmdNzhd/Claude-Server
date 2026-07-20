Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -match 'connect' } |
  ForEach-Object {
    $age = ((Get-Date) - $_.CreationDate).TotalSeconds
    Write-Host ("PID={0} age={1:N0}s" -f $_.ProcessId, $age)
    Write-Host ("  " + $_.CommandLine.Substring(0, [Math]::Min(200, $_.CommandLine.Length)))
  }
$ssh = @(Get-Process ssh -EA SilentlyContinue)
Write-Host ("ssh_count={0}" -f $ssh.Count)
