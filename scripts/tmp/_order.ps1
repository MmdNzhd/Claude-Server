$c = Get-Content scripts/client/mac/connect.sh
for ($i=130; $i -lt 320; $i++) {
  if ($i -ge $c.Count) { break }
  $line = $c[$i]
  if ($line -match 'git-mode|initialize_server|Server setup|source |REMOTE_USER|connect.conf|CONNECT_VERSION') {
    Write-Output ("{0}:{1}" -f ($i+1), $line)
  }
}
Write-Output '--- all source lines ---'
Select-String -Path scripts/client/mac/connect.sh -Pattern '^\.|source ' |
  ForEach-Object { "$($_.LineNumber):$($_.Line.Trim())" }
