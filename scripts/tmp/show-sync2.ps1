$g=Get-Content 'scripts/client/git-mode.ps1'
Write-Output '=== Test-TunnelBannerIsWindows ==='
182..195 | ForEach-Object { '{0}: {1}' -f $_, $g[$_-1] }
Write-Output '=== Sync-SessionTunnelProcess ==='
355..410 | ForEach-Object { '{0}: {1}' -f $_, $g[$_-1] }
Write-Output '=== PID lifecycle in log ==='
$log='C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260717\windows\connect.log'
Select-String -Path $log -Pattern '38352|TUNNEL_STOP: killing|killing orphan|killing bg' -SimpleMatch:$false |
  Select-Object -First 40 |
  ForEach-Object { 'L{0}|{1}' -f $_.LineNumber, $_.Line }
Write-Output '=== Drop1 timing deltas ==='
# parse key timestamps
$need=@(
  '17:05:03.726','17:05:16.467','17:05:17.009','17:05:21.946','17:05:22.496','17:05:22.522','17:05:22.531','17:05:22.560','17:05:22.599'
)
