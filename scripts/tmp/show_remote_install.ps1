$i=0
Get-Content 'D:\Smart\Claude-Code-Server\publish\deploy-client-bundles.ps1' | ForEach-Object {
  $i++
  if ($i -ge 190 -and $i -le 280) { "{0}:{1}" -f $i, $_ }
}
