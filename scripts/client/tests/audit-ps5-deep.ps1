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
    $codeBody = (($src -split "`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    Assert ($codeBody -notmatch '[\u2013\u2014]') "$rel no en/em dashes in executable lines"
    Assert ($codeBody -notmatch "-replace '\\',") "$rel no invalid -replace backslash regex"
    Assert ($src -notmatch 'Select-String[^\n]*-Pattern\s+\[regex\]::Escape') "$rel no bare Select-String [regex]::Escape"
    Assert ($src -notmatch 'Set-ConnectTitle\s+"[^"]*\|[^"]*\$\(') "$rel no pipe-in-Set-ConnectTitle double-quote"
}

# Repo git-mode must dot-source (em-dash in strings breaks PS 5.1 parse)
Write-Host ''
Write-Host '--- repo git-mode dot-source ---' -ForegroundColor Cyan
try {
    . (Get-ClientFile 'git-mode.ps1')
    Assert (Get-Command Sanitize-SshAliasConfig -ErrorAction SilentlyContinue) 'repo git-mode loads Sanitize-SshAliasConfig'
    Assert (Get-Command Acquire-TunnelPort -ErrorAction SilentlyContinue) 'repo git-mode loads Acquire-TunnelPort'
} catch {
    Assert $false "repo git-mode dot-source failed: $($_.Exception.Message)"
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
$ver = Get-ConnectVersion
$required = @('connect-ui.ps1', 'editor-launch.ps1', 'git-mode.ps1', 'cursor-auth-laptop.ps1', 'connect-version.txt', 'Path.Combine', '@(Choose-Project', 'Acquire-TunnelPort')
foreach ($r in $required) {
    Assert ($batSrc -match [regex]::Escape($r)) "connect.bat requires $r"
}
Assert ($batSrc -match 'ConnectVersion = ''!EXPECT_VER!''') 'connect.bat checks ConnectVersion from connect-version.txt'

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'All deep audit checks passed.' -ForegroundColor Green
    exit 0
}
Write-Host "$fail check(s) failed." -ForegroundColor Red
exit 1
