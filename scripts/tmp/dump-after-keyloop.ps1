$p='D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
$lines=Get-Content -LiteralPath $p
for ($j=1595; $j -le 1720; $j++) {
  Write-Output ("{0,4}|{1}" -f ($j+1), $lines[$j])
}
Write-Output '==== PushConf head ===='
$g=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\git-mode.ps1'
for ($i=0;$i -lt $g.Count;$i++) {
  if ($g[$i] -match '^function Push-ServerConnectConf') {
    for ($j=$i; $j -lt $i+75; $j++) { Write-Output ("{0,4}|{1}" -f ($j+1), $g[$j]) }
    break
  }
}
Write-Output '==== versions ===='
Get-Content D:\Smart\Claude-Code-Server\scripts\client\windows\connect-version.txt
