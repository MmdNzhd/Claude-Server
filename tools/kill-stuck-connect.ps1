Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
  Where-Object {
    $c = $_.CommandLine
    $c -and ($c -match 'connect-boot\.ps1' -or $c -match 'Claude-Connect\\connect\.ps1')
  } |
  ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    Write-Output "killed $($_.ProcessId)"
  }
if (-not $?) { Write-Output 'kill_scan_done' }
