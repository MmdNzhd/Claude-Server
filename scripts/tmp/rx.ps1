$p='D:\Smart\Claude-Code-Server\scripts\client\windows\connect-update.ps1'
Select-String -Path $p -Pattern 'match' | ForEach-Object { Write-Host ("L$($_.LineNumber): $($_.Line)") }
Write-Host '--- byte dump of match lines ---'
$i=0
Get-Content $p | ForEach-Object {
  $i++
  if ($_ -match 'match') {
    $bytes = [Text.Encoding]::UTF8.GetBytes($_)
    Write-Host ("L$i HEX=" + [BitConverter]::ToString($bytes))
    Write-Host ("L$i TXT=$_")
  }
}
Write-Host '--- regex tests ---'
foreach ($rel in @('mac/connect.sh','server/laptop-exec.sh','connect.ps1')) {
  $s = [bool]($rel -match '^server[/\\]')
  $m = [bool]($rel -match '^mac[/\\](.+)$')
  Write-Host "rel=$rel server=$s mac=$m"
}
