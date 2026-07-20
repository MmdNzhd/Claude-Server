$ErrorActionPreference='Continue'
Write-Output "ConnectVersion:"
Select-String -Path 'scripts/client/windows/connect.ps1' -Pattern "ConnectVersion\s*=" | Select-Object -First 1 | ForEach-Object { $_.Line }
Write-Output "CONNECT_VERSION mac:"
Select-String -Path 'scripts/client/mac/connect.sh' -Pattern "^CONNECT_VERSION=" | Select-Object -First 1 | ForEach-Object { $_.Line }
Write-Output "--- git-mode.ps1 sizes ---"
(Get-Item 'scripts/client/git-mode.ps1').Length
Write-Output "--- Clear-TunnelBannerCache ---"
Select-String -Path 'scripts/client/git-mode.ps1' -Pattern 'function Clear-TunnelBannerCache|TunnelBannerCache' |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
Write-Output "--- mac Get-TunnelBanner equivalent? ---"
Select-String -Path 'scripts/client/git-mode.sh','scripts/client/mac/connect.sh' -Pattern 'dev/tcp|TUNNEL_BANNER|Test-Tunnel' -ErrorAction SilentlyContinue |
  Select-Object -First 20 | ForEach-Object { '{0}:{1}: {2}' -f ($_.Path|Split-Path -Leaf), $_.LineNumber, $_.Line.Trim() }
