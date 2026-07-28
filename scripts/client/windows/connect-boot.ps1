#Requires -Version 5.1
# connect-boot.ps1 - acquire one of Global\ClaudeConnect#0..#9 THEN run connect.ps1.
# Up to 10 Connect UIs per PC. Abandoned mutex frees a dead slot automatically.
#
# Also: silent flat/hybrid -> Claude-Connect\{ver}\src migrate BEFORE UI.
# Old clients apply updates inplace (no folders). After that update lands this
# boot script, the relaunch creates version folders without telling users to
# run a new EXE.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$_connectEnvRepair = Join-Path $here 'connect-env-repair.ps1'
if (Test-Path -LiteralPath $_connectEnvRepair) { . $_connectEnvRepair }
$_connectEnvRepair = $null
$maxUi = 10

function Write-ConnectRootRedirectStub {
    # Leave a tiny connect.bat at Claude-Connect\ root so old Desktop shortcuts
    # keep working after scripts moved into {ver}\src.
    param([string]$Root, [string]$Ver)
    if (-not $Root -or -not $Ver) { return }
    $stub = @"
@echo off
setlocal EnableDelayedExpansion
set "ROOT=%~dp0"
set "VER="
if exist "%ROOT%current.txt" (
  for /f "usebackq delims=" %%V in ("%ROOT%current.txt") do set "VER=%%V"
)
if not defined VER set "VER=$Ver"
set "SRC=%ROOT%!VER!\src"
if not exist "%SRC%\connect.bat" (
  echo.
  echo   [X] Claude Connect scripts missing under %SRC%
  echo.
  pause
  exit /b 1
)
if exist "%SRC%\connect-hide-relaunch.vbs" (
  wscript.exe //B //Nologo "%SRC%\connect-hide-relaunch.vbs" %*
) else (
  powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%SRC%\connect.bat' -WorkingDirectory '%SRC%' -WindowStyle Hidden"
)
exit /b 0
"@
    try {
        Set-Content -LiteralPath (Join-Path $Root 'connect.bat') -Value $stub -Encoding ASCII
    } catch { }
}

function Repair-ConnectVersionedLayoutAtBoot {
    # Returns the directory that should host connect.ps1 (versioned src when possible).
    param([string]$StartDir)
    if (-not $StartDir) { return $StartDir }
    try { $StartDir = [IO.Path]::GetFullPath($StartDir) } catch { return $StartDir }

    $leaf = Split-Path -Leaf $StartDir
    # Already ...\Claude-Connect\{ver}\src
    if ($leaf -eq 'src') {
        $verDir = Split-Path -Parent $StartDir
        $verName = Split-Path -Leaf $verDir
        $root = Split-Path -Parent $verDir
        if ($verName -match '^\d{8}\.\d+$' -and (Split-Path -Leaf $root) -eq 'Claude-Connect') {
            if (Test-Path -LiteralPath (Join-Path $StartDir 'connect.ps1')) { return $StartDir }
        }
    }

    # Flat or hybrid Claude-Connect root
    if ($leaf -ne 'Claude-Connect') { return $StartDir }
    if (-not (Test-Path -LiteralPath (Join-Path $StartDir 'connect.ps1')) -and
        -not (Test-Path -LiteralPath (Join-Path $StartDir 'current.txt'))) {
        return $StartDir
    }

    $root = $StartDir
    $ver = ''
    $vf = Join-Path $root 'connect-version.txt'
    if (Test-Path -LiteralPath $vf) {
        try { $ver = (Get-Content -LiteralPath $vf -Raw -ErrorAction SilentlyContinue).Trim() } catch { $ver = '' }
    }
    $cf = Join-Path $root 'current.txt'
    if (Test-Path -LiteralPath $cf) {
        try {
            $cv = (Get-Content -LiteralPath $cf -Raw -ErrorAction SilentlyContinue).Trim()
            if ($cv -match '^\d{8}\.\d+$') { $ver = $cv }
        } catch { }
    }
    if ($ver -notmatch '^\d{8}\.\d+$') { return $StartDir }

    $verDir = Join-Path $root $ver
    $srcDir = Join-Path $verDir 'src'
    $srcPs1 = Join-Path $srcDir 'connect.ps1'

    # Hybrid: src already complete — sweep leftover root scripts, redirect.
    if (Test-Path -LiteralPath $srcPs1) {
        try {
            $destExe = Join-Path $verDir ("Claude-Connect-{0}.exe" -f $ver)
            Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -eq 'current.txt') { return }
                if ($_.Name -eq 'connect.bat') {
                    # Root stub rewritten below; don't move the live stub into src yet.
                    return
                }
                if ($_.Name -match '^(?i)Claude-Connect(-[\d.]+)?\.exe$') {
                    if (-not (Test-Path -LiteralPath $destExe)) {
                        try { Move-Item -LiteralPath $_.FullName -Destination $destExe -Force } catch {
                            try { Copy-Item -LiteralPath $_.FullName -Destination $destExe -Force } catch { }
                        }
                    } else {
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    }
                    return
                }
                Move-Item -LiteralPath $_.FullName -Destination (Join-Path $srcDir $_.Name) -Force -ErrorAction SilentlyContinue
            }
            Set-Content -LiteralPath $cf -Value $ver -Encoding ASCII -NoNewline
            Write-ConnectRootRedirectStub -Root $root -Ver $ver
        } catch { }
        return $srcDir
    }

    # Pure flat: create {ver}\src and move client files there.
    if (-not (Test-Path -LiteralPath (Join-Path $root 'connect.ps1'))) { return $StartDir }
    try {
        New-Item -ItemType Directory -Force -Path $srcDir | Out-Null
        Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -eq 'current.txt') { return }
            Move-Item -LiteralPath $_.FullName -Destination (Join-Path $srcDir $_.Name) -Force -ErrorAction SilentlyContinue
        }
        $win = Join-Path $root 'windows'
        if (Test-Path -LiteralPath $win) {
            Get-ChildItem -LiteralPath $win -File -ErrorAction SilentlyContinue | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination (Join-Path $srcDir $_.Name) -Force -ErrorAction SilentlyContinue
            }
        }
        $destExe = Join-Path $verDir ("Claude-Connect-{0}.exe" -f $ver)
        foreach ($cand in @(
            (Join-Path $srcDir 'Claude-Connect.exe'),
            (Join-Path $srcDir ("Claude-Connect-{0}.exe" -f $ver))
        )) {
            if ((Test-Path -LiteralPath $cand) -and -not (Test-Path -LiteralPath $destExe)) {
                try { Move-Item -LiteralPath $cand -Destination $destExe -Force } catch {
                    try { Copy-Item -LiteralPath $cand -Destination $destExe -Force } catch { }
                }
            }
        }
        Set-Content -LiteralPath $cf -Value $ver -Encoding ASCII -NoNewline
        Write-ConnectRootRedirectStub -Root $root -Ver $ver
        if (-not (Test-Path -LiteralPath (Join-Path $srcDir 'connect.ps1'))) { return $StartDir }
        try {
            $logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
            New-Item -ItemType Directory -Force -Path $logDir | Out-Null
            $log = Join-Path $logDir ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
            $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
            $line = '[{0}] [INFO] [-] BOOT: flat_migrated_at_boot ver={1} src={2}' -f $ts, $ver, $srcDir
            [IO.File]::AppendAllText($log, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        } catch { }
        return $srcDir
    } catch {
        return $StartDir
    }
}

$here = Repair-ConnectVersionedLayoutAtBoot -StartDir $here

function Test-AcquireConnectUiSlot {
    param([int]$Max = 10)
    for ($i = 0; $i -lt $Max; $i++) {
        $name = "Global\ClaudeConnect#$i"
        $created = $false
        $cand = $null
        try {
            $cand = New-Object System.Threading.Mutex($false, $name, [ref]$created)
        } catch {
            continue
        }
        $got = $false
        try {
            try { $got = $cand.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
        } catch {
            try { $cand.Dispose() } catch { }
            continue
        }
        if ($got) {
            return @{ Mutex = $cand; Slot = $i; Name = $name }
        }
        try { $cand.Dispose() } catch { }
    }
    return $null
}

$acq = Test-AcquireConnectUiSlot -Max $maxUi
if (-not $acq) {
    Write-Host ''
    Write-Host '  [i] 10 Claude Connect windows already open - close one, then retry.' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}

$m = $acq.Mutex
$slot = [int]$acq.Slot
$global:ClaudeConnectBootMutex = $m
$env:CLAUDE_CONNECT_BOOT_MUTEX = '1'
$env:CLAUDE_CONNECT_UI_SLOT = [string]$slot

$connectPs1 = Join-Path $here 'connect.ps1'
if (-not (Test-Path -LiteralPath $connectPs1)) {
    try { $m.ReleaseMutex() } catch { }
    try { $m.Dispose() } catch { }
    Write-Host ''
    Write-Host '  [X] connect.ps1 missing next to connect-boot.ps1.' -ForegroundColor Red
    Write-Host ''
    exit 1
}

try {
    & $connectPs1 @args
    $ec = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
} catch {
    $ec = 1
    Write-Host ("  [X] connect.ps1 failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
} finally {
    if ($global:ClaudeConnectBootMutex) {
        try { $global:ClaudeConnectBootMutex.ReleaseMutex() } catch { }
        try { $global:ClaudeConnectBootMutex.Dispose() } catch { }
        $global:ClaudeConnectBootMutex = $null
    }
    $env:CLAUDE_CONNECT_BOOT_MUTEX = $null
}
exit $ec
