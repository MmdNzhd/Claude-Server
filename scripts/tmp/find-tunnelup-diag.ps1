Select-String -Path 'scripts/client/connect-diagnostic.ps1','scripts/client/windows/connect.ps1' -Pattern 'TunnelUp|local_port_open|localPortOpen|VERDICT' |
  ForEach-Object { '{0}:{1}: {2}' -f ($_.Path | Split-Path -Leaf), $_.LineNumber, $_.Line.Trim() }
