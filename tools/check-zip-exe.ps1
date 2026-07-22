Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client.zip'
if (-not (Test-Path $z)) { Write-Host 'no zip'; exit 0 }
$zip = [IO.Compression.ZipFile]::OpenRead($z)
try {
  $e = $zip.Entries | Where-Object { $_.FullName -match 'Claude-Connect\.exe$' } | Select-Object -First 1
  if (-not $e) { Write-Host 'no exe in zip'; return }
  Write-Host ("zip entry={0} len={1}" -f $e.FullName, $e.Length)
  $ms = New-Object IO.MemoryStream
  $s = $e.Open(); $s.CopyTo($ms); $s.Dispose()
  $b = $ms.ToArray()
  $peOff = [BitConverter]::ToInt32($b, 0x3C)
  $sig = [Text.Encoding]::ASCII.GetString($b, $peOff, 4)
  Write-Host ("extracted size={0} sig={1}" -f $b.Length, $sig)
} finally { $zip.Dispose() }
