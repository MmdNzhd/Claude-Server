# connect.sh: when is update vs initialize_server_session
Select-String -Path scripts/client/mac/connect.sh -Pattern 'connect-update|initialize_server_session|Server setup|CONNECT_VERSION' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
Write-Output '--- initialize_server_session body ---'
$lines = Get-Content scripts/client/git-mode.sh
$start = ($lines | Select-String -Pattern '^initialize_server_session\(').LineNumber
for ($i=$start-1; $i -lt [Math]::Min($start+100, $lines.Count); $i++) {
  Write-Output ("{0}:{1}" -f ($i+1), $lines[$i])
  if ($i -ge $start -and $lines[$i] -match '^}' ) { break }
}
