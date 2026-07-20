$p='D:\Smart\Claude-Code-Server\scripts\client\connect-ui.ps1'
$lines=Get-Content -LiteralPath $p
for ($i=0;$i -lt $lines.Count;$i++) {
  if ($lines[$i] -match 'function Write-ConnectLog\b') {
    for ($j=$i; $j -lt [Math]::Min($i+80,$lines.Count); $j++) {
      Write-Output ("{0,4}|{1}" -f ($j+1), $lines[$j])
      if ($j -gt $i -and $lines[$j] -match '^function ') { break }
    }
  }
}
