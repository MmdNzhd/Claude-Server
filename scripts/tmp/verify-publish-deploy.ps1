Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fail = 0

function Assert-True([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  OK  $Msg" -ForegroundColor Green }
    else { Write-Host "  FAIL $Msg" -ForegroundColor Red; $script:fail++ }
}

function Copy-EnsureDir([string]$Src, [string]$Dst) {
    $parent = Split-Path $Dst -Parent
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Copy-Item -LiteralPath $Src -Destination $Dst -Force
}

Write-Host ""
Write-Host "Verify publish -> Smart + Sepidz deploy" -ForegroundColor White
Write-Host ""

$required = @(
    'publish\publish.ps1',
    'publish\deploy-client-bundles.ps1',
    'scripts\server\commands\install-client-bundle.sh',
    'scripts\server\claude-server'
)
foreach ($rel in $required) {
    Assert-True (Test-Path (Join-Path $ProjectRoot $rel)) "file exists: $rel"
}

$pub = Get-Content (Join-Path $ProjectRoot 'publish\publish.ps1') -Raw
Assert-True ($pub -match '\[switch\]\$SkipServerDeploy') 'publish.ps1 has -SkipServerDeploy'
Assert-True ($pub -match 'deploy-client-bundles\.ps1') 'publish.ps1 calls deploy-client-bundles.ps1'

$dep = Get-Content (Join-Path $ProjectRoot 'publish\deploy-client-bundles.ps1') -Raw
Assert-True ($dep -match '192\.168\.210\.240') 'Smart server IP in deploy script'
Assert-True ($dep -match '192\.168\.250\.70') 'Sepidz server IP in deploy script'
Assert-True ($dep -match 'install-client-bundle\.sh') 'deploy uploads install-client-bundle.sh'
Assert-True ($dep -match 'Split-Path \$Dst -Parent') 'deploy creates nested dirs before copy'

foreach ($rel in @('publish\publish.ps1', 'publish\deploy-client-bundles.ps1')) {
    $path = Join-Path $ProjectRoot $rel
    $tokens = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
    Assert-True (($errs | Measure-Object).Count -eq 0) "PowerShell syntax: $rel"
}

$OutBase = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$latestSmart = Get-ChildItem $OutBase -Directory -Filter 'claude-code-client-*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
$latestSepid = Get-ChildItem $OutBase -Directory -Filter 'claude-code-sepidz-*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1

if ($latestSmart -and $latestSepid) {
    Write-Host ""
    Write-Host "Dry-run bundle build from $($latestSmart.Name) + $($latestSepid.Name)..." -ForegroundColor Cyan
    $WinBundleFiles = @('connect.bat','connect-version.txt','connect.ps1','connect-rider.bat','connect-update.ps1','connect-ui.ps1','connect-diagnostic.ps1','editor-launch.ps1','git-mode.ps1','cursor-auth-laptop.ps1')
    $MacBundleFiles = @('connect.sh','connect-update.sh','connect-version.txt','git-mode.sh','connect-ui.sh','editor-launch.sh','claude-mount.sh')
    $ServerBundleFiles = @('laptop-exec.sh','laptop-exec-setup.sh','claude-mount.sh','claude-git-setup.sh','cursor-rules/laptop-exec.mdc','skills/laptop-exec/SKILL.md','cursor-hooks/laptop-exec-guard.sh','cursor-hooks/hooks-user.json')

    function Build-Stage {
        param([string]$ClientRoot, [string]$StageDir)
        if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $StageDir, (Join-Path $StageDir 'mac') | Out-Null
        foreach ($n in $WinBundleFiles) { Copy-EnsureDir (Join-Path $ClientRoot "windows\$n") (Join-Path $StageDir $n) }
        foreach ($n in $MacBundleFiles) { Copy-EnsureDir (Join-Path $ClientRoot "mac\$n") (Join-Path $StageDir "mac\$n") }
        foreach ($rel in $ServerBundleFiles) {
            Copy-EnsureDir (Join-Path $ProjectRoot ("scripts\server\" + ($rel -replace '/','\'))) (Join-Path $StageDir ("server\" + ($rel -replace '/','\')))
        }
    }

    $stageSmart = Join-Path $env:TEMP 'claude-verify-smart-stage'
    $stageSepid = Join-Path $env:TEMP 'claude-verify-sepid-stage'
    Build-Stage -ClientRoot $latestSmart.FullName -StageDir $stageSmart
    Build-Stage -ClientRoot (Join-Path $latestSepid.FullName 'claude-code') -StageDir $stageSepid

    Assert-True (Test-Path (Join-Path $stageSmart 'connect.ps1')) 'Smart bundle stage built'
    Assert-True (Test-Path (Join-Path $stageSepid 'connect.ps1')) 'Sepidz bundle stage built'
    Assert-True (Test-Path (Join-Path $stageSmart 'server\cursor-rules\laptop-exec.mdc')) 'Smart bundle has server/cursor-rules'
    Assert-True (Test-Path (Join-Path $stageSepid 'server\skills\laptop-exec\SKILL.md')) 'Sepidz bundle has server/skills'

    $smartHits = (Select-String -Path (Join-Path $stageSmart 'connect.ps1') -Pattern '192\.168\.210\.240' -AllMatches).Matches.Count
    $sepidHits = (Select-String -Path (Join-Path $stageSepid 'connect.ps1') -Pattern '192\.168\.250\.70' -AllMatches).Matches.Count
    Assert-True ($smartHits -gt 0) "Smart bundle has Smart IP ($smartHits hits)"
    Assert-True ($sepidHits -gt 0) "Sepidz bundle has Sepidz IP ($sepidHits hits)"
    Assert-True (-not (Select-String -Path (Join-Path $stageSmart 'connect.ps1') -Pattern '192\.168\.250\.70' -Quiet)) 'Smart bundle has no Sepidz IP'
    Assert-True (-not (Select-String -Path (Join-Path $stageSepid 'connect.ps1') -Pattern '192\.168\.210\.240' -Quiet)) 'Sepidz bundle has no Smart IP'

    foreach ($label in @('smart','sepid')) {
        $stage = if ($label -eq 'smart') { $stageSmart } else { $stageSepid }
        $mount = Join-Path $stage 'mac\claude-mount.sh'
        & bash -n $mount 2>$null
        Assert-True ($LASTEXITCODE -eq 0) "bash -n $label/mac/claude-mount.sh"
    }
} else {
    Write-Host "  SKIP bundle dry-run (no publish folders on Desktop)" -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "SSH reachability..." -ForegroundColor Cyan
foreach ($target in @('smart@192.168.210.240', 'smart@192.168.250.70')) {
    & ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new $target "echo ok" 2>$null | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "SSH BatchMode: $target"
}

Write-Host ""
Write-Host "Current server bundles..." -ForegroundColor Cyan
foreach ($pair in @(@('Smart','smart@192.168.210.240','192.168.210.240'), @('Sepidz','smart@192.168.250.70','192.168.250.70'))) {
    $ver = & ssh -o BatchMode=yes -o ConnectTimeout=8 $pair[1] "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null" 2>$null
    if ($ver) {
        Write-Host "  $($pair[0]): v$ver" -ForegroundColor DarkGray
        $ip = & ssh -o BatchMode=yes -o ConnectTimeout=8 $pair[1] "grep -o '192.168.[0-9.]*' /usr/local/share/claude-client/connect.ps1 2>/dev/null | head -1" 2>$null
        Write-Host "  $($pair[0]) connect.ps1 IP: $ip" -ForegroundColor DarkGray
        Assert-True ($ip -eq $pair[2]) "$($pair[0]) server bundle has correct IP"
    } else {
        Write-Host "  WARN $($pair[0]): no bundle or unreadable" -ForegroundColor Yellow
        $script:fail++
    }
}

Write-Host ""
if ($fail -eq 0) {
    Write-Host "All checks passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$fail check(s) FAILED." -ForegroundColor Red
    exit 1
}
