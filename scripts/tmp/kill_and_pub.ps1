$ErrorActionPreference='Continue'
$kill = @(32368,55160,57084,63656)
foreach ($pid in $kill) {
  try {
    $p = Get-Process -Id $pid -EA SilentlyContinue
    if ($p) {
      Stop-Process -Id $pid -Force -EA SilentlyContinue
      Write-Host ("killed $pid")
    } else { Write-Host ("gone $pid") }
  } catch { Write-Host ("fail $pid $_") }
}
Start-Sleep -Seconds 1
$left = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
  Where-Object { $_.CommandLine -match 'connect(-update)?\.ps1|force_update' })
Write-Host ("remaining_connect_procs=" + $left.Count)
. .\scripts\client\connect-ui.ps1 | Out-Null
Write-Host 'parse_ok'
$bat = Get-Content .\scripts\client\windows\connect.bat -Raw
if ($bat -notmatch 'CLAUDE_CONNECT_RUN_ID') { throw 'bat missing RUN_ID' }
Write-Host 'bat_ok'
Write-Host ('ver=' + (Get-Content .\scripts\client\windows\connect-version.txt -Raw).Trim())
