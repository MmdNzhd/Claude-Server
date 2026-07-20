$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$ClientRoot = Join-Path $ProjectRoot 'scripts/client'
$Stage = Join-Path $env:TEMP 'claude-client-bundle-smart-stage2'
$Zip = Join-Path $ProjectRoot 'scripts/tmp/client-bundle-20260717.9.zip'
if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'mac') | Out-Null

$ver = (Get-Content (Join-Path $ClientRoot 'mac/connect-version.txt') -Raw).Trim()
Set-Content (Join-Path $Stage 'connect-version.txt') -Value $ver -NoNewline

$win = @('connect.bat','connect.ps1','connect-rider.bat','connect-update.ps1','connect-ui.ps1','connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1')
$mac = @('connect.sh','connect-update.sh','git-mode.sh','connect-ui.sh','editor-launch.sh','connect-version.txt')
foreach ($f in $win) {
  $src = Join-Path $ClientRoot "windows/$f"
  if (Test-Path $src) { Copy-Item $src (Join-Path $Stage $f) -Force }
}
foreach ($f in $mac) {
  $src = Join-Path $ClientRoot "mac/$f"
  if (Test-Path $src) { Copy-Item $src (Join-Path $Stage "mac/$f") -Force }
}
$cm = Join-Path $ProjectRoot 'scripts/server/claude-mount.sh'
if (Test-Path $cm) { Copy-Item $cm (Join-Path $Stage 'mac/claude-mount.sh') -Force }

# Forward-slash zip (Linux unzip compatible)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $Zip) { Remove-Item $Zip -Force }
$zipFile = [System.IO.Compression.ZipFile]::Open($Zip, 'Create')
try {
  Get-ChildItem $Stage -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($Stage.Length).TrimStart('\').Replace('\','/')
    $entry = $zipFile.CreateEntry($rel)
    $es = $entry.Open()
    try {
      $fs = [System.IO.File]::OpenRead($_.FullName)
      try { $fs.CopyTo($es) } finally { $fs.Dispose() }
    } finally { $es.Dispose() }
  }
} finally { $zipFile.Dispose() }

# manifest with forward slashes
$mans = Get-ChildItem $Stage -Recurse -File | ForEach-Object {
  $_.FullName.Substring($Stage.Length).TrimStart('\').Replace('\','/')
} | Sort-Object
# rewrite zip including manifest - simpler append via recreate
$mans | Set-Content (Join-Path $Stage 'manifest.txt')
# recreate with manifest
Remove-Item $Zip -Force
$zipFile = [System.IO.Compression.ZipFile]::Open($Zip, 'Create')
try {
  Get-ChildItem $Stage -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($Stage.Length).TrimStart('\').Replace('\','/')
    $entry = $zipFile.CreateEntry($rel)
    $es = $entry.Open()
    try {
      $fs = [System.IO.File]::OpenRead($_.FullName)
      try { $fs.CopyTo($es) } finally { $fs.Dispose() }
    } finally { $es.Dispose() }
  }
} finally { $zipFile.Dispose() }

Write-Output "VER=$ver SIZE=$((Get-Item $Zip).Length)"
# list a few entries
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z=[System.IO.Compression.ZipFile]::OpenRead($Zip)
$z.Entries | Select-Object -First 15 | ForEach-Object { $_.FullName }
$z.Dispose()
