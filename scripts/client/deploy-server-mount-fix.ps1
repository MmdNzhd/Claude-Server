# deploy-server-mount-fix.ps1 - deploy mount + automount fix to ALL server users (sudo once)
# Run from repo only:  scripts\client\deploy-server-mount-fix.ps1
# NOT included in published client ZIPs - reads scripts\server\ from the repo checkout.

param(
    [string]$Server = 'smart@192.168.210.240'
)

$ErrorActionPreference = 'Stop'

function Find-DeployFiles {
    param([string]$StartDir)
    $candidates = @(
        $StartDir,
        (Split-Path $StartDir -Parent),
        (Split-Path (Split-Path $StartDir -Parent) -Parent)
    ) | Select-Object -Unique
    foreach ($base in $candidates) {
        $repoMount = Join-Path $base 'scripts\server\claude-mount.sh'
        $repoAuto  = Join-Path $base 'scripts\server\claude-automount.sh'
        $repoWatch = Join-Path $base 'scripts\server\claude-watchdog.sh'
        $repoFix   = Join-Path $base 'scripts\server\commands\deploy-mount-fix.sh'
        if ((Test-Path $repoMount) -and (Test-Path $repoAuto) -and (Test-Path $repoFix)) {
            return @{ Mount = $repoMount; Auto = $repoAuto; Watch = $repoWatch; Fix = $repoFix; Base = $base }
        }
    }
    return $null
}

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$files = Find-DeployFiles -StartDir $scriptDir
if (-not $files) {
    Write-Host '  [X] claude-mount.sh not found - run from repo scripts\client\' -ForegroundColor Red
    Write-Host '      (Published client ZIPs do not include server scripts)' -ForegroundColor DarkGray
    exit 1
}

$DeployDir = 'claude-mount-deploy'
Write-Host ''
Write-Host '  Deploy mount + automount fix (ALL server users)' -ForegroundColor Cyan
Write-Host "  Server: $Server" -ForegroundColor DarkGray
Write-Host "  From:   $($files.Base)" -ForegroundColor DarkGray
Write-Host ''

$serverRoot = Join-Path $files.Base 'scripts\server'
$uploads = @(
    @{ Local = $files.Mount; Name = 'claude-mount.sh' },
    @{ Local = $files.Auto;  Name = 'claude-automount.sh' },
    @{ Local = $files.Fix;   Name = 'deploy-mount-fix.sh' },
    @{ Local = (Join-Path $serverRoot 'claude-watchdog.sh'); Name = 'claude-watchdog.sh' },
    @{ Local = (Join-Path $serverRoot 'claude-self-heal.sh'); Name = 'claude-self-heal.sh' },
    @{ Local = (Join-Path $serverRoot 'claude-mount-reaper.sh'); Name = 'claude-mount-reaper.sh' },
    @{ Local = (Join-Path $serverRoot 'claude-tunnel-reacquire.sh'); Name = 'claude-tunnel-reacquire.sh' }
)

ssh -o BatchMode=yes -o ConnectTimeout=15 $Server "mkdir -p ~/$DeployDir"
foreach ($pair in $uploads) {
    if (-not (Test-Path -LiteralPath $pair.Local)) {
        throw "Missing deploy source: $($pair.Local)"
    }
    scp -o BatchMode=yes -o ConnectTimeout=30 -q $pair.Local "${Server}:~/$DeployDir/$($pair.Name)"
    Write-Host "    uploaded $($pair.Name)" -ForegroundColor Green
}

Write-Host ''
Write-Host '  Running deploy via sudo-from-laptop...' -ForegroundColor Cyan
Write-Host ''

ssh -o BatchMode=yes -o ConnectTimeout=120 $Server "chmod +x ~/$DeployDir/deploy-mount-fix.sh && sudo-from-laptop --smart -- bash ~/$DeployDir/deploy-mount-fix.sh"
$rc = $LASTEXITCODE
Write-Host ''
if ($rc -eq 0) { Write-Host '  All users updated.' -ForegroundColor Green }
else { Write-Host "  Failed (exit $rc). Run on server: sudo bash ~/$DeployDir/deploy-mount-fix.sh" -ForegroundColor Red }
Write-Host ''
exit $rc
