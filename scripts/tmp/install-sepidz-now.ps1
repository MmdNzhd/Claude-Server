Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) '..\publish\Get-DeployCredentials.ps1')
$pw = Get-SepidzSudoPassword
if (-not $pw) { throw 'No Sepidz password in sepidz-deploy.local.ps1' }
$Server = 'smart@192.168.250.70'
$remote = 'sudo -S bash ~/claude-client-bundle-deploy/install-client-bundle.sh ~/claude-client-bundle-deploy/bundle.zip'
Write-Host "Installing on Sepidz (stdin sudo)..."
($pw + "`n") | & ssh -o BatchMode=yes -o ConnectTimeout=30 $Server $remote
Write-Host "ssh exit=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$ver = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $Server "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt").Trim()
$ip = (& ssh -o BatchMode=yes -o ConnectTimeout=10 $Server "grep -o '192.168.[0-9.]*' /usr/local/share/claude-client/connect.ps1 | head -1").Trim()
& ssh -o BatchMode=yes -o ConnectTimeout=10 $Server "bash -n /usr/local/share/claude-client/mac/claude-mount.sh && echo mount=OK"
Write-Host "OK v$ver ip=$ip"
