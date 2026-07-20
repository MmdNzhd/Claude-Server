$ErrorActionPreference='Continue'
foreach ($procId in @(32368,55160,57084,63656)) {
  Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
  Write-Host ("killed " + $procId)
}
Start-Sleep -Seconds 1
$left = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -and ($_.CommandLine -match 'connect(-update)?\.ps1|force_update') })
Write-Host ("remaining=" + $left.Count)
foreach ($p in $left) {
  Write-Host ("still PID=" + $p.ProcessId + " " + $p.CommandLine.Substring(0,[Math]::Min(120,$p.CommandLine.Length)))
  Stop-Process -Id $p.ProcessId -Force -EA SilentlyContinue
}
Start-Sleep 1
$left2 = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -and ($_.CommandLine -match 'connect(-update)?\.ps1|force_update') })
Write-Host ("remaining_after=" + $left2.Count)
