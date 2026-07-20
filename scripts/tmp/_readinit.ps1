$lines = Get-Content scripts/client/git-mode.sh
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'initialize_server_session|INIT_SERVER_SESSION_ERROR|could not configure') {
    Write-Output ("{0}:{1}" -f ($i+1), $lines[$i])
  }
}
# print function body around initialize_server_session
$start = ($lines | Select-String -Pattern '^initialize_server_session\(' | Select-Object -First 1).LineNumber
if ($start) {
  Write-Output "--- function from $start ---"
  for ($i=$start-1; $i -lt [Math]::Min($start+120, $lines.Count); $i++) {
    Write-Output ("{0}:{1}" -f ($i+1), $lines[$i])
    if ($i -gt $start -and $lines[$i] -match '^[a-z_]+\(\)|^}') { if ($lines[$i] -eq '}' ) { break } }
  }
}
