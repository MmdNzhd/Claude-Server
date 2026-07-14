# sync-desktop.ps1 - publish + sync Desktop\Claude-Connect + optional server deploy + tests
# Run from repo:  scripts\client\sync-desktop.ps1
#                 scripts\client\sync-desktop.ps1 -DeployServer

param(
    [switch]$DeployServer,
    [switch]$SkipTests,
    [string]$Server = 'smart@192.168.210.240'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$PublishScript = Join-Path $RepoRoot 'publish\publish.ps1'
$TestsBat = Join-Path $PSScriptRoot 'tests\run-all.bat'
$Desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'

function Write-Step($m) { Write-Host "  $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "  OK  $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "  !   $m" -ForegroundColor Yellow }

Write-Host ''
Write-Host '=== Claude Connect - full desktop sync ===' -ForegroundColor White
Write-Host ''

Write-Step 'Publishing packages...'
& $PublishScript -SkipVersionBump
Write-Ok 'publish complete'

$pub = Get-ChildItem (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-*') -Directory |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $pub) { throw 'Publish folder not found under Desktop\claude-publish' }

Write-Step "Syncing Desktop\Claude-Connect from $($pub.Name) (client only)..."
$maps = @(
    @{ S = 'windows\connect.bat'; D = 'connect.bat' },
    @{ S = 'windows\connect-version.txt'; D = 'connect-version.txt' },
    @{ S = 'windows\connect-update.ps1'; D = 'connect-update.ps1' },
    @{ S = 'windows\connect.ps1'; D = 'connect.ps1' },
    @{ S = 'windows\connect-rider.bat'; D = 'connect-rider.bat' },
    @{ S = 'windows\editor-launch.ps1'; D = 'editor-launch.ps1' },
    @{ S = 'windows\git-mode.ps1'; D = 'git-mode.ps1' },
    @{ S = 'windows\cursor-auth-laptop.ps1'; D = 'cursor-auth-laptop.ps1' },
    @{ S = 'windows\connect-ui.ps1'; D = 'connect-ui.ps1' },
    @{ S = 'windows\connect-diagnostic.ps1'; D = 'connect-diagnostic.ps1' },
    @{ S = 'README.txt'; D = 'README.txt' }
)
foreach ($m in $maps) {
    $src = Join-Path $pub.FullName $m.S
    $dst = Join-Path $Desk $m.D
    Copy-Item $src $dst -Force
}
$macDir = Join-Path $Desk 'mac'
New-Item -ItemType Directory -Force -Path $macDir | Out-Null
Copy-Item (Join-Path $pub.FullName 'mac\connect.sh') (Join-Path $macDir 'connect.sh') -Force
Copy-Item (Join-Path $pub.FullName 'mac\connect-update.sh') (Join-Path $macDir 'connect-update.sh') -Force
Copy-Item (Join-Path $pub.FullName 'mac\connect-version.txt') (Join-Path $macDir 'connect-version.txt') -Force
Copy-Item (Join-Path $pub.FullName 'mac\git-mode.sh') (Join-Path $macDir 'git-mode.sh') -Force
Copy-Item (Join-Path $pub.FullName 'mac\connect-ui.sh') (Join-Path $macDir 'connect-ui.sh') -Force
Copy-Item (Join-Path $pub.FullName 'mac\editor-launch.sh') (Join-Path $macDir 'editor-launch.sh') -Force
Copy-Item (Join-Path $pub.FullName 'mac\claude-mount.sh') (Join-Path $macDir 'claude-mount.sh') -Force
Copy-Item (Join-Path $PSScriptRoot 'deploy-server-mount-fix.ps1') (Join-Path $Desk 'deploy-server-mount-fix.ps1') -Force
Copy-Item (Join-Path $PSScriptRoot 'deploy-server-mount-fix.bat') (Join-Path $Desk 'deploy-server-mount-fix.bat') -Force
foreach ($stale in @('server', 'claude-automount.sh', 'claude-watchdog.sh', 'claude-git-setup.sh', 'deploy-mount-fix.sh')) {
    $p = Join-Path $Desk $stale
    if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
}
Copy-Item (Join-Path $pub.FullName 'mac\claude-mount.sh') (Join-Path $Desk 'claude-mount.sh') -Force
$deskVer = (Get-Content (Join-Path $Desk 'connect-version.txt') -Raw).Trim()
Write-Ok "Desktop\Claude-Connect (client v$deskVer + mac; deploy tools from repo)"

if ($DeployServer) {
    Write-Step "Deploying mount fix to $Server..."
    $probe = ssh -o BatchMode=yes -o ConnectTimeout=8 $Server 'echo OK' 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Server unreachable (VPN on?). Skipping deploy."
        Write-Warn $probe
    } else {
        $deployPs1 = Join-Path $PSScriptRoot 'deploy-server-mount-fix.ps1'
        & $deployPs1 -Server $Server
        if ($LASTEXITCODE -eq 0) {
            Write-Ok 'all server users updated'
            Write-Step 'Deploying client auto-update bundle on server...'
            ssh -o BatchMode=yes -o ConnectTimeout=15 $Server 'sudo claude-server deploy-client-bundle' 2>&1 | ForEach-Object { Write-Host "    $_" }
            if ($LASTEXITCODE -eq 0) { Write-Ok 'client bundle deployed' } else { Write-Warn 'client bundle deploy failed - run: sudo claude-server deploy-client-bundle' }
        } else {
            Write-Warn 'deploy failed - run deploy-server-mount-fix.bat manually with sudo'
        }
    }
} else {
    Write-Warn 'Server deploy skipped. Use: sync-desktop.ps1 -DeployServer (VPN required)'
}

if (-not $SkipTests) {
    Write-Step 'Running regression tests...'
    & $TestsBat
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
    Write-Ok 'all tests passed'
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host "  Use: $Desk\connect.bat" -ForegroundColor Green
Write-Host "  Mac: bash $Desk\mac\connect.sh" -ForegroundColor Green
Write-Host ''
