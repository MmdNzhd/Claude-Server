$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$C = Join-Path $ProjectRoot 'scripts/client'
$Stage = Join-Path $env:TEMP 'claude-client-bundle-smart-stage4'
$Zip = Join-Path $ProjectRoot 'scripts/tmp/client-bundle-20260717.9.zip'
if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'mac') | Out-Null

function Copy-Req([string]$SrcRel, [string]$DstRel) {
  $src = Join-Path $C $SrcRel
  if (-not (Test-Path $src)) { $src = Join-Path $ProjectRoot $SrcRel }
  if (-not (Test-Path $src)) { throw "missing $SrcRel" }
  $dst = Join-Path $Stage $DstRel
  $parent = Split-Path $dst -Parent
  if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  Copy-Item $src $dst -Force
  Write-Output "ok $DstRel"
}

$ver = (Get-Content (Join-Path $C 'mac/connect-version.txt') -Raw).Trim()
Set-Content (Join-Path $Stage 'connect-version.txt') -Value $ver -NoNewline

# Windows flat bundle root (auto-update layout)
Copy-Req 'windows/connect.ps1' 'connect.ps1'
Copy-Req 'windows/connect.bat' 'connect.bat'
Copy-Req 'windows/connect-rider.bat' 'connect-rider.bat'
Copy-Req 'windows/connect-update.ps1' 'connect-update.ps1'
Copy-Req 'windows/connect-diagnostic.ps1' 'connect-diagnostic.ps1'
Copy-Req 'windows/cursor-auth-laptop.ps1' 'cursor-auth-laptop.ps1'
Copy-Req 'connect-ui.ps1' 'connect-ui.ps1'
Copy-Req 'editor-launch.ps1' 'editor-launch.ps1'
Copy-Req 'git-mode.ps1' 'git-mode.ps1'

# Mac
Copy-Req 'mac/connect.sh' 'mac/connect.sh'
Copy-Req 'mac/connect-update.sh' 'mac/connect-update.sh'
Copy-Req 'mac/connect-version.txt' 'mac/connect-version.txt'
Copy-Req 'connect-ui.sh' 'mac/connect-ui.sh'
Copy-Req 'editor-launch.sh' 'mac/editor-launch.sh'
Copy-Req 'git-mode.sh' 'mac/git-mode.sh'
Copy-Req 'scripts/server/claude-mount.sh' 'mac/claude-mount.sh'

$gm = Get-Content (Join-Path $Stage 'mac/git-mode.sh') -Raw
if ($gm -notmatch 'warn_foreign_server_session') { throw 'WARN_FOREIGN missing' }
$cs = Get-Content (Join-Path $Stage 'mac/connect.sh') -Raw
if ($cs -notmatch 'warn_foreign_server_session') { throw 'connect missing call' }

Get-ChildItem $Stage -Recurse -File | ForEach-Object {
  $_.FullName.Substring($Stage.Length).TrimStart('\').Replace('\','/')
} | Sort-Object | Set-Content (Join-Path $Stage 'manifest.txt')

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $Zip) { Remove-Item $Zip -Force }
$z = [System.IO.Compression.ZipFile]::Open($Zip, 'Create')
try {
  Get-ChildItem $Stage -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($Stage.Length).TrimStart('\').Replace('\','/')
    $e = $z.CreateEntry($rel)
    $es = $e.Open()
    try { $fs = [IO.File]::OpenRead($_.FullName); try { $fs.CopyTo($es) } finally { $fs.Dispose() } }
    finally { $es.Dispose() }
  }
} finally { $z.Dispose() }

Write-Output "VER=$ver SIZE=$((Get-Item $Zip).Length)"
$zr = [IO.Compression.ZipFile]::OpenRead($Zip)
$zr.Entries.FullName
$zr.Dispose()
