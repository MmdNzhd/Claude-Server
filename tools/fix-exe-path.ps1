$paths = @(
  (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\Claude-Connect.exe'),
  (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe'),
  (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client\windows\Claude-Connect.exe')
)
foreach ($p in $paths) {
  if (Test-Path $p) {
    $i = Get-Item $p
    $h = (Get-FileHash $p -Algorithm SHA256).Hash
    Write-Host ("{0} len={1} sha={2}" -f $p, $i.Length, $h)
  } else { Write-Host ("missing {0}" -f $p) }
}
