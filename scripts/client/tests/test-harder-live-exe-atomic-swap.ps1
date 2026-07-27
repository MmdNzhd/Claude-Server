#Requires -Version 5.1
# test-harder-live-exe-atomic-swap.ps1
# HARDER LIVE: Copy-ExeAtomicSwap extracted verbatim from connect-update.ps1 —
# identical-hash short-circuit, real content swap, FileShare.None rename-swap,
# spaced destination paths, and no .tmp debris. Seeds from Desktop Claude-Connect.exe.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}
function Note([string]$Msg) { Write-Host "  ----  $Msg" -ForegroundColor DarkGray }

function Get-TmpDebris {
    param([Parameter(Mandatory)][string]$Root)
    @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)\.tmp(?:\.|$)' })
}

function Resolve-SeedConnectExe {
    $live = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect\Claude-Connect.exe'
    if (Test-Path -LiteralPath $live) { return $live }
    $ver = (Get-Content (Get-ClientFile 'windows\connect-version.txt') -Raw).Trim()
    foreach ($c in @(
        (Join-Path $env:USERPROFILE ("Desktop\claude-publish\Claude-Connect-{0}.exe" -f $ver)),
        (Join-Path $env:USERPROFILE 'Desktop\claude-publish\Claude-Connect.exe')
    )) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function New-AltBuildFromSeed {
    param(
        [Parameter(Mandatory)][string]$Seed,
        [Parameter(Mandatory)][string]$OutPath
    )
    Copy-Item -LiteralPath $Seed -Destination $OutPath -Force
    $bytes = [System.IO.File]::ReadAllBytes($OutPath)
    [System.IO.File]::WriteAllBytes($OutPath, $bytes + [byte]0x00)
}

Write-Host ''
Write-Host '=== HARDER LIVE: Copy-ExeAtomicSwap ===' -ForegroundColor Cyan
Write-Host ''

$updPath = Get-ClientFile 'windows\connect-update.ps1'
$updSrc = Get-Content -LiteralPath $updPath -Raw

$extracted = @()
foreach ($n in @('Get-SafeFileSha256', 'Copy-ExeAtomicSwap')) {
    $fn = Get-FunctionSource -Content $updSrc -Name $n
    if (-not $fn) {
        Assert $false "could not extract $n from shipped connect-update.ps1"
        Write-Host ("RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor Red
        exit 1
    }
    $extracted += $n
    . ([scriptblock]::Create($fn))
}
function Write-UpdateFileLog { param([string]$Msg, [string]$Level = 'INFO') }
Assert ($extracted.Count -eq 2) 'extracted Get-SafeFileSha256 + Copy-ExeAtomicSwap from shipped connect-update.ps1'

$seedExe = Resolve-SeedConnectExe
Assert ($null -ne $seedExe -and (Test-Path -LiteralPath $seedExe)) 'seed EXE from Desktop Claude-Connect (or claude-publish fallback)'
if (-not $seedExe) {
    Write-Host ("RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor Red
    exit 1
}
Note ("seed=$seedExe")

$root = Join-Path $env:TEMP ("cc-harder-swap-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $root
$altExe = Join-Path $root 'new-build.exe'
New-AltBuildFromSeed -Seed $seedExe -OutPath $altExe

$altHash = Get-SafeFileSha256 -Path $altExe
Assert ($altHash -ne (Get-SafeFileSha256 -Path $seedExe)) 'alt build SHA256 differs from seed (genuine content change)'

$dest = Join-Path $root 'dest.exe'
Copy-Item -LiteralPath $seedExe -Destination $dest -Force

try {
    # --- identical hash short-circuit: true without rewrite ---
    $beforeUtc = (Get-Item -LiteralPath $dest).LastWriteTimeUtc
    Start-Sleep -Milliseconds 80
    $okSame = Copy-ExeAtomicSwap -Source $seedExe -Destination $dest
    $afterUtc = (Get-Item -LiteralPath $dest).LastWriteTimeUtc
    Assert $okSame 'identical hash: Copy-ExeAtomicSwap returns true'
    Assert ($beforeUtc -eq $afterUtc) 'identical hash: destination not rewritten (LastWriteTimeUtc unchanged)'
    $okSame2 = Copy-ExeAtomicSwap -Source $seedExe -Destination $dest
    Assert $okSame2 'identical hash: second call still returns true (idempotent short-circuit)'

    # --- different content: swap lands new hash ---
    Copy-Item -LiteralPath $seedExe -Destination $dest -Force
    $okDiff = Copy-ExeAtomicSwap -Source $altExe -Destination $dest
    Assert $okDiff 'different content: Copy-ExeAtomicSwap returns true'
    Assert ((Get-SafeFileSha256 -Path $dest) -eq $altHash) 'different content: destination SHA256 matches new source'

    # --- FileShare.None lock: rename-swap still succeeds; dest must end on source hash ---
    Copy-Item -LiteralPath $seedExe -Destination $dest -Force
    $lockFs = $null
    $plainDenied = $false
    $swapLockedOk = $false
    $lockedAfterHash = $null
    try {
        $lockFs = [System.IO.File]::Open(
            $dest,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::None)
        try { Copy-Item -LiteralPath $altExe -Destination $dest -Force -ErrorAction Stop }
        catch { $plainDenied = $true }
        Assert $plainDenied 'FileShare.None lock: plain Copy-Item denied while destination exclusive-locked'
        $swapLockedOk = Copy-ExeAtomicSwap -Source $altExe -Destination $dest
        $lockedAfterHash = Get-SafeFileSha256 -Path $dest
    } finally {
        if ($lockFs) { try { $lockFs.Dispose() } catch { } }
    }
    Assert $swapLockedOk 'FileShare.None lock: Copy-ExeAtomicSwap returns true (rename-swap path)'
    Assert ($lockedAfterHash -eq $altHash) 'FileShare.None lock: destination SHA256 matches source after true return (hard assert)'

    # --- spaced destination path ---
    $spaceDir = Join-Path $root 'folder with spaces'
    $spaceDest = Join-Path $spaceDir 'Claude Connect.exe'
    $null = New-Item -ItemType Directory -Force -Path $spaceDir
    Copy-Item -LiteralPath $seedExe -Destination $spaceDest -Force
    $okSpace = Copy-ExeAtomicSwap -Source $altExe -Destination $spaceDest
    Assert $okSpace 'spaced path: Copy-ExeAtomicSwap returns true'
    Assert ((Get-SafeFileSha256 -Path $spaceDest) -eq $altHash) 'spaced path: destination SHA256 matches source'

    Assert ((Get-TmpDebris -Root $root).Count -eq 0) 'sandbox: never leaves .tmp debris after all swap cases'

} finally {
    Start-Sleep -Milliseconds 200
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("HARDER LIVE atomic-swap RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor Green
    exit 0
}
Write-Host ("HARDER LIVE atomic-swap RESULT: {0} pass / {1} fail" -f $Pass, $Fail) -ForegroundColor Red
exit 1
