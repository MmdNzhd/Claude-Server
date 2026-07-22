$ErrorActionPreference = 'Continue'
$log = Join-Path $env:USERPROFILE '.config\claude-connect\logs\connect-20260720.log'

Write-Host '=== sessions after 16:50 (BOOTSTRAP / session start / FAIL) ==='
Select-String -LiteralPath $log -Pattern 'BOOTSTRAP:|session start v|FAIL |LAUNCH_KILL|soft-stop|taskkill|Stop-Process|Kill-|AUTH_RELAUNCH|git hide|Access to the path|UNHANDLED|TUNNEL_DROP|RECOVERY_|did not come up|EDITOR_SEEN_CLEAR|cursor_running' |
  Where-Object { $_.Line -match '\[2026-07-20 1[67]:' } |
  ForEach-Object { $_.Line.Substring(0, [Math]::Min(280, $_.Line.Length)) }

Write-Host ''
Write-Host '=== concurrent session ids 16:50-17:05 ==='
Select-String -LiteralPath $log -Pattern '\[2026-07-20 1[67]:[0-5][0-9]:' |
  ForEach-Object {
    if ($_.Line -match '\[([0-9a-f]{12})\]') { $Matches[1] }
  } | Group-Object | Sort-Object Count -Desc | Select-Object -First 15 |
  ForEach-Object { '{0,5} {1}' -f $_.Count, $_.Name }

Write-Host ''
Write-Host '=== LAUNCH_KILL / soft-stop / kill anywhere today ==='
$n1 = @(Select-String -LiteralPath $log -Pattern 'LAUNCH_KILL|soft-stop|taskkill|Stop-Process|Kill-Cursor|AUTH_RELAUNCH|auth_relaunch').Count
Write-Host "kill-related hits=$n1"
Select-String -LiteralPath $log -Pattern 'LAUNCH_KILL|soft-stop|taskkill|Kill-Cursor|AUTH_RELAUNCH|auth_relaunch|PROC_START: mode=' |
  Select-Object -Last 30 | ForEach-Object { $_.Line.Substring(0, [Math]::Min(260, $_.Line.Length)) }

Write-Host ''
Write-Host '=== git hide / Access denied ==='
Select-String -LiteralPath $log -Pattern 'git hide|Access to the path|\.git. is denied|close Cursor' |
  Select-Object -Last 20 | ForEach-Object { $_.Line.Substring(0, [Math]::Min(300, $_.Line.Length)) }

Write-Host ''
Write-Host '=== UNHANDLED / Pid ==='
Select-String -LiteralPath $log -Pattern 'UNHANDLED|read-only|Pid' |
  Select-Object -Last 15 | ForEach-Object { $_.Line.Substring(0, [Math]::Min(300, $_.Line.Length)) }
