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
    # Root must stay version-folders only. Launcher is Desktop\Claude-Connect.vbs (beside folder).
    param([string]$Root, [string]$Ver)
    if (-not $Root) { return }
    if ($Ver -match '^\d{8}\.\d+$' -and (Get-Command Set-ConnectInstallCurrent -ErrorAction SilentlyContinue)) {
        try { Set-ConnectInstallCurrent -Root $Root -Ver $Ver } catch {}
    }
    if (Get-Command Repair-ConnectRootLayout -ErrorAction SilentlyContinue) {
        try { [void](Repair-ConnectRootLayout -Root $Root -Ver $Ver -Quiet) } catch {}
    } elseif (Get-Command Write-ConnectRootInstantLauncher -ErrorAction SilentlyContinue) {
        try { Write-ConnectRootInstantLauncher -Root $Root -Ver $Ver } catch {}
    }
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
            if (Test-Path -LiteralPath (Join-Path $StartDir 'connect.ps1')) {
                # Prefer connect-version when that tree exists (stamped src beats stale current.txt).
                $stamp = ''
                try {
                    $stamp = (Get-Content -LiteralPath (Join-Path $StartDir 'connect-version.txt') -Raw -ErrorAction SilentlyContinue).Trim()
                } catch { $stamp = '' }
                if ($stamp -match '^\d{8}\.\d+$' -and $stamp -ne $verName) {
                    $alt = Join-Path $root (Join-Path $stamp 'src')
                    if ((Test-Path -LiteralPath (Join-Path $alt 'connect.ps1')) -and
                        ((Get-Item -LiteralPath (Join-Path $alt 'connect.ps1')).Length -gt 2000)) {
                        $verName = $stamp
                        $verDir = Join-Path $root $stamp
                        $StartDir = $alt
                    }
                }
                if (Get-Command Repair-ConnectVerDirLayout -ErrorAction SilentlyContinue) {
                    [void](Repair-ConnectVerDirLayout -VerDir $verDir -Quiet)
                }
                # Content poison: folder name .7 but connect.ps1 still .1 — leave this tree;
                # Repair-ConnectAllVerDirLayouts + install-current will prefer a healthy VerDir.
                $srcHealthy = $true
                if (Get-Command Test-ConnectVerSrcComplete -ErrorAction SilentlyContinue) {
                    $srcHealthy = [bool](Test-ConnectVerSrcComplete -SrcDir $StartDir -Ver $verName)
                }
                # Always prefer newest complete VerDir under root (never re-stamp install-current
                # to this boot's older folder when a newer tree exists).
                $best = $null
                if (Get-Command Repair-ConnectAllVerDirLayouts -ErrorAction SilentlyContinue) {
                    $best = Repair-ConnectAllVerDirLayouts -Root $root -Quiet
                }
                if (-not $best) {
                    if ($srcHealthy) { $best = $verName }
                }
                if ($best -match '^\d{8}\.\d+$') {
                    if (Get-Command Set-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
                        try { Set-ConnectInstallCurrent -Root $root -Ver $best } catch {}
                    }
                    if (Get-Command Write-ConnectRootInstantLauncher -ErrorAction SilentlyContinue) {
                        try { Write-ConnectRootInstantLauncher -Root $root -Ver $best } catch {}
                    }
                    try {
                        $stampDir = Join-Path $env:USERPROFILE '.config\claude-connect'
                        New-Item -ItemType Directory -Force -Path $stampDir | Out-Null
                        Set-Content -LiteralPath (Join-Path $stampDir 'last-launch-dir.txt') `
                            -Value (Join-Path $root $best) -Encoding ASCII -NoNewline
                    } catch {}
                    Write-ConnectRootRedirectStub -Root $root -Ver $best
                } else {
                    Write-ConnectRootRedirectStub -Root $root -Ver $verName
                }
                # If all-repair retargeted current to a newer complete tree, prefer that src.
                try {
                    $cv = ''
                    if (Get-Command Get-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
                        $cv = Get-ConnectInstallCurrent -Root $root
                    }
                    if ($cv -notmatch '^\d{8}\.\d+$') {
                        $cf0 = Join-Path $root 'current.txt'
                        if (Test-Path -LiteralPath $cf0) {
                            $cv = (Get-Content -LiteralPath $cf0 -Raw -ErrorAction SilentlyContinue).Trim()
                        }
                    }
                    if ($cv -match '^\d{8}\.\d+$') {
                        $curSrc = Join-Path $root (Join-Path $cv 'src')
                        if ((Test-Path -LiteralPath (Join-Path $curSrc 'connect.ps1')) -and
                            ((Get-Item -LiteralPath (Join-Path $curSrc 'connect.ps1')).Length -gt 2000)) {
                            return $curSrc
                        }
                    }
                } catch {}
                return $StartDir
            }
        }
    }

    # Flat or hybrid Claude-Connect root
    if ($leaf -ne 'Claude-Connect') { return $StartDir }
    $hasInstallPtr = $false
    if (Get-Command Get-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
        $hasInstallPtr = ((Get-ConnectInstallCurrent -Root $StartDir) -match '^\d{8}\.\d+$')
    }
    if (-not (Test-Path -LiteralPath (Join-Path $StartDir 'connect.ps1')) -and
        -not (Test-Path -LiteralPath (Join-Path $StartDir 'current.txt')) -and
        -not $hasInstallPtr) {
        # Still try if any version folder exists
        $anyVer = Get-ChildItem -LiteralPath $StartDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{8}\.\d+$' } |
            Select-Object -First 1
        if (-not $anyVer) { return $StartDir }
    }

    $root = $StartDir
    $ver = ''
    if (Get-Command Get-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
        $ver = Get-ConnectInstallCurrent -Root $root
    }
    # Prefer connect-version when that tree exists over a stale current.txt pointer.
    $vf = Join-Path $root 'connect-version.txt'
    if (Test-Path -LiteralPath $vf) {
        try { $ver = (Get-Content -LiteralPath $vf -Raw -ErrorAction SilentlyContinue).Trim() } catch { }
    }
    if ($ver -match '^\d{8}\.\d+$') {
        $stampSrc = Join-Path $root (Join-Path $ver 'src\connect.ps1')
        if (-not (Test-Path -LiteralPath $stampSrc)) {
            # stamped version file at root but tree missing — fall through
        } elseif ((Get-Item -LiteralPath $stampSrc).Length -gt 2000) {
            # keep $ver
        } else {
            $ver = ''
        }
    }
    $cf = Join-Path $root 'current.txt'
    if ($ver -notmatch '^\d{8}\.\d+$' -and (Test-Path -LiteralPath $cf)) {
        try {
            $cv = (Get-Content -LiteralPath $cf -Raw -ErrorAction SilentlyContinue).Trim()
            if ($cv -match '^\d{8}\.\d+$') { $ver = $cv }
        } catch { }
    }
    # If current.txt points at a missing/broken tree but a stamped complete tree exists, retarget.
    if ($ver -match '^\d{8}\.\d+$') {
        $probe = Join-Path $root (Join-Path $ver 'src\connect.ps1')
        if (-not (Test-Path -LiteralPath $probe) -or ((Get-Item -LiteralPath $probe -EA SilentlyContinue).Length -le 2000)) {
            if (Get-Command Repair-ConnectAllVerDirLayouts -ErrorAction SilentlyContinue) {
                $best = Repair-ConnectAllVerDirLayouts -Root $root -Quiet
                if ($best) { $ver = $best }
            }
        }
    }
    if ($ver -notmatch '^\d{8}\.\d+$') { return $StartDir }

    $verDir = Join-Path $root $ver
    $srcDir = Join-Path $verDir 'src'
    $srcPs1 = Join-Path $srcDir 'connect.ps1'

    # Hybrid: src already complete — sweep leftover root scripts, redirect.
    # Never overwrite versioned src with stale hybrid root leftovers.
    if (Test-Path -LiteralPath $srcPs1) {
        try {
            $destExe = Join-Path $verDir ("Claude-Connect-{0}.exe" -f $ver)
            Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -match '^(?i)Claude-Connect-(\d{8}\.\d+)\.exe$') {
                    if (-not (Test-Path -LiteralPath $destExe)) {
                        try { Move-Item -LiteralPath $_.FullName -Destination $destExe -Force } catch {
                            try { Copy-Item -LiteralPath $_.FullName -Destination $destExe -Force } catch { }
                        }
                    } else {
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    }
                    return
                }
                if ($_.Name -match '^(?i)Claude-Connect\.(vbs|cmd|exe)$' -or $_.Name -eq 'current.txt' -or $_.Name -eq 'connect.bat') {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    return
                }
                $dest = Join-Path $srcDir $_.Name
                if (Test-Path -LiteralPath $dest) {
                    $srcLen = 0
                    try { $srcLen = (Get-Item -LiteralPath $dest).Length } catch { $srcLen = 0 }
                    if ($srcLen -gt 2000) {
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                        return
                    }
                }
                Move-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction SilentlyContinue
            }
            if (Get-Command Repair-ConnectVerDirLayout -ErrorAction SilentlyContinue) {
                [void](Repair-ConnectVerDirLayout -VerDir $verDir -Quiet)
            }
            if (Get-Command Set-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
                Set-ConnectInstallCurrent -Root $root -Ver $ver
            }
            Write-ConnectRootRedirectStub -Root $root -Ver $ver
        } catch { }
        return $srcDir
    }

    # Pure flat: create {ver}\src and move client files there.
    if (-not (Test-Path -LiteralPath (Join-Path $root 'connect.ps1'))) { return $StartDir }
    try {
        New-Item -ItemType Directory -Force -Path $srcDir | Out-Null
        Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -eq 'current.txt') {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                return
            }
            if ($_.Name -match '^(?i)Claude-Connect\.(vbs|cmd|exe)$') {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                return
            }
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
        if (Get-Command Repair-ConnectVerDirLayout -ErrorAction SilentlyContinue) {
            [void](Repair-ConnectVerDirLayout -VerDir $verDir -Quiet)
        }
        Set-Content -LiteralPath $cf -Value $ver -Encoding ASCII -NoNewline
        Write-ConnectRootRedirectStub -Root $root -Ver $ver
        if (Get-Command Write-ConnectRootInstantLauncher -ErrorAction SilentlyContinue) {
            Write-ConnectRootInstantLauncher -Root $root -Ver $ver
        }
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
    try { $m.ReleaseMutex() } catch { }
    try { $m.Dispose() } catch { }
}
exit $ec
