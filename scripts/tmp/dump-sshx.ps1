$p = 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
$lines = Get-Content -LiteralPath $p
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^function SshX') { $start = $i; break }
}
Write-Output "SshX_START=$($start+1)"
for ($j = $start; $j -lt [Math]::Min($start+80, $lines.Count); $j++) {
  Write-Output ("{0,4}|{1}" -f ($j+1), $lines[$j])
  if ($j -gt $start -and $lines[$j] -match '^function ') { break }
}
