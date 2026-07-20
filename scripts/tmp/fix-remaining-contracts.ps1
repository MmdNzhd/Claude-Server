Set-Location 'D:\Smart\Claude-Code-Server'

Write-Output '=== tunnel contract expectations vs code ==='
Select-String -Path scripts\tmp\test-tunnel-contracts.ps1 -Pattern 'SoftFailCount|-lt 6|-ge 6|TUNNEL_DROP' | ForEach-Object { $_.Line.Trim() }
Write-Output '--- code ---'
Select-String -Path scripts\client\git-mode.ps1 -Pattern 'TunnelSoftFailCount' | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }

Write-Output '=== log sync WARN/ERROR contract ==='
Select-String -Path scripts\tmp\test-log-sync-contracts.ps1 -Pattern 'WARN|ERROR|Force|sync' | Select-Object -First 40 | ForEach-Object { $_.Line.Trim().Substring(0,[Math]::Min(140,$_.Line.Trim().Length)) }
Write-Output '--- connect-ui Write-ConnectLog sync ---'
Select-String -Path scripts\client\connect-ui.ps1 -Pattern 'function Write-ConnectLog|Sync-ConnectLog|Force|WARN|ERROR' | Select-Object -First 30 | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(120,$_.Line.Trim().Length)))" }

Write-Output '=== askpass ==='
Select-String -Path scripts\client\git-mode.sh -Pattern 'askpass|LAPTOP_ADMIN_PW|SSH_ASKPASS|echo' |
  Where-Object { $_.Line -match 'ASKPASS|ADMIN_PW|askpass' } |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim().Substring(0,[Math]::Min(160,$_.Line.Trim().Length)))" }
