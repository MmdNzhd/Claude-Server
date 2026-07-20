$lines=Get-Content 'D:\Smart\Claude-Code-Server\scripts\client\windows\connect.ps1'
for ($j=1535; $j -le 1595; $j++) {
  Write-Output ("{0,4}|{1}" -f ($j+1), $lines[$j])
}
