$g = Get-Content scripts/client/git-mode.sh
# print 1155-1220
for ($i=1154; $i -lt 1225 -and $i -lt $g.Count; $i++) {
  Write-Output ("{0}:{1}" -f ($i+1), $g[$i])
}
Write-Output '--- push_server_connect_conf ---'
$s = ($g | Select-String -Pattern '^push_server_connect_conf\(').LineNumber
for ($i=$s-1; $i -lt [Math]::Min($s+40,$g.Count); $i++) {
  Write-Output ("{0}:{1}" -f ($i+1), $g[$i])
  if ($i -ge $s -and $g[$i] -eq '}') { break }
}
