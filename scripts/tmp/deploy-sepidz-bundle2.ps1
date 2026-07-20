#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. (Join-Path $root 'publish\Get-DeployCredentials.ps1')

$stage = Join-Path $env:TEMP 'claude-bundle-sepidz-stage'
$zipPath = Join-Path $env:TEMP 'claude-client-bundle-sepidz.zip'
# reuse zip if already built
if (-not (Test-Path $zipPath)) { throw "zip missing, rebuild needed: $zipPath" }
$ver = (Get-Content (Join-Path $root 'scripts\client\windows\connect-version.txt') -Raw).Trim()
Write-Host "Using existing zip v$ver size=$((Get-Item $zipPath).Length)"

$server = Get-SepidzServerTarget
$pw = Get-SepidzSudoPassword
$key = Join-Path $env:USERPROFILE '.ssh\claude_laptop'
$sshArgs = @('-o','BatchMode=yes','-o','ConnectTimeout=30')
if (Test-Path $key) { $sshArgs = @('-i',$key) + $sshArgs }

& ssh @sshArgs $server "mkdir -p ~/claude-client-bundle-deploy"
if ($LASTEXITCODE -ne 0) { throw 'ssh mkdir failed' }
& scp @sshArgs -q $zipPath "${server}:~/claude-client-bundle-deploy/bundle.zip"
if ($LASTEXITCODE -ne 0) { throw 'scp zip failed' }
$install = Join-Path $root 'scripts\server\commands\install-client-bundle.sh'
& scp @sshArgs -q $install "${server}:~/claude-client-bundle-deploy/install-client-bundle.sh"
if ($LASTEXITCODE -ne 0) { throw 'scp install failed' }

$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
$bash = @"
set -e
PW=`$(printf '%s' '$pwB64' | base64 -d)
python3 - <<'PY'
from pathlib import Path
p = Path.home() / 'claude-client-bundle-deploy' / 'install-client-bundle.sh'
b = p.read_bytes()
if b.startswith(b'\xef\xbb\xbf'):
    b = b[3:]
p.write_bytes(b.replace(b'\r\n', b'\n').replace(b'\r', b'\n'))
PY
chmod +x "`$HOME/claude-client-bundle-deploy/install-client-bundle.sh"
printf '%s\n' "`$PW" | sudo -S -p '' bash "`$HOME/claude-client-bundle-deploy/install-client-bundle.sh" "`$HOME/claude-client-bundle-deploy/bundle.zip"
echo VER=`$(tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt)
"@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
Write-Host "Installing on $server ..."
& ssh @sshArgs $server "echo $b64 | base64 -d > /tmp/inst-bundle.sh && bash /tmp/inst-bundle.sh"
if ($LASTEXITCODE -ne 0) { throw "install failed exit=$LASTEXITCODE" }
$remoteVer = (& ssh @sshArgs $server "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null").Trim()
Write-Host "REMOTE_VERSION=$remoteVer"
if ($remoteVer -ne $ver) { throw "deploy mismatch expected=$ver got=$remoteVer" }
Write-Host 'SEPIDZ_DEPLOY_OK'
