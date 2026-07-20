from pathlib import Path
p = Path(r"D:\Smart\Claude-Code-Server\scripts\tmp\sepidz_proper_deploy.ps1")
t = p.read_text(encoding="utf-8")
old = """if (Test-Path $zip) { Remove-Item $zip -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
Write-Host \"zip=$((Get-Item $zip).Length)\"
"""
new = """if (Test-Path $zip) { Remove-Item $zip -Force }
$z = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  Get-ChildItem -Path $stage -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($stage.Length).TrimStart('\\')
    $entry = $z.CreateEntry($rel.Replace('\\', '/'))
    $es = $entry.Open()
    try {
      $fs = [System.IO.File]::Open($_.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
      try { $fs.CopyTo($es) } finally { $fs.Dispose() }
    } finally { $es.Dispose() }
  }
} finally { $z.Dispose() }
Write-Host \"zip=$((Get-Item $zip).Length)\"
# sanity list
Add-Type -AssemblyName System.IO.Compression.FileSystem
$check = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
  $names = $check.Entries | ForEach-Object { $_.FullName }
  if ($names -notcontains 'mac/connect.sh') { throw ('zip missing mac/connect.sh; has=' + (($names | Select-Object -First 20) -join ',')) }
  if ($names -notcontains 'connect.ps1') { throw 'zip missing connect.ps1' }
  Write-Host ('zip_entries_ok n=' + $names.Count)
} finally { $check.Dispose() }
"""
if old not in t:
    raise SystemExit('old zip block not found')
p.write_text(t.replace(old, new), encoding='utf-8', newline='\n')
print('patched zip')
