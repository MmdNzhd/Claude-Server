$g=Get-Content 'scripts/client/git-mode.ps1'
181..195 | ForEach-Object { '{0}: {1}' -f $_, $g[$_-1] }
Write-Output '--- Test-TunnelBannerIsWindows ---'
220..230 | ForEach-Object { '{0}: {1}' -f $_, $g[$_-1] }
Write-Output '--- Sync-SessionTunnelProcess ---'
355..410 | ForEach-Object { '{0}: {1}' -f $_, $g[$_-1] }
Write-Output '--- connect after diagnostic into wait loop ---'
$c=Get-Content 'scripts/client/windows/connect.ps1'
600..680 | ForEach-Object { '{0}: {1}' -f $_, $c[$_-1] }
Write-Output '---'
1420..1460 | ForEach-Object { '{0}: {1}' -f $_, $c[$_-1] }
# Why bg lost on drop1: search Clear-TunnelBannerCache / SessionBgTunnel = null
Select-String -Path 'scripts/client/git-mode.ps1','scripts/client/windows/connect.ps1','scripts/client/connect-diagnostic.ps1' -Pattern 'SessionBgTunnel\s*=|BgTunnel\.Value\s*=\s*\$null|Clear-TunnelBannerCache' |
  ForEach-Object { '{0}:{1}: {2}' -f ($_.Path|Split-Path -Leaf), $_.LineNumber, $_.Line.Trim() }
