$p = 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$lines = Get-Content -LiteralPath $p
for ($j = 1555; $j -le 1610; $j++) {
  Write-Output ("{0,4}|{1}" -f ($j+1), $lines[$j])
}
