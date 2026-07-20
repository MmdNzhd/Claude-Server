Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\publish\Get-DeployCredentials.ps1')
$pw = Get-SepidzSudoPassword
$Server = Get-SepidzServerTarget
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $pw) { throw 'No Sepidz password' }
Write-Host "Target: $Server"

& ssh -o BatchMode=yes -o ConnectTimeout=10 $Server 'mkdir -p ~/claude-client-bundle-deploy'
if ($LASTEXITCODE -ne 0) { throw 'SSH mkdir failed' }

$zip = Join-Path $env:TEMP 'claude-sepidz-bundle.zip'
if (-not (Test-Path $zip)) {
    Write-Host 'Building bundle zip...'
    $OutBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
    $sepidClient = Join-Path (Get-ChildItem $OutBase -Directory -Filter 'claude-code-sepidz-*' | Sort-Object Name -Descending | Select-Object -First 1).FullName 'claude-code'
    & (Join-Path $ProjectRoot 'publish\deploy-client-bundles.ps1') -ProjectRoot $ProjectRoot -SmartClientRoot $sepidClient -SepidClientRoot $sepidClient -DeploySmart:$false -DeploySepidz:$false 2>$null
    # build inline if zip missing - use existing upload script logic
    $stage = Join-Path $env:TEMP 'claude-sepidz-stage2'
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage, (Join-Path $stage 'mac') | Out-Null
    $win = @('connect.bat','connect-version.txt','connect.ps1','connect-rider.bat','connect-update.ps1','connect-ui.ps1','connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1')
    $mac = @('connect.sh','connect-update.sh','connect-version.txt','git-mode.sh','connect-ui.sh','editor-launch.sh','claude-mount.sh')
    foreach ($n in $win) { Copy-Item (Join-Path $sepidClient "windows\$n") (Join-Path $stage $n) -Force }
    foreach ($n in $mac) { Copy-Item (Join-Path $sepidClient "mac\$n") (Join-Path $stage "mac\$n") -Force }
    New-Item -ItemType Directory -Force -Path (Join-Path $stage 'server') | Out-Null
    foreach ($rel in @('laptop-exec.sh','laptop-exec-setup.sh','claude-mount.sh','claude-git-setup.sh')) {
        Copy-Item (Join-Path $ProjectRoot "scripts\server\$rel") (Join-Path $stage "server\$rel") -Force
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $zip) { Remove-Item $zip -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
}

Write-Host 'Uploading bundle + install script...'
$installLocal = Join-Path $ProjectRoot 'scripts\server\commands\install-client-bundle.sh'
& scp -o BatchMode=yes -o ConnectTimeout=30 -q $zip "${Server}:~/claude-client-bundle-deploy/bundle.zip"
& scp -o BatchMode=yes -o ConnectTimeout=30 -q $installLocal "${Server}:~/claude-client-bundle-deploy/install-client-bundle.sh"

$bash = @"
set -e
echo '$pw' | sudo -S bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip
echo INSTALL_DONE
"@
Write-Host 'Installing...'
$out = $bash | & ssh -o BatchMode=yes -o ConnectTimeout=120 $Server 'bash -s' 2>&1
$out | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$ver = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $Server 'cat /usr/local/share/claude-client/connect-version.txt').Trim()
$ip = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $Server "grep -o '192.168.[0-9.]*' /usr/local/share/claude-client/connect.ps1 | head -1").Trim()
Write-Host "SUCCESS v$ver ip=$ip"
