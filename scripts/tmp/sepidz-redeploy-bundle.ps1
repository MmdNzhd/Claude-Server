#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. (Join-Path $root 'publish\Get-DeployCredentials.ps1')

$stage = Join-Path $env:TEMP 'claude-bundle-sepidz-stage'
$zipPath = Join-Path $env:TEMP 'claude-client-bundle-sepidz.zip'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path (Join-Path $stage 'mac')
$null = New-Item -ItemType Directory -Force -Path (Join-Path $stage 'server\cursor-rules')
$null = New-Item -ItemType Directory -Force -Path (Join-Path $stage 'server\skills\laptop-exec')
$null = New-Item -ItemType Directory -Force -Path (Join-Path $stage 'server\cursor-hooks')

$copies = @(
  @('scripts\client\windows\connect.bat','connect.bat'),
  @('scripts\client\windows\connect-version.txt','connect-version.txt'),
  @('scripts\client\windows\connect.ps1','connect.ps1'),
  @('scripts\client\windows\connect-rider.bat','connect-rider.bat'),
  @('scripts\client\windows\connect-update.ps1','connect-update.ps1'),
  @('scripts\client\windows\connect-diagnostic.ps1','connect-diagnostic.ps1'),
  @('scripts\client\connect-ui.ps1','connect-ui.ps1'),
  @('scripts\client\editor-launch.ps1','editor-launch.ps1'),
  @('scripts\client\git-mode.ps1','git-mode.ps1'),
  @('scripts\client\cursor-auth-laptop.ps1','cursor-auth-laptop.ps1'),
  @('scripts\client\mac\connect.sh','mac\connect.sh'),
  @('scripts\client\mac\connect-update.sh','mac\connect-update.sh'),
  @('scripts\client\windows\connect-version.txt','mac\connect-version.txt'),
  @('scripts\client\git-mode.sh','mac\git-mode.sh'),
  @('scripts\client\connect-ui.sh','mac\connect-ui.sh'),
  @('scripts\client\editor-launch.sh','mac\editor-launch.sh'),
  @('scripts\server\claude-mount.sh','mac\claude-mount.sh'),
  @('scripts\server\laptop-exec.sh','server\laptop-exec.sh'),
  @('scripts\server\laptop-exec-setup.sh','server\laptop-exec-setup.sh'),
  @('scripts\server\claude-mount.sh','server\claude-mount.sh'),
  @('scripts\server\claude-git-setup.sh','server\claude-git-setup.sh'),
  @('scripts\server\cursor-rules\laptop-exec.mdc','server\cursor-rules\laptop-exec.mdc'),
  @('scripts\server\skills\laptop-exec\SKILL.md','server\skills\laptop-exec\SKILL.md'),
  @('scripts\server\cursor-hooks\laptop-exec-guard.sh','server\cursor-hooks\laptop-exec-guard.sh'),
  @('scripts\server\cursor-hooks\hooks-user.json','server\cursor-hooks\hooks-user.json')
)
foreach ($pair in $copies) {
  $src = Join-Path $root $pair[0]
  $dst = Join-Path $stage $pair[1]
  if (-not (Test-Path $src)) { throw "missing $src" }
  $parent = Split-Path $dst -Parent
  if (-not (Test-Path $parent)) { $null = New-Item -ItemType Directory -Force -Path $parent }
  Copy-Item $src $dst -Force
}
Get-ChildItem $stage -Recurse -File | ForEach-Object {
  $_.FullName.Substring($stage.Length).TrimStart('\').Replace('\','/')
} | Sort-Object | Set-Content (Join-Path $stage 'manifest.txt') -Encoding ascii

# Zip with forward-slash entries (Linux unzip compatible)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  Get-ChildItem -Path $stage -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($stage.Length).TrimStart('\').Replace('\', '/')
    $entry = $zip.CreateEntry($rel)
    $out = $entry.Open()
    try {
      $fs = [System.IO.File]::OpenRead($_.FullName)
      try { $fs.CopyTo($out) } finally { $fs.Dispose() }
    } finally { $out.Dispose() }
  }
} finally { $zip.Dispose() }

$z = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
  $names = @($z.Entries | ForEach-Object { $_.FullName })
  Write-Host ("zip entries={0} has_mac_connect={1}" -f $names.Count, ($names -contains 'mac/connect.sh'))
  if (-not ($names -contains 'mac/connect.sh')) { throw 'zip missing mac/connect.sh' }
} finally { $z.Dispose() }

$ver = (Get-Content (Join-Path $stage 'connect-version.txt') -Raw).Trim()
$server = Get-SepidzServerTarget
Write-Host "upload+install v$ver -> $server"

& ssh -o BatchMode=yes -o ConnectTimeout=15 $server "mkdir -p ~/claude-client-bundle-deploy"
& scp -o BatchMode=yes -o ConnectTimeout=60 -q $zipPath "${server}:~/claude-client-bundle-deploy/bundle.zip"
if ($LASTEXITCODE -ne 0) { throw 'scp failed' }

$remote = @'
set -e
# quick peek
python3 - <<'PY'
import zipfile
z=zipfile.ZipFile('/home/sepidz/claude-client-bundle-deploy/bundle.zip')
print('remote_zip_sample', [n for n in z.namelist() if 'connect' in n][:8])
PY
sudo -n /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh "$HOME/claude-client-bundle-deploy/bundle.zip"
echo VER=$(tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt)
'@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
& ssh -o BatchMode=yes -o ConnectTimeout=60 $server "echo $b64 | base64 -d | bash"
if ($LASTEXITCODE -ne 0) { throw "install failed $LASTEXITCODE" }

$remoteVer = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $server "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt").Trim()
Write-Host "REMOTE_VERSION=$remoteVer"
if ($remoteVer -ne $ver) { throw "mismatch expected=$ver got=$remoteVer" }
Write-Host 'SEPIDZ_DEPLOY_OK'
