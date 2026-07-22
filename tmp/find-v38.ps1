$ErrorActionPreference='Continue'
foreach ($p in @(
  'D:\Smart\Claude-Code-Server\.test-client-bundle',
  'D:\Smart\Claude-Code-Server\scripts\client\.client-update-staging',
  'C:\Users\Smart\Desktop\Claude-Connect\.client-update-staging'
)) {
  if (Test-Path $p) {
    Write-Output "FOUND $p"
    Get-ChildItem $p -Recurse -Filter connect-version.txt -EA SilentlyContinue | ForEach-Object {
      Write-Output ("  " + $_.FullName + " => " + (Get-Content $_.FullName -Raw).Trim())
    }
  } else {
    Write-Output "MISS $p"
  }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($z in @(
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260721.zip',
  'C:\Users\Smart\Desktop\claude-publish\claude-code-client-20260720.zip'
)) {
  if (-not (Test-Path $z)) { continue }
  $a = [IO.Compression.ZipFile]::OpenRead($z)
  try {
    $a.Entries | Where-Object { $_.FullName -match 'connect-version.txt$' } | Select-Object -First 4 | ForEach-Object {
      $sr = New-Object IO.StreamReader($_.Open())
      $v = $sr.ReadToEnd().Trim(); $sr.Close()
      Write-Output ("ZIP $z :: $($_.FullName) => $v")
    }
  } finally { $a.Dispose() }
}
