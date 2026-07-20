Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $env:TEMP 'claude-sepidz-bundle.zip'
if (-not (Test-Path $zip)) { Write-Host 'no local zip - run upload first'; exit 1 }
$z = [System.IO.Compression.ZipFile]::OpenRead($zip)
$z.Entries | ForEach-Object { $_.FullName } | Sort-Object
$z.Dispose()
