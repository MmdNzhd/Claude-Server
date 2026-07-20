Write-Output '=== search 30min / LastClientUpdate / drain ==='
Select-String -LiteralPath 'scripts/client/windows/connect.ps1','scripts/client/windows/connect-update.ps1','scripts/client/windows/connect.bat','scripts/client/git-mode.ps1','docs/client-connect.md' -Pattern '30.?min|LastClient|update.?check|Ensure-Session|drain|ConnectUpdate|CLAUDE_UPDATE' -ErrorAction SilentlyContinue |
  ForEach-Object { "{0}:{1}:{2}" -f ($_.Path -replace '.*\\',''), $_.LineNumber, $_.Line.Trim() }

Write-Output '=== connect.bat update invoke ==='
Get-Content 'scripts/client/windows/connect.bat'

Write-Output '=== forensic UPDATE lines ==='
Select-String -LiteralPath 'scripts/tmp/farzad-connect-20260719.log' -Pattern 'UPDATE:' | ForEach-Object { $_.Line }

Write-Output '=== TUNNEL: connection dropped count ==='
Select-String -LiteralPath 'scripts/tmp/farzad-connect-20260719.log' -Pattern 'TUNNEL: connection dropped|auto reconnect|fallthrough_recover' | ForEach-Object { $_.Line }

Write-Output '=== session start count + ENSURE spawned = real new tunnels ==='
Write-Output ("session_start=" + (Select-String -LiteralPath 'scripts/tmp/farzad-connect-20260719.log' -Pattern '======== session start' | Measure-Object).Count)
Write-Output ("ENSURE_spawned=" + (Select-String -LiteralPath 'scripts/tmp/farzad-connect-20260719.log' -Pattern 'ENSURE_TUNNEL spawned' | Measure-Object).Count)
Write-Output ("ENSURE_reused=" + (Select-String -LiteralPath 'scripts/tmp/farzad-connect-20260719.log' -Pattern 'ENSURE_TUNNEL reused' | Measure-Object).Count)
Write-Output ("ORPHAN_kill=" + (Select-String -LiteralPath 'scripts/tmp/farzad-connect-20260719.log' -Pattern 'ORPHAN_TUNNEL: killing' | Measure-Object).Count)
Write-Output ("TUNNEL_STOP=" + (Select-String -LiteralPath 'scripts/tmp/farzad-connect-20260719.log' -Pattern 'TUNNEL_STOP' | Measure-Object).Count)
Write-Output ("STATUS_OK_tunnel_up=" + (Select-String -LiteralPath 'scripts/tmp/farzad-connect-20260719.log' -Pattern 'STATUS_OK.*tunnel=up' | Measure-Object).Count)
