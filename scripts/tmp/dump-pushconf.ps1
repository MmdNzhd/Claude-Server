$p = 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
$lines = Get-Content -LiteralPath $p
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'function Push-ServerConnectConf') {
    $start = $i
    break
  }
}
Write-Output "START=$($start+1)"
for ($j = $start; $j -lt [Math]::Min($start+130, $lines.Count); $j++) {
  Write-Output ("{0,4}|{1}" -f ($j+1), $lines[$j])
}
