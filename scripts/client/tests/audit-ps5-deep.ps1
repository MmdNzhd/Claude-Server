# audit-ps5-deep.ps1 — deep PS 5.1 safety audit for client scripts
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

$prodFiles = @(
    'windows\connect.ps1',
    'connect-ui.ps1',
    'editor-launch.ps1',
    'git-mode.ps1',
    'cursor-auth-laptop.ps1',
    'users\designer\connect.ps1'
)

Write-Host ''
Write-Host '=== PS 5.1 deep audit (production scripts) ===' -ForegroundColor Cyan
Write-Host ''

foreach ($rel in $prodFiles) {
    $path = Get-ClientFile $rel
    if (-not (Test-Path $path)) { Assert $false "$rel exists"; continue }
    $src = Get-Content $path -Raw
    $parseErrs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$parseErrs)
    Assert ((-not $parseErrs) -or ($parseErrs.Count -eq 0)) "$rel parses cleanly"
    Assert ($src -notmatch '[\u201C\u201D\u2018\u2019]') "$rel no smart quotes"
    Assert ($src -notmatch 'Select-String[^\n]*-Pattern\s+\[regex\]::Escape') "$rel no bare Select-String [regex]::Escape"
    Assert ($src -notmatch 'Set-ConnectTitle\s+"[^"]*\|[^"]*\$\(') "$rel no pipe-in-Set-ConnectTitle double-quote"
}

# Dot-source chain smoke (no main script run)
Write-Host ''
Write-Host '--- dot-source smoke (functions load) ---' -ForegroundColor Cyan
$desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
if (Test-Path $desk) {
    try {
        . (Join-Path $desk 'editor-launch.ps1')
        . (Join-Path $desk 'git-mode.ps1')
        . (Join-Path $desk 'connect-ui.ps1')
        . (Join-Path $desk 'cursor-auth-laptop.ps1')
        Assert (Get-Command Launch-RemoteEditor -ErrorAction SilentlyContinue) 'Desktop editor-launch loads'
        Assert (Get-Command Get-GitMode -ErrorAction SilentlyContinue) 'Desktop git-mode loads'
        Assert (Get-Command Write-ConnectHeader -ErrorAction SilentlyContinue) 'Desktop connect-ui loads'
        Assert (Get-Command Sync-CursorGoldenAuth -ErrorAction SilentlyContinue) 'Desktop cursor-auth loads'
    } catch {
        Assert $false "Desktop dot-source failed: $($_.Exception.Message)"
    }
} else {
    Write-Host '  SKIP  Desktop Claude-Connect not found' -ForegroundColor DarkYellow
}

# Bundle guards
Write-Host ''
Write-Host '--- connect.bat bundle guards ---' -ForegroundColor Cyan
$bat = Get-ClientFile 'windows\connect.bat'
$batSrc = Get-Content $bat -Raw
$required = @('connect-ui.ps1', 'editor-launch.ps1', 'git-mode.ps1', 'cursor-auth-laptop.ps1', '20260703.12', 'Path.Combine', '@(Choose-Project')
foreach ($r in $required) {
    Assert ($batSrc -match [regex]::Escape($r)) "connect.bat requires $r"
}

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'All deep audit checks passed.' -ForegroundColor Green
    exit 0
}
Write-Host "$fail check(s) failed." -ForegroundColor Red
exit 1
