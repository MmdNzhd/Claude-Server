$ErrorActionPreference='Continue'
# Find how diagnostic decides TUNNEL_DOWN vs local_port_open
$files = @(
  'scripts/client/connect-diagnostic.ps1',
  'scripts/client/windows/connect-diagnostic.ps1'
) | Where-Object { Test-Path $_ }
foreach ($f in $files) {
  Write-Output "==== $f ===="
  $lines = Get-Content $f
  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'TUNNEL_DOWN|local_port_open|Get-TunnelBanner|Test-TunnelUp|banner') {
      '{0}: {1}' -f ($i+1), $lines[$i].TrimEnd()
    }
  }
}
Write-Output '==== Sync-SessionTunnelProcess 30s gate in current repo ===='
Select-String -Path 'scripts/client/git-mode.ps1' -Pattern 'LastForwardProbeAt|bg_alive_forward|Test-TunnelUp|Get-TunnelBanner' |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }

Write-Output '==== session loop Test-Tunnel in connect.ps1 ===='
Select-String -Path 'scripts/client/windows/connect.ps1' -Pattern 'Test-TunnelUp|Sync-SessionTunnel|connection dropped|KeyAvailable' |
  ForEach-Object { '{0}: {1}' -f $_.LineNumber, $_.Line.Trim() }
