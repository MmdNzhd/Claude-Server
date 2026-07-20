#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. (Join-Path $root 'publish\Get-DeployCredentials.ps1')

$stage = Join-Path $env:TEMP 'claude-bundle-sepidz-stage'
$zipPath = Join-Path $env:TEMP 'claude-client-bundle-sepidz.zip'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'mac') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'server') | Out-Null

$win = @{
  'connect.bat'='scripts\client\windows\connect.bat'
  'connect-version.txt'='scripts\client\windows\connect-version.txt'
  'connect.ps1'='scripts\client\windows\connect.ps1'
  'connect-rider.bat'='scripts\client\windows\connect-rider.bat'
  'connect-update.ps1'='scripts\client\windows\connect-update.ps1'
  'connect-diagnostic.ps1'='scripts\client\windows\connect-diagnostic.ps1'
  'connect-ui.ps1'='scripts\client\connect-ui.ps1'
  'editor-launch.ps1'='scripts\client\editor-launch.ps1'
  'git-mode.ps1'='scripts\client\git-mode.ps1'
  'cursor-auth-laptop.ps1'='scripts\client\cursor-auth-laptop.ps1'
}
foreach ($k in $win.Keys) {
  $src = Join-Path $root $win[$k]
  if (-not (Test-Path $src)) { throw "missing $src" }
  Copy-Item $src (Join-Path $stage $k) -Force
}
$mac = @{
  'connect.sh'='scripts\client\mac\connect.sh'
  'connect-update.sh'='scripts\client\mac\connect-update.sh'
  'connect-version.txt'='scripts\client\windows\connect-version.txt'
  'git-mode.sh'='scripts\client\git-mode.sh'
  'connect-ui.sh'='scripts\client\connect-ui.sh'
  'editor-launch.sh'='scripts\client\editor-launch.sh'
  'claude-mount.sh'='scripts\server\claude-mount.sh'
}
foreach ($k in $mac.Keys) {
  $src = Join-Path $root $mac[$k]
  if (-not (Test-Path $src)) { throw "missing $src" }
  Copy-Item $src (Join-Path $stage "mac\$k") -Force
}
$srv = @(
  'laptop-exec.sh','laptop-exec-setup.sh','claude-mount.sh','claude-git-setup.sh',
  'cursor-rules\laptop-exec.mdc','skills\laptop-exec\SKILL.md',
  'cursor-hooks\laptop-exec-guard.sh','cursor-hooks\hooks-user.json'
)
foreach ($rel in $srv) {
  $src = Join-Path $root ("scripts\server\" + $rel)
  if (-not (Test-Path $src)) { throw "missing $src" }
  $dst = Join-Path $stage ("server\" + $rel)
  $parent = Split-Path $dst -Parent
  if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  Copy-Item $src $dst -Force
}
Get-ChildItem $stage -Recurse -File | ForEach-Object {
  $_.FullName.Substring($stage.Length).TrimStart('\').Replace('\','/')
} | Sort-Object | Set-Content (Join-Path $stage 'manifest.txt') -Encoding UTF8

Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath)

$ver = (Get-Content (Join-Path $stage 'connect-version.txt') -Raw).Trim()
Write-Host "Built zip v$ver size=$((Get-Item $zipPath).Length)"

$server = Get-SepidzServerTarget
$pw = Get-SepidzSudoPassword
if (-not $pw) { throw 'SepidzSudoPassword missing' }

& ssh -o BatchMode=yes -o ConnectTimeout=20 $server "mkdir -p ~/claude-client-bundle-deploy"
if ($LASTEXITCODE -ne 0) { throw 'ssh mkdir failed' }
& scp -o BatchMode=yes -o ConnectTimeout=60 -q $zipPath "${server}:~/claude-client-bundle-deploy/bundle.zip"
if ($LASTEXITCODE -ne 0) { throw 'scp zip failed' }
$install = Join-Path $root 'scripts\server\commands\install-client-bundle.sh'
& scp -o BatchMode=yes -o ConnectTimeout=30 -q $install "${server}:~/claude-client-bundle-deploy/install-client-bundle.sh"
if ($LASTEXITCODE -ne 0) { throw 'scp install failed' }

$escaped = $pw.Replace("'", "'\''")
$remote = @"
set -e
python3 -c "from pathlib import Path; p=Path.home()/'claude-client-bundle-deploy'/'install-client-bundle.sh'; b=p.read_bytes(); b=b[3:] if b.startswith(b'\\xef\\xbb\\xbf') else b; p.write_bytes(b.replace(b'\\r\\n',b'\\n').replace(b'\\r',b'\\n'))"
chmod +x `$HOME/claude-client-bundle-deploy/install-client-bundle.sh
printf '%s\n' '$escaped' | sudo -S -p '' bash `$HOME/claude-client-bundle-deploy/install-client-bundle.sh `$HOME/claude-client-bundle-deploy/bundle.zip
tr -d '\\r\\n' < /usr/local/share/claude-client/connect-version.txt
"@
Write-Host "Installing on $server ..."
$out = & ssh -o BatchMode=yes -o ConnectTimeout=180 $server "bash -lc $(ConvertTo-Json $remote)" 2>&1
Write-Host ($out | Out-String)
$remoteVer = (& ssh -o BatchMode=yes -o ConnectTimeout=15 $server "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
Write-Host "REMOTE_VERSION=$remoteVer"
if ($remoteVer -ne $ver) { throw "deploy mismatch expected=$ver got=$remoteVer" }
Write-Host 'SEPIDZ_DEPLOY_OK'
