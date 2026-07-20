$ErrorActionPreference='Continue'
$path = 'scripts/client/git-mode.ps1'
$lines = Get-Content $path
for ($i=0; $i -lt $lines.Count; $i++) {
  $l = $lines[$i]
  if ($l -match 'function\s+(Test-TunnelUp|Get-TunnelBanner|Sync-Tunnel|Ensure-Tunnel|Test-TunnelBanner|Wait-Tunnel)' -or
      $l -match 'TUNNEL_BANNER_BEGIN|connection dropped|bg_alive|dev/tcp/127') {
    '{0}: {1}' -f ($i+1), $l.TrimEnd()
  }
}
Write-Output '---- CURRENT VERSION ----'
Select-String -Path 'scripts/client/windows/connect.ps1','scripts/client/connect.ps1' -Pattern 'ConnectVersion|CONNECT_VERSION' -ErrorAction SilentlyContinue | Select-Object -First 5 | ForEach-Object { $_.Line }
