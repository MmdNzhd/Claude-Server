$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$p = Join-Path $root 'publish\publish.ps1'
$t = Get-Content $p -Raw
$needle = '    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }'
$insert = @'
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
'@
if ($t.Contains($needle) -and $t -notmatch 'Add-Type -AssemblyName System\.IO\.Compression\r?\n    Add-Type -AssemblyName System\.IO\.Compression\.FileSystem\r?\n    if \(Test-Path \$ZipPath\)') {
    $t = $t.Replace($needle, $insert)
    Set-Content -Path $p -Value $t -Encoding UTF8 -NoNewline
    Write-Host 'Added Compression assemblies to New-ClientZipFromDirectory'
} else {
    Write-Host 'Already has Compression assemblies or needle missing'
}
