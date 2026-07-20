$ErrorActionPreference = 'Stop'
. .\publish\sepidz-deploy.local.ps1
$pw = $SepidzSudoPassword
$user = if ($SepidzSshUser) { $SepidzSshUser } else { 'sepidz' }
$hostName = if ($SepidzServerIp) { $SepidzServerIp } else { '192.168.250.70' }
# Prefer ssh config host alias
$sshTarget = 'claude-server-sepidz'
Write-Output "target=$sshTarget user=$user host=$hostName pw_set=$([bool]$pw)"

$localTg = Join-Path (Get-Location) 'tmp\lex-sepidz-bundle.tgz'
if (-not (Test-Path $localTg)) { throw "missing $localTg" }

# Upload
& scp -o BatchMode=yes -o ConnectTimeout=20 $localTg "${sshTarget}:/tmp/lex-sepidz-bundle.tgz"
if ($LASTEXITCODE -ne 0) { throw "scp failed $LASTEXITCODE" }

# Remote extract + sudo install (password via stdin to sudo -S; never echo)
$remote = @'
set -euo pipefail
rm -rf /tmp/lex-sepidz-bundle
tar -xzf /tmp/lex-sepidz-bundle.tgz -C /tmp
chmod +x /tmp/lex-sepidz-bundle/install-on-sepidz.sh
echo "EXTRACT_OK"
'@
& ssh -o BatchMode=yes -o ConnectTimeout=20 $sshTarget $remote
if ($LASTEXITCODE -ne 0) { throw "extract failed" }

# sudo install - pipe password
$installCmd = 'echo "$SUDO_PW" | sudo -S -p "" bash /tmp/lex-sepidz-bundle/install-on-sepidz.sh /tmp/lex-sepidz-bundle'
# Use env var on remote without putting pw in process list long-term via ssh
$psi = @"
export SUDO_PW=$(ConvertTo-Json $pw)
bash -lc 'echo "\$SUDO_PW" | sudo -S -p "" bash /tmp/lex-sepidz-bundle/install-on-sepidz.sh /tmp/lex-sepidz-bundle'
"@
# Safer: write password to remote temp with ssh heredoc then shred
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pw))
$remoteInstall = @"
set -euo pipefail
echo '$b64' | base64 -d | sudo -S -p '' bash /tmp/lex-sepidz-bundle/install-on-sepidz.sh /tmp/lex-sepidz-bundle
"@
$out = & ssh -o BatchMode=yes -o ConnectTimeout=60 $sshTarget $remoteInstall 2>&1
Write-Output $out
if ($LASTEXITCODE -ne 0) { throw "install failed: $out" }
Write-Output 'SEPIDZ_DEPLOY_DONE'
