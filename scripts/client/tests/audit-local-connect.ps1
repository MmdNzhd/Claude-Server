#Requires -Version 5.1
# audit-local-connect.ps1 - scan laptop for connect.ps1 copies; report safe vs broken
param(
    [switch]$Json
)

. (Join-Path $PSScriptRoot '_paths.ps1')
$ErrorActionPreference = 'SilentlyContinue'
$ExpectedVersion = Get-ConnectVersion

function Test-ConnectBundle {
    param([string]$Dir)

    $ps1 = Join-Path $Dir 'connect.ps1'
    $bat = Join-Path $Dir 'connect.bat'
    $ed  = Join-Path $Dir 'editor-launch.ps1'
    if (-not (Test-Path $ed)) {
        $ed = Join-Path (Split-Path $Dir -Parent) 'editor-launch.ps1'
    }
    if (-not (Test-Path $ed)) {
        $ed = Join-Path (Split-Path (Split-Path $Dir -Parent) -Parent) 'editor-launch.ps1'
    }
    $git = Join-Path $Dir 'git-mode.ps1'
    if (-not (Test-Path $git)) {
        $git = Join-Path (Split-Path $Dir -Parent) 'git-mode.ps1'
    }
    if (-not (Test-Path $git)) {
        $git = Join-Path (Split-Path (Split-Path $Dir -Parent) -Parent) 'git-mode.ps1'
    }

    $ui  = Join-Path $Dir 'connect-ui.ps1'
    if (-not (Test-Path $ui)) {
        $ui = Join-Path (Split-Path $Dir -Parent) 'connect-ui.ps1'
    }
    if (-not (Test-Path $ui)) {
        $ui = Join-Path (Split-Path (Split-Path $Dir -Parent) -Parent) 'connect-ui.ps1'
    }

    if (-not (Test-Path $ps1)) { return $null }

    $src = Get-Content $ps1 -Raw
    $eds = if (Test-Path $ed) { Get-Content $ed -Raw } else { '' }
    $hasUi = Test-Path $ui -PathType Leaf

    $ver = if ($src -match "ConnectVersion = '([^']+)'") { $Matches[1] } else { 'NONE' }

    [PSCustomObject]@{
        Path            = (Resolve-Path $ps1).Path
        Version         = $ver
        VersionOk       = ($ver -eq $ExpectedVersion)
        HasGitMenu      = ($src -match 'g git')
        SafeCapture     = ($src -match '@\(Choose-Project -Mounts \$mounts\)\[-1\]')
        PathCombine     = ($eds -match '\[System\.IO\.Path\]::Combine\(\$CfgDir')
        HasGitModePs1   = (Test-Path $git -PathType Leaf)
        HasConnectUi    = $hasUi
        HasEditorLaunch = (Test-Path $ed -PathType Leaf)
        HasConnectBat   = (Test-Path $bat)
        HasServerFolder = (Test-Path (Join-Path $Dir 'server') -PathType Container) -or
                          (Test-Path (Join-Path (Split-Path $Dir -Parent) 'server') -PathType Container)
        HasDeployInZip  = @('deploy-mount-fix.sh', 'claude-mount.sh', 'claude-automount.sh', 'claude-watchdog.sh') |
            Where-Object { Test-Path (Join-Path $Dir $_) -or Test-Path (Join-Path (Split-Path $Dir -Parent) $_) } |
            ForEach-Object { $_ }
        JoinPathBugRisk = (
            ($ver -ne $ExpectedVersion) -or
            (-not ($src -match 'g git')) -or
            (-not ($src -match '@\(Choose-Project')) -or
            (-not ($eds -match 'Path\.Combine')) -or
            (-not $hasUi)
        )
        Verdict         = if (
            ($ver -eq $ExpectedVersion) -and ($src -match 'g git') -and
            ($src -match '@\(Choose-Project') -and ($eds -match 'Path\.Combine') -and
            (Test-Path $git -PathType Leaf) -and $hasUi
        ) { 'SAFE' } elseif ($ver -match '^20260703\.' -and $ver -lt $ExpectedVersion) { 'OUTDATED' } elseif (-not ($src -match 'ConnectVersion')) { 'OTHER' } else { 'BROKEN' }
    }
}

$roots = @(
    (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect')
    (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260703\windows')
    (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-client-20260630\windows')
    (Join-Path $env:USERPROFILE 'Desktop\claude-publish\claude-code-sepidz-20260703\claude-code\windows')
    (Get-ClientFile 'windows')
)

$found = @()
foreach ($root in $roots) {
    if (Test-Path $root) {
        $r = Test-ConnectBundle -Dir $root
        if ($r) { $found += $r }
    }
}

$desktop = Join-Path $env:USERPROFILE 'Desktop'
Get-ChildItem -Path $desktop -Filter 'connect.ps1' -Recurse -Depth 4 -ErrorAction SilentlyContinue |
    ForEach-Object {
    $dir = $_.DirectoryName
    if ($dir -match '\\designer\\') { return }
    if ($found.Path -notcontains $_.FullName) {
            $r = Test-ConnectBundle -Dir $dir
            if ($r) { $found += $r }
        }
    }

if ($Json) {
    $found | ConvertTo-Json -Depth 3
    exit 0
}

Write-Host ""
Write-Host "=== Local connect.ps1 audit (expected v$ExpectedVersion) ===" -ForegroundColor Cyan
Write-Host ""

foreach ($item in $found | Sort-Object Verdict, Path) {
    $color = switch ($item.Verdict) {
        'SAFE'      { 'Green' }
        'OUTDATED'  { 'Yellow' }
        default     { 'Red' }
    }
    Write-Host "[$($item.Verdict)] v$($item.Version)" -ForegroundColor $color
    Write-Host "  $($item.Path)"
    if ($item.JoinPathBugRisk) {
        Write-Host "  RISK: may show Join-Path ChildPath after project select" -ForegroundColor DarkYellow
    }
    if ($item.HasServerFolder) {
        Write-Host "  RISK: server/ folder in client package - re-publish or remove" -ForegroundColor DarkYellow
    }
    if ($item.HasDeployInZip -and $item.HasDeployInZip.Count -gt 0) {
        Write-Host "  RISK: server deploy files in client folder: $($item.HasDeployInZip -join ', ')" -ForegroundColor DarkYellow
    }
    Write-Host ""
}

$safe = @($found | Where-Object { $_.Verdict -eq 'SAFE' -and -not $_.HasServerFolder -and (-not $_.HasDeployInZip -or $_.HasDeployInZip.Count -eq 0) })
if ($safe.Count -gt 0) {
    Write-Host "Use:" -ForegroundColor Green
    foreach ($s in $safe) {
        $bat = Join-Path (Split-Path $s.Path -Parent) 'connect.bat'
        if (Test-Path $bat) { Write-Host "  $bat" }
    }
}

$broken = @($found | Where-Object {
    $_.Verdict -ne 'SAFE' -or $_.HasServerFolder -or ($_.HasDeployInZip -and $_.HasDeployInZip.Count -gt 0)
})
if ($broken.Count -gt 0) {
    Write-Host ""
    Write-Host "$($broken.Count) folder(s) NOT safe - do not use for connect." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "All scanned copies are SAFE." -ForegroundColor Green
exit 0
