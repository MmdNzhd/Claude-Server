$p='D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$lines=Get-Content -LiteralPath $p
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '\$action\s*=') {
    if ($i -ge 1500 -and $i -le 1620) {
      Write-Output ("{0,4}|{1}" -f ($i+1), $lines[$i])
    }
  }
}
Write-Output '--- around action init ---'
for ($i=1480; $i -le 1535; $i++) { Write-Output ("{0,4}|{1}" -f ($i+1), $lines[$i]) }
