#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path (Get-Location) 'publish\Get-DeployCredentials.ps1')

$Server = Get-SepidzServerTarget
$DeployDir = 'claude-mount-deploy'
$repo = Get-Location

$mount = Join-Path $repo 'scripts\server\claude-mount.sh'
$auto  = Join-Path $repo 'scripts\server\claude-automount.sh'
$fix   = Join-Path $repo 'scripts\server\commands\deploy-mount-fix.sh'
foreach ($f in @($mount, $auto, $fix)) {
    if (-not (Test-Path $f)) { throw "Missing $f" }
}

Write-Host ''
Write-Host 'Deploy mount fix -> Sepidz' -ForegroundColor Cyan
Write-Host "  Server: $Server" -ForegroundColor DarkGray
Write-Host ''

ssh -o BatchMode=yes -o ConnectTimeout=15 $Server "mkdir -p ~/$DeployDir"
foreach ($pair in @(
    @{ Local = $mount; Name = 'claude-mount.sh' },
    @{ Local = $auto;  Name = 'claude-automount.sh' },
    @{ Local = $fix;   Name = 'deploy-mount-fix.sh' }
)) {
    scp -o BatchMode=yes -o ConnectTimeout=30 -q $pair.Local "${Server}:~/$DeployDir/$($pair.Name)"
    Write-Host "  uploaded $($pair.Name)" -ForegroundColor Green
}

$pw = Get-SepidzSudoPassword
if (-not $pw) { throw 'Sepidz sudo password missing (publish/sepidz-deploy.local.ps1)' }

$runnerLocal = Join-Path $env:TEMP 'sepidz-mount-fix-run.sh'
$pwEsc = $pw.Replace("'", "'\"'\"'")
@(
    '#!/bin/bash',
    'set -euo pipefail',
    "chmod +x ~/$DeployDir/deploy-mount-fix.sh",
    "echo '$pwEsc' | sudo -S bash ~/$DeployDir/deploy-mount-fix.sh"
) | Set-Content -Path $runnerLocal -Encoding ASCII

scp -o BatchMode=yes -o ConnectTimeout=30 -q $runnerLocal "${Server}:~/$DeployDir/run-mount-fix.sh"
ssh -o BatchMode=yes -o ConnectTimeout=120 $Server "chmod +x ~/$DeployDir/run-mount-fix.sh && bash ~/$DeployDir/run-mount-fix.sh"
$rc = $LASTEXITCODE
Remove-Item $runnerLocal -Force -ErrorAction SilentlyContinue

if ($rc -ne 0) { throw "deploy-mount-fix failed exit=$rc" }

Write-Host ''
Write-Host 'Verify syntax:' -ForegroundColor Cyan
ssh -o BatchMode=yes -o ConnectTimeout=12 $Server 'bash -n /usr/local/lib/claude-mount && echo lib-ok'
ssh -o BatchMode=yes -o ConnectTimeout=12 $Server 'sudo -n bash -n /home/farzadb/.local/bin/claude-mount 2>/dev/null || bash -n /home/farzadb/.local/bin/claude-mount 2>&1 || true'
Write-Host 'Done.' -ForegroundColor Green
