$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$ClientRoot = Join-Path $ProjectRoot 'scripts/client'
$Stage = Join-Path $env:TEMP 'claude-client-bundle-smart-stage3'
$Zip = Join-Path $ProjectRoot 'scripts/tmp/client-bundle-20260717.9.zip'
if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'mac') | Out-Null

$ver = (Get-Content (Join-Path $ClientRoot 'mac/connect-version.txt') -Raw).Trim()
Set-Content (Join-Path $Stage 'connect-version.txt') -Value $ver -NoNewline

$copies = @(
  @{ Src = 'windows/connect.bat'; Dst = 'connect.bat' },
  @{ Src = 'windows/connect.ps1'; Dst = 'connect.ps1' },
  @{ Src = 'windows/connect-rider.bat'; Dst = 'connect-rider.bat' },
  @{ Src = 'windows/connect-update.ps1'; Dst = 'connect-update.ps1' },
  @{ Src = 'windows/connect-ui.ps1'; Dst = 'connect-ui.ps1' },
  @{ Src = 'windows/connect-diagnostic.ps1'; Dst = 'connect-diagnostic.ps1' },
  @{ Src = 'windows/editor-launch.ps1'; Dst = 'editor-launch.ps1' },
  @{ Src = 'windows/git-mode.ps1'; Dst = 'git-mode.ps1' },
  @{ Src = 'windows/cursor-auth-laptop.ps1'; Dst = 'cursor-auth-laptop.ps1' },
  @{ Src = 'mac/connect.sh'; Dst = 'mac/connect.sh' },
  @{ Src = 'mac/connect-update.sh'; Dst = 'mac/connect-update.sh' },
  @{ Src = 'mac/connect-ui.sh'; Dst = 'mac/connect-ui.sh' },
  @{ Src = 'mac/editor-launch.sh'; Dst = 'mac/editor-launch.sh' },
  @{ Src = 'mac/connect-version.txt'; Dst = 'mac/connect-version.txt' },
  @{ Src = 'git-mode.sh'; Dst = 'mac/git-mode.sh' },
  @{ Src = 'git-mode.ps1'; Dst = 'git-mode.ps1' }
)
foreach ($c in $copies) {
  $src = Join-Path $ClientRoot $c.Src
  if (-not (Test-Path $src)) { throw "missing $src" }
  $dst = Join-Path $Stage $c.Dst
  $parent = Split-Path $dst -Parent
  if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  Copy-Item $src $dst -Force
}
$cm = Join-Path $ProjectRoot 'scripts/server/claude-mount.sh'
Copy-Item $cm (Join-Path $Stage 'mac/claude-mount.sh') -Force

# Verify critical symbol
$gm = Get-Content (Join-Path $Stage 'mac/git-mode.sh') -Raw
if ($gm -notmatch 'warn_foreign_server_session') { throw 'git-mode.sh missing warn_foreign_server_session' }
$cs = Get-Content (Join-Path $Stage 'mac/connect.sh') -Raw
if ($cs -notmatch 'warn_foreign_server_session') { throw 'connect.sh missing warn_foreign call' }

Get-ChildItem $Stage -Recurse -File |
  ForEach-Object { $_.FullName.Substring($Stage.Length).TrimStart('\').Replace('\','/') } |
  Sort-Object | Set-Content (Join-Path $Stage 'manifest.txt')

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $Zip) { Remove-Item $Zip -Force }
$z = [System.IO.Compression.ZipFile]::Open($Zip, 'Create')
try {
  Get-ChildItem $Stage -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($Stage.Length).TrimStart('\').Replace('\','/')
    $e = $z.CreateEntry($rel)
    $es = $e.Open()
    try {
      $fs = [IO.File]::OpenRead($_.FullName)
      try { $fs.CopyTo($es) } finally { $fs.Dispose() }
    } finally { $es.Dispose() }
  }
} finally { $z.Dispose() }

Write-Output "VER=$ver SIZE=$((Get-Item $Zip).Length)"
Write-Output 'entries:'
$zr = [IO.Compression.ZipFile]::OpenRead($Zip)
$zr.Entries | ForEach-Object { $_.FullName }
$zr.Dispose()
