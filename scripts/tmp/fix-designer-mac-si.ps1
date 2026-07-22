Set-Location D:\Smart\Claude-Code-Server
# Show connect-ui.sh enter_connect_single_instance
$lines = Get-Content scripts/client/connect-ui.sh
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'enter_connect_single_instance|exit_connect_single_instance') {
    $end = [Math]::Min($i+35, $lines.Count-1)
    for ($j=$i; $j -le $end; $j++) { Write-Host ("{0}|{1}" -f ($j+1), $lines[$j]) }
    Write-Host '---'
    if ($lines[$i] -match '^exit_connect') { break }
  }
}
# designer win single instance
Select-String -Path scripts/client/users/designer/connect.ps1 -Pattern 'Enter-ConnectSingleInstance|SINGLE_INSTANCE' | ForEach-Object {
  Write-Host ("DESPS:{0}:{1}" -f $_.LineNumber, $_.Line.Trim())
}
# hard assert exact
Select-String -Path scripts/client/tests/test-hard-multi-agent-regressions.ps1 -Pattern 'Designer' | ForEach-Object {
  Write-Host ("HARD:{0}:{1}" -f $_.LineNumber, $_.Line.Trim())
}
