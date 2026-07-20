$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../../publish/Get-DeployCredentials.ps1" 2>$null
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
# Load functions from deploy-client-bundles without running main - dot-source carefully
$deploy = Join-Path $ProjectRoot 'publish/deploy-client-bundles.ps1'
# Just build stage manually
$ClientRoot = Join-Path $ProjectRoot 'scripts/client'
$Stage = Join-Path $env:TEMP 'claude-client-bundle-smart-stage'
$Zip = Join-Path $env:TEMP 'claude-client-bundle-smart.zip'
if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'mac') | Out-Null

$win = @(
  'connect.bat','connect.ps1','connect-rider.bat','connect-update.ps1','connect-ui.ps1',
  'connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1'
)
$mac = @('connect.sh','connect-update.sh','git-mode.sh','connect-ui.sh','editor-launch.sh')
# versions
$ver = (Get-Content (Join-Path $ClientRoot 'mac/connect-version.txt') -Raw).Trim()
Set-Content -Path (Join-Path $Stage 'connect-version.txt') -Value $ver -NoNewline
Copy-Item (Join-Path $ClientRoot 'mac/connect-version.txt') (Join-Path $Stage 'mac/connect-version.txt') -Force

foreach ($f in $win) {
  $src = Join-Path $ClientRoot "windows/$f"
  if (Test-Path $src) { Copy-Item $src (Join-Path $Stage $f) -Force }
}
# connect.bat may need connect-version
Copy-Item (Join-Path $ClientRoot 'mac/connect-version.txt') (Join-Path $Stage 'connect-version.txt') -Force
foreach ($f in $mac) {
  $src = Join-Path $ClientRoot "mac/$f"
  if (Test-Path $src) { Copy-Item $src (Join-Path $Stage "mac/$f") -Force }
}
# claude-mount for mac package
$cm = Join-Path $ClientRoot 'mac/claude-mount.sh'
if (-not (Test-Path $cm)) { $cm = Join-Path $ProjectRoot 'scripts/server/claude-mount.sh' }
if (Test-Path $cm) { Copy-Item $cm (Join-Path $Stage 'mac/claude-mount.sh') -Force }

# server extras optional
$srv = Join-Path $Stage 'server'
New-Item -ItemType Directory -Force -Path $srv | Out-Null
foreach ($pair in @(
  @('scripts/server/laptop-exec.sh','laptop-exec.sh'),
  @('scripts/server/laptop-exec-setup.sh','laptop-exec-setup.sh'),
  @('scripts/server/claude-mount.sh','claude-mount.sh'),
  @('scripts/server/claude-git-setup.sh','claude-git-setup.sh')
)) {
  $s = Join-Path $ProjectRoot $pair[0]
  if (Test-Path $s) { Copy-Item $s (Join-Path $srv $pair[1]) -Force }
}

# manifest
$manifest = New-Object System.Collections.Generic.List[string]
Get-ChildItem $Stage -Recurse -File | ForEach-Object {
  $rel = $_.FullName.Substring($Stage.Length).TrimStart('\','/').Replace('\','/')
  if ($rel -ne 'manifest.txt') { $manifest.Add($rel) }
}
$manifest | Sort-Object | Set-Content (Join-Path $Stage 'manifest.txt')

if (Test-Path $Zip) { Remove-Item $Zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($Stage, $Zip)
Write-Output "ZIP=$Zip"
Write-Output "VER=$ver"
Write-Output "SIZE=$((Get-Item $Zip).Length)"
# Copy zip to a path we can scp via... actually write to project tmp for laptop-exec
$out = Join-Path $ProjectRoot 'scripts/tmp/client-bundle-20260717.9.zip'
Copy-Item $Zip $out -Force
Write-Output "OUT=$out"
