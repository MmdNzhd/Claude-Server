Select-String -Path 'scripts/client/windows/connect.ps1' -Pattern 'bgTunnel|SessionBgTunnel|Ensure-Tunnel|Wait-ForTunnel' |
  Where-Object { $_.LineNumber -ge 1100 -and $_.LineNumber -le 1470 } |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
