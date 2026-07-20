$ErrorActionPreference='Continue'
Write-Host '=== hung/wrong connect processes ==='
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'connect(-update)?\.ps1|force_update' } |
  ForEach-Object {
    Write-Host ("PID={0} age_min={1:N1} cmd={2}" -f $_.ProcessId, ((Get-Date) - $_.CreationDate).TotalMinutes, $_.CommandLine.Substring(0,[Math]::Min(140,$_.CommandLine.Length)))
  }
Write-Host '=== version ==='
Write-Host (Get-Content scripts\client\windows\connect-version.txt -Raw).Trim()
Write-Host ('ship_timed=' + (Select-String -Path scripts\client\windows\connect-update.ps1 -Pattern 'Invoke-SshTimed' -SimpleMatch -Quiet))
Write-Host ('HOME_concat=' + (Select-String -Path scripts\client\windows\connect-update.ps1 -Pattern "'\`"`$HOME/" -SimpleMatch -Quiet))
Write-Host ('sync_timed=' + (Select-String -Path scripts\client\connect-ui.ps1 -Pattern 'Invoke-ConnectLogProcTimed' -SimpleMatch -Quiet))
