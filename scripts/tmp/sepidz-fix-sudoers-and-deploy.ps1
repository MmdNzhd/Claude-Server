#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
. (Join-Path $root 'publish\Get-DeployCredentials.ps1')

$server = Get-SepidzServerTarget
$pw = Get-SepidzSudoPassword
if (-not $pw) { throw 'SepidzSudoPassword missing' }
$pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))

$zipPath = Join-Path $env:TEMP 'claude-client-bundle-sepidz.zip'
$installLocal = Join-Path $root 'scripts\server\commands\install-client-bundle.sh'
if (-not (Test-Path $zipPath)) { throw "missing zip $zipPath - rebuild first" }
if (-not (Test-Path $installLocal)) { throw "missing $installLocal" }

$ver = (Get-Content (Join-Path $root 'scripts\client\windows\connect-version.txt') -Raw).Trim()
Write-Host "1) upload bundle v$ver -> $server"

& ssh -o BatchMode=yes -o ConnectTimeout=15 $server "mkdir -p ~/claude-client-bundle-deploy /tmp/claude-deploy-in"
if ($LASTEXITCODE -ne 0) { throw 'ssh mkdir failed' }

& scp -o BatchMode=yes -o ConnectTimeout=60 -q $zipPath "${server}:~/claude-client-bundle-deploy/bundle.zip"
if ($LASTEXITCODE -ne 0) { throw 'scp zip failed' }
& scp -o BatchMode=yes -o ConnectTimeout=30 -q $installLocal "${server}:~/claude-client-bundle-deploy/install-client-bundle.sh"
if ($LASTEXITCODE -ne 0) { throw 'scp install failed' }

Write-Host '2) install sudoers NOPASSWD (sepidz) + install bundle'

$bash = @"
set -euo pipefail
PW=`$(printf '%s' '$pwB64' | base64 -d)
sudo_pw() { printf '%s\n' "`$PW" | sudo -S -p '' "`$@"; }

# Fix CRLF on installer
python3 - <<'PY'
from pathlib import Path
p = Path.home() / 'claude-client-bundle-deploy' / 'install-client-bundle.sh'
b = p.read_bytes()
if b.startswith(b'\xef\xbb\xbf'):
    b = b[3:]
p.write_bytes(b.replace(b'\r\n', b'\n').replace(b'\r', b'\n'))
p.chmod(0o755)
PY

# Install golden installer path used by deploy scripts
sudo_pw mkdir -p /usr/local/lib/claude-server/commands
sudo_pw cp -f "`$HOME/claude-client-bundle-deploy/install-client-bundle.sh" /usr/local/lib/claude-server/commands/install-client-bundle.sh
sudo_pw chmod 755 /usr/local/lib/claude-server/commands/install-client-bundle.sh

# Passwordless sudoers like Smart (user=sepidz, home=/home/sepidz)
SUDOERS=/tmp/claude-client-deploy.sudoers
cat > "`$SUDOERS" <<'S'
# Allow Sepidz deploy without interactive password (client auto-update bundle).
Defaults:sepidz !requiretty
Cmnd_Alias CLAUDE_CLIENT_BUNDLE = /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh *, /bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh *, /usr/bin/bash /home/sepidz/claude-client-bundle-deploy/install-client-bundle.sh *, /bin/bash /home/sepidz/claude-client-bundle-deploy/install-client-bundle.sh *
sepidz ALL=(root) NOPASSWD: CLAUDE_CLIENT_BUNDLE
S
sudo_pw cp -f "`$SUDOERS" /etc/sudoers.d/claude-client-deploy
sudo_pw chmod 440 /etc/sudoers.d/claude-client-deploy
sudo_pw visudo -cf /etc/sudoers.d/claude-client-deploy

echo '3) sudo -n install (should be fast)'
sudo -n /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh "`$HOME/claude-client-bundle-deploy/bundle.zip"
echo VER=`$(tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt)
"@

$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bash))
& ssh -o BatchMode=yes -o ConnectTimeout=120 $server "echo $b64 | base64 -d > /tmp/sepidz-deploy.sh && bash /tmp/sepidz-deploy.sh"
if ($LASTEXITCODE -ne 0) { throw "remote deploy failed exit=$LASTEXITCODE" }

$remoteVer = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $server "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt").Trim()
Write-Host "REMOTE_VERSION=$remoteVer"
if ($remoteVer -ne $ver) { throw "mismatch expected=$ver got=$remoteVer" }

# verify sudo -n works for next time
& ssh -o BatchMode=yes -o ConnectTimeout=10 $server "sudo -n true 2>/dev/null; sudo -n /usr/bin/bash -c 'echo NOPASSWD_OK' 2>&1 | head -1"
Write-Host 'SEPIDZ_DEPLOY_OK'
