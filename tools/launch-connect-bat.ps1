$WinDir = 'C:\Users\Smart\Downloads\claude-code-client-20260715\windows'
$bat = Join-Path $WinDir 'connect.bat'
$p = Start-Process -FilePath $bat -WorkingDirectory $WinDir -PassThru
Write-Output "launched pid=$($p.Id)"
[Console]::Out.Flush()
Start-Sleep -Seconds 45
Write-Output 'wait_45s_done'
if ($p.HasExited) { Write-Output "bat_cmd_exit=$($p.ExitCode)" } else { Write-Output 'bat_cmd_still_running' }
