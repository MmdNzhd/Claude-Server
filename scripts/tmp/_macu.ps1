Write-Output '=== connect.sh update call site ==='
$c = Get-Content scripts/client/mac/connect.sh
for ($i=0; $i -lt [Math]::Min(100,$c.Count); $i++) { Write-Output ("{0}:{1}" -f ($i+1), $c[$i]) }
Write-Output '=== install_laptop_server_pubkey ==='
$g = Get-Content scripts/client/git-mode.sh
$s = ($g | Select-String -Pattern '^install_laptop_server_pubkey\(').LineNumber
for ($i=$s-1; $i -lt [Math]::Min($s+80,$g.Count); $i++) {
  Write-Output ("{0}:{1}" -f ($i+1), $g[$i])
  if ($i -ge $s -and $g[$i] -eq '}') { break }
}
Write-Output '=== acquire_tunnel_port port formula ==='
Select-String -Path scripts/client/git-mode.sh -Pattern 'PORT=|TUNNEL_SLOT|port_base|20000' |
  Select-Object -First 25 | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
