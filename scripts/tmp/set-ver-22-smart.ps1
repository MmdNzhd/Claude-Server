$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. (Join-Path $root 'publish\bump-connect-version.ps1')
. (Join-Path $root 'publish\Get-DeployCredentials.ps1')

# Freeze Smart auto-update at .22 (same date family as current tree).
# Clients already on .32+ will NOT update (remote not newer).
# Clients below .22 get one update to .22 then stop.
$Version = '20260717.22'
Write-Host "Setting repo connect version -> $Version"
Set-ConnectVersionInRepo -ProjectRoot $root -Version $Version
$got = (Get-Content (Join-Path $root 'scripts\client\windows\connect-version.txt') -Raw).Trim()
if ($got -ne $Version) { throw "version file mismatch got=$got" }
Write-Host "REPO_VERSION=$got"

# Build zip (forward-slash entries) and deploy SMART ONLY
$stage = Join-Path $env:TEMP 'claude-bundle-smart-22'
$zip = Join-Path $env:TEMP 'claude-client-bundle-smart-22.zip'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path (Join-Path $stage 'mac'), (Join-Path $stage 'server\cursor-rules'), (Join-Path $stage 'server\skills\laptop-exec'), (Join-Path $stage 'server\cursor-hooks')
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

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
if (Test-Path $zip) { Remove-Item $zip -Force }
$z = [IO.Compression.ZipFile]::Open($zip, 'Create')
try {
  Get-ChildItem $stage -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($stage.Length).TrimStart('\').Replace('\', '/')
    $e = $z.CreateEntry($rel)
    $o = $e.Open()
    try {
      $fs = [IO.File]::OpenRead($_.FullName)
      try { $fs.CopyTo($o) } finally { $fs.Dispose() }
    } finally { $o.Dispose() }
  }
} finally { $z.Dispose() }

$server = 'smart@192.168.210.240'
Write-Host "Deploy SMART ONLY -> $server v$Version"
& ssh -o BatchMode=yes -o ConnectTimeout=15 $server 'mkdir -p ~/claude-client-bundle-deploy'
& scp -o BatchMode=yes -o ConnectTimeout=60 -q $zip "${server}:~/claude-client-bundle-deploy/bundle.zip"
if ($LASTEXITCODE -ne 0) { throw 'scp failed' }

$remote = @'
set -e
sudo -n /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh "$HOME/claude-client-bundle-deploy/bundle.zip"
echo VER=$(tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt)
'@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remote))
& ssh -o BatchMode=yes -o ConnectTimeout=90 $server "echo $b64 | base64 -d | bash"
if ($LASTEXITCODE -ne 0) { throw "smart install failed $LASTEXITCODE" }

$remoteVer = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $server "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt").Trim()
Write-Host "SMART_REMOTE=$remoteVer"
if ($remoteVer -ne $Version) { throw "mismatch expected=$Version got=$remoteVer" }

# Confirm Sepidz unchanged
$sepidzVer = (& ssh -o BatchMode=yes -o ConnectTimeout=10 sepidz@192.168.250.70 "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt").Trim()
Write-Host "SEPIDZ_UNCHANGED=$sepidzVer"
Write-Host 'SMART_VERSION_22_OK'
