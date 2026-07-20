$g = Get-Content scripts/client/git-mode.sh
$s = ($g | Select-String -Pattern '^warn_foreign_server_session\(').LineNumber
Write-Output "=== warn_foreign_server_session @$s ==="
for ($i=$s-1; $i -lt [Math]::Min($s+80,$g.Count); $i++) {
  Write-Output ("{0}:{1}" -f ($i+1), $g[$i])
  if ($i -ge $s -and $g[$i] -eq '}') { break }
}
Write-Output "=== sshx quote wrap (mac connect) ==="
Select-String -Path scripts/client/mac/connect.sh -Pattern "bash -lc|remote_cmd|timeout 45" |
  Select-Object -First 15 | ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
Write-Output "=== server conf now ==="
