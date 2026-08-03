# connect-env-repair.ps1 - fix broken DOS 8.3 USERPROFILE/TEMP (dot usernames)
# + VerDir contract healer (EXE + src only under Claude-Connect\{ver}\).
# Dot-source early from connect-update.ps1 / connect.ps1 / connect-preflight.ps1 / connect-boot.ps1.
# Or: powershell -File connect-env-repair.ps1 -EmitBatEnv  (KEY=VALUE lines for connect.bat)
# Symptom: "An object at the specified path C:\Users\XXXX~1.YYY does not exist."

param(
    [switch]$EmitBatEnv
)

function Repair-ConnectWindowsProfileTempEnv {
    [CmdletBinding()]
    param()

    $longProfile = $null
    try {
        $fp = [Environment]::GetFolderPath('UserProfile')
        if ($fp -and ($fp -notmatch '~') -and (Test-Path -LiteralPath $fp)) {
            $longProfile = $fp
        }
    } catch {}

    if (-not $longProfile) {
        $u = if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName }
        if ($u -and ($u -notmatch '~')) {
            foreach ($root in @('C:\Users', 'D:\Users')) {
                $guess = Join-Path $root $u
                if (Test-Path -LiteralPath $guess) {
                    $longProfile = $guess
                    break
                }
            }
        }
    }

    if ($longProfile -and ($longProfile -notmatch '~') -and (Test-Path -LiteralPath $longProfile)) {
        if (-not $env:USERPROFILE -or ($env:USERPROFILE -match '~') -or -not (Test-Path -LiteralPath $env:USERPROFILE)) {
            $env:USERPROFILE = $longProfile
        }
        $longLocal = Join-Path $longProfile 'AppData\Local'
        if ((Test-Path -LiteralPath $longLocal) -and (
                -not $env:LOCALAPPDATA -or ($env:LOCALAPPDATA -match '~') -or -not (Test-Path -LiteralPath $env:LOCALAPPDATA))) {
            $env:LOCALAPPDATA = $longLocal
        }
    }

    $tempCandidates = New-Object System.Collections.Generic.List[string]
    if ($env:LOCALAPPDATA -and ($env:LOCALAPPDATA -notmatch '~')) {
        [void]$tempCandidates.Add((Join-Path $env:LOCALAPPDATA 'Temp'))
    }
    if ($env:USERPROFILE -and ($env:USERPROFILE -notmatch '~')) {
        [void]$tempCandidates.Add((Join-Path $env:USERPROFILE 'AppData\Local\Temp'))
    }
    try {
        $p = [IO.Path]::GetTempPath()
        if ($p -and ($p -notmatch '~')) { [void]$tempCandidates.Add($p) }
    } catch {}
    if ($env:TEMP -and ($env:TEMP -notmatch '~')) { [void]$tempCandidates.Add($env:TEMP) }
    if ($env:TMP -and ($env:TMP -notmatch '~')) { [void]$tempCandidates.Add($env:TMP) }
    if ($env:SystemRoot) {
        [void]$tempCandidates.Add((Join-Path $env:SystemRoot 'Temp'))
    }

    foreach ($cand in $tempCandidates) {
        if (-not $cand) { continue }
        if ($cand -match '~') { continue }
        try {
            if (-not (Test-Path -LiteralPath $cand)) {
                New-Item -ItemType Directory -Force -Path $cand -ErrorAction Stop | Out-Null
            }
            $full = (Get-Item -LiteralPath $cand -ErrorAction Stop).FullName
            if ($full -and ($full -notmatch '~')) {
                $env:TEMP = $full
                $env:TMP = $full
                return
            }
        } catch { continue }
    }
}

function Get-ConnectPs1EmbeddedVersion {
    # Parse $script:ConnectVersion / $ConnectVersion from connect.ps1. Empty = unreadable.
    param([string]$ConnectPs1Path)
    if (-not $ConnectPs1Path -or -not (Test-Path -LiteralPath $ConnectPs1Path)) { return '' }
    try {
        # Head-only: version is near the top; avoid slurping 200KB+ on every boot probe.
        $head = Get-Content -LiteralPath $ConnectPs1Path -TotalCount 250 -ErrorAction Stop | Out-String
        if ($head -match "(?m)ConnectVersion\s*=\s*'([^']+)'") { return $Matches[1].Trim() }
    } catch {}
    return ''
}

function Test-ConnectFileIsStaleShadow {
    # windows/connect-ui.ps1 + connect-diagnostic.ps1 are intentional STALE-SHADOW stubs.
    # A VerDir that shipped those stubs is not "complete" (fleet break 2026-08-03).
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $head = (Get-Content -LiteralPath $Path -TotalCount 8 -ErrorAction Stop) -join "`n"
        return [bool]($head -match 'STALE-SHADOW')
    } catch { return $false }
}

function Test-ConnectVerSrcComplete {
    # Complete = required files present AND folder name == connect-version.txt == connect.ps1 ConnectVersion
    # AND no STALE-SHADOW canon replacements for ui/diagnostic when those files exist.
    # Folder-only / txt-only match is NOT enough (2026-08-03: Repair stamped txt=.7 while ps1 still .1 → false "healthy").
    param([string]$SrcDir, [string]$Ver)
    if (-not $SrcDir -or -not (Test-Path -LiteralPath $SrcDir)) { return $false }
    foreach ($n in @('connect.ps1', 'connect-boot.ps1', 'connect-update.ps1', 'connect.bat', 'connect-version.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $SrcDir $n))) { return $false }
    }
    foreach ($n in @('connect-diagnostic.ps1', 'connect-ui.ps1')) {
        $p = Join-Path $SrcDir $n
        if ((Test-Path -LiteralPath $p) -and (Test-ConnectFileIsStaleShadow -Path $p)) { return $false }
    }
    if ($Ver -match '^\d{8}\.\d+$') {
        try {
            $v = (Get-Content -LiteralPath (Join-Path $SrcDir 'connect-version.txt') -Raw -ErrorAction Stop).Trim()
            if ($v -and $v -ne $Ver) { return $false }
        } catch { return $false }
        $ps1Ver = Get-ConnectPs1EmbeddedVersion -ConnectPs1Path (Join-Path $SrcDir 'connect.ps1')
        if (-not $ps1Ver -or $ps1Ver -ne $Ver) { return $false }
    }
    return $true
}

function Repair-ConnectVerDirLayout {
    # Contract: Claude-Connect\{ver}\ contains ONLY:
    #   - src\  (all scripts)
    #   - Claude-Connect-{ver}.exe
    # Everything else (vbs/cmd/ps1/extra dirs) is removed or moved into src.
    param(
        [Parameter(Mandatory)][string]$VerDir,
        [switch]$Quiet
    )
    if (-not $VerDir -or -not (Test-Path -LiteralPath $VerDir)) { return $false }
    try { $VerDir = [IO.Path]::GetFullPath($VerDir) } catch { return $false }
    $ver = Split-Path -Leaf $VerDir
    if ($ver -notmatch '^\d{8}\.\d+$') { return $false }

    $srcDir = Join-Path $VerDir 'src'
    if (-not (Test-Path -LiteralPath $srcDir)) {
        try { New-Item -ItemType Directory -Force -Path $srcDir | Out-Null } catch { return $false }
    }

    $wantExe = Join-Path $VerDir ("Claude-Connect-{0}.exe" -f $ver)

    Get-ChildItem -LiteralPath $VerDir -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.Name
        if ($name -match ('^(?i)Claude-Connect-' + [regex]::Escape($ver) + '\.exe$')) {
            if ($_.FullName -ne $wantExe) {
                try { Move-Item -LiteralPath $_.FullName -Destination $wantExe -Force } catch {}
            }
            return
        }
        if ($name -match '^(?i)Claude-Connect\.exe$') {
            if (-not (Test-Path -LiteralPath $wantExe)) {
                try {
                    Move-Item -LiteralPath $_.FullName -Destination $wantExe -Force
                } catch {
                    try { Copy-Item -LiteralPath $_.FullName -Destination $wantExe -Force } catch {}
                }
            } else {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
            return
        }
        # Stale launchers / foreign scripts beside EXE — never keep in VerDir.
        if ($name -match '(?i)\.(vbs|cmd)$' -or ($name -match '^(?i)Claude-Connect-' -and $name -match '(?i)\.exe$')) {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            $script:ConnectVerDirRepairLast = 'removed_foreign_or_launcher'
            return
        }
        $dest = Join-Path $srcDir $name
        if (-not (Test-Path -LiteralPath $dest)) {
            try {
                Move-Item -LiteralPath $_.FullName -Destination $dest -Force
            } catch {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        } else {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
        $script:ConnectVerDirRepairLast = 'removed_foreign_or_launcher'
    }

    Get-ChildItem -LiteralPath $VerDir -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -eq 'src') { return }
        try {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            $script:ConnectVerDirRepairLast = 'removed_extra_dir'
        } catch {}
    }

    # Never stamp connect-version.txt to the folder name when connect.ps1 disagrees.
    # That lie made poisoned trees look "complete" and kept install-current on bad code.
    $ps1Ver = Get-ConnectPs1EmbeddedVersion -ConnectPs1Path (Join-Path $srcDir 'connect.ps1')
    if ($ps1Ver -match '^\d{8}\.\d+$' -and $ps1Ver -eq $ver) {
        try {
            Set-Content -LiteralPath (Join-Path $srcDir 'connect-version.txt') -Value $ver -Encoding ASCII -NoNewline
        } catch {}
    } elseif ($ps1Ver -match '^\d{8}\.\d+$' -and $ps1Ver -ne $ver) {
        $script:ConnectVerDirRepairLast = ('content_version_mismatch folder={0} ps1={1}' -f $ver, $ps1Ver)
        # Keep txt honest (embedded) so Test-ConnectVerSrcComplete fails vs folder name.
        try {
            Set-Content -LiteralPath (Join-Path $srcDir 'connect-version.txt') -Value $ps1Ver -Encoding ASCII -NoNewline
        } catch {}
        if (-not $Quiet) {
            Write-Host ("WARN: VerDir content mismatch folder={0} connect.ps1={1} (not install-current)" -f $ver, $ps1Ver)
        }
    }

    foreach ($cand in @(
            (Join-Path $srcDir 'Claude-Connect.exe'),
            (Join-Path $srcDir ("Claude-Connect-{0}.exe" -f $ver))
        )) {
        if (Test-Path -LiteralPath $cand) {
            if (-not (Test-Path -LiteralPath $wantExe)) {
                try { Move-Item -LiteralPath $cand -Destination $wantExe -Force } catch {
                    try { Copy-Item -LiteralPath $cand -Destination $wantExe -Force } catch {}
                }
            }
            Remove-Item -LiteralPath $cand -Force -ErrorAction SilentlyContinue
        }
    }
    # Foreign versioned SFX dropped into src (seen: Claude-Connect-20260803.1.exe inside .7\src).
    Get-ChildItem -LiteralPath $srcDir -Filter 'Claude-Connect*.exe' -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        $script:ConnectVerDirRepairLast = 'removed_src_exe_poison'
    }

    return $true
}

function Repair-ConnectAllVerDirLayouts {
    param(
        [Parameter(Mandatory)][string]$Root,
        [switch]$Quiet
    )
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return $null }
    try { $Root = [IO.Path]::GetFullPath($Root) } catch { return $null }
    if ((Split-Path -Leaf $Root) -ne 'Claude-Connect') { return $null }

    $best = $null
    $bestKey = [int64](-1)
    Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{8}\.\d+$' } |
        ForEach-Object {
            $ver = $_.Name
            $src = Join-Path $_.FullName 'src'
            $complete = Test-ConnectVerSrcComplete -SrcDir $src -Ver $ver
            if (-not $complete) {
                $hasPs1 = Test-Path -LiteralPath (Join-Path $src 'connect.ps1')
                if (-not $hasPs1) {
                    try {
                        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        $script:ConnectVerDirRepairLast = 'removed_incomplete_orphan'
                    } catch {}
                    return
                }
            }
            [void](Repair-ConnectVerDirLayout -VerDir $_.FullName -Quiet:$Quiet)
            if ($complete -or (Test-ConnectVerSrcComplete -SrcDir $src -Ver $ver)) {
                if ($ver -match '^(\d{8})\.(\d+)$') {
                    $key = [int64]$Matches[1] * 10000 + [int]$Matches[2]
                    if ($key -gt $bestKey) {
                        $bestKey = $key
                        $best = $ver
                    }
                }
            }
        }

    if ($best) {
        if (Get-Command Set-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
            try { Set-ConnectInstallCurrent -Root $Root -Ver $best } catch {}
        }
        if (Get-Command Write-ConnectRootInstantLauncher -ErrorAction SilentlyContinue) {
            try { Write-ConnectRootInstantLauncher -Root $Root -Ver $best } catch {}
        }
        if (Get-Command Repair-ConnectRootLayout -ErrorAction SilentlyContinue) {
            try { [void](Repair-ConnectRootLayout -Root $Root -Ver $best -Quiet:$Quiet) } catch {}
        }
    }
    return $best
}

function Get-ConnectInstallCurrentPath {
    # Test seam: never let regression tests poison the live laptop pointer
    # (hit live 2026-08-03: test wrote 20260803.88 into real install-current.txt).
    $override = ''
    try { $override = [string]$env:CLAUDE_CONNECT_TEST_INSTALL_CURRENT_PATH } catch { $override = '' }
    if ($override -and $override.Trim().Length -gt 0) {
        return $override.Trim()
    }
    return (Join-Path $env:USERPROFILE '.config\claude-connect\install-current.txt')
}

function Get-ConnectVersionSortKey {
    # Numeric order for YYYYMMDD.N (same formula as Repair-ConnectAllVerDirLayouts).
    param([string]$Ver)
    if ($Ver -match '^(\d{8})\.(\d+)$') {
        return ([int64]$Matches[1] * 10000L + [int64]$Matches[2])
    }
    return [int64](-1)
}

function Get-ConnectInstallCurrent {
    param([string]$Root = '')
    $ver = ''
    try {
        $p = Get-ConnectInstallCurrentPath
        if (Test-Path -LiteralPath $p) {
            $ver = (Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue).Trim()
        }
    } catch { $ver = '' }
    # Normalize full-path poison (agents/scripts wrote absolute VerDir path). VBS joins
    # root\cfgVer\src and fails unless cfgVer is VERSION ONLY.
    if ($ver -and $ver -notmatch '^\d{8}\.\d+$') {
        $leaf = [IO.Path]::GetFileName($ver.TrimEnd('\', '/'))
        if ($leaf -match '^\d{8}\.\d+$') { $ver = $leaf }
    }
    if ($ver -notmatch '^\d{8}\.\d+$' -and $Root) {
        try {
            $cf = Join-Path $Root 'current.txt'
            if (Test-Path -LiteralPath $cf) {
                $ver = (Get-Content -LiteralPath $cf -Raw -ErrorAction SilentlyContinue).Trim()
            }
        } catch { $ver = '' }
    }
    # Reject poison/stale pointers: missing connect.ps1 OR content/version mismatch in that VerDir.
    if ($ver -match '^\d{8}\.\d+$' -and $Root -and (Test-Path -LiteralPath $Root)) {
        $probeSrc = Join-Path $Root (Join-Path $ver 'src')
        $probe = Join-Path $probeSrc 'connect.ps1'
        if (-not (Test-Path -LiteralPath $probe)) {
            $ver = ''
        } elseif (-not (Test-ConnectVerSrcComplete -SrcDir $probeSrc -Ver $ver)) {
            $ver = ''
        }
    }
    # Prefer newest complete VerDir under Root when pointer is missing OR older than best
    # (old Connect boot used to re-stamp install-current to its own older folder).
    if ($Root -and (Test-Path -LiteralPath $Root)) {
        $bestKey = -1L
        $bestVer = ''
        Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{8}\.\d+$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'src\connect.ps1')) } |
            ForEach-Object {
                $cand = $_.Name
                $src = Join-Path $_.FullName 'src'
                $ok = $true
                if (Get-Command Test-ConnectVerSrcComplete -ErrorAction SilentlyContinue) {
                    $ok = [bool](Test-ConnectVerSrcComplete -SrcDir $src -Ver $cand)
                }
                if (-not $ok) { return }
                $key = Get-ConnectVersionSortKey -Ver $cand
                if ($key -gt $bestKey) { $bestKey = $key; $bestVer = $cand }
            }
        if ($bestVer) {
            if ($ver -notmatch '^\d{8}\.\d+$') {
                $ver = $bestVer
            } elseif ((Get-ConnectVersionSortKey -Ver $bestVer) -gt (Get-ConnectVersionSortKey -Ver $ver)) {
                $ver = $bestVer
            }
        }
    }
    if ($ver -match '^\d{8}\.\d+$') { return $ver }
    return ''
}

function Set-ConnectInstallCurrent {
    param(
        [string]$Root = '',
        [Parameter(Mandatory)][string]$Ver
    )
    if ($Ver -notmatch '^\d{8}\.\d+$') { return }
    # Never poison the machine-wide pointer from TEMP/sandbox Claude-Connect trees
    # (hard tests extract Write-ConnectInstantLauncher into %TEMP%\...\Claude-Connect\{ver}).
    $skipGlobal = $false
    if ($Root) {
        try {
            $rf = [IO.Path]::GetFullPath($Root)
            if ($env:TEMP) {
                $tr = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
                if ($rf.StartsWith($tr + '\', [StringComparison]::OrdinalIgnoreCase) -or
                    [string]::Equals($rf, $tr, [StringComparison]::OrdinalIgnoreCase)) {
                    $skipGlobal = $true
                }
            }
            if ($env:TMP -and -not $skipGlobal) {
                $tr2 = [IO.Path]::GetFullPath($env:TMP).TrimEnd('\')
                if ($rf.StartsWith($tr2 + '\', [StringComparison]::OrdinalIgnoreCase) -or
                    [string]::Equals($rf, $tr2, [StringComparison]::OrdinalIgnoreCase)) {
                    $skipGlobal = $true
                }
            }
        } catch {}
    }
    if (-not $skipGlobal) {
        # Never stamp a Ver that is not content-complete under Root (folder/txt/ps1 + no STALE-SHADOW).
        # Write-side poison was the .88 incident: pointer set to incomplete VerDir, read-side only healed.
        if ($Root -and (Test-Path -LiteralPath $Root)) {
            $wantSrc = Join-Path $Root (Join-Path $Ver 'src')
            if (-not (Test-ConnectVerSrcComplete -SrcDir $wantSrc -Ver $Ver)) { return }
        } else {
            # No Root = cannot prove VerDir health; refuse machine-wide pointer write.
            return
        }
        # Anti-downgrade: a live older Connect must not overwrite install-current after a newer
        # versioned update landed (seen 2026-08-03: .4 update then .2.4 boot re-stamped pointer).
        try {
            $cur = ''
            $pCur = Get-ConnectInstallCurrentPath
            if (Test-Path -LiteralPath $pCur) {
                $cur = (Get-Content -LiteralPath $pCur -Raw -ErrorAction SilentlyContinue).Trim()
            }
            if ($cur -match '^\d{8}\.\d+$' -and $Root -and (Test-Path -LiteralPath $Root)) {
                $curSrc = Join-Path $Root (Join-Path $cur 'src')
                $curProbe = Join-Path $curSrc 'connect.ps1'
                # Only anti-downgrade against a HEALTHY newer tree (poisoned .7 with .1 ps1 must not block).
                $curHealthy = (Test-Path -LiteralPath $curProbe) -and
                    (Test-ConnectVerSrcComplete -SrcDir $curSrc -Ver $cur)
                if ($curHealthy -and
                    ((Get-ConnectVersionSortKey -Ver $cur) -gt (Get-ConnectVersionSortKey -Ver $Ver))) {
                    return
                }
            }
        } catch {}
        try {
            $ptrPath = Get-ConnectInstallCurrentPath
            $dir = Split-Path -Parent $ptrPath
            if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            Set-Content -LiteralPath $ptrPath -Value $Ver -Encoding ASCII -NoNewline
        } catch {}
    }
    if ($Root) {
        Remove-Item -LiteralPath (Join-Path $Root 'current.txt') -Force -ErrorAction SilentlyContinue
    }
}

function Repair-ConnectRootLayout {
    # HARD: Desktop\Claude-Connect\ = ONLY version folders. Zero files at root.
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Ver = '',
        [switch]$Quiet
    )
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return $false }
    try { $Root = [IO.Path]::GetFullPath($Root) } catch { return $false }
    if ((Split-Path -Leaf $Root) -ne 'Claude-Connect') { return $false }

    if ($Ver -notmatch '^\d{8}\.\d+$') {
        $Ver = Get-ConnectInstallCurrent -Root $Root
    }
    $srcDir = $null
    if ($Ver -match '^\d{8}\.\d+$') {
        $srcDir = Join-Path $Root (Join-Path $Ver 'src')
        if (-not (Test-Path -LiteralPath $srcDir)) {
            try { New-Item -ItemType Directory -Force -Path $srcDir | Out-Null } catch {}
        }
    }

    function Remove-ConnectRootFileRetry([string]$Path) {
        if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $true }
        for ($i = 0; $i -lt 6; $i++) {
            try {
                Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
                return $true
            } catch {
                Start-Sleep -Milliseconds (80 * ($i + 1))
            }
        }
        try {
            $q = $Path + ('.BAD-ROOT-{0}' -f (Get-Date -Format 'yyyyMMddHHmmss'))
            Move-Item -LiteralPath $Path -Destination $q -Force -ErrorAction Stop
            Remove-Item -LiteralPath $q -Force -ErrorAction SilentlyContinue
            return (-not (Test-Path -LiteralPath $Path))
        } catch { return $false }
    }

    Get-ChildItem -LiteralPath $Root -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.Name
        if ($name -match '^(?i)Claude-Connect-(\d{8}\.\d+)\.exe$') {
            $exeVer = $Matches[1]
            $exeDest = Join-Path $Root (Join-Path $exeVer $name)
            $exeVerDir = Join-Path $Root $exeVer
            try {
                if (-not (Test-Path -LiteralPath $exeVerDir)) {
                    New-Item -ItemType Directory -Force -Path $exeVerDir | Out-Null
                }
                if (-not (Test-Path -LiteralPath $exeDest)) {
                    Move-Item -LiteralPath $_.FullName -Destination $exeDest -Force -ErrorAction Stop
                } else {
                    [void](Remove-ConnectRootFileRetry -Path $_.FullName)
                }
            } catch {
                [void](Remove-ConnectRootFileRetry -Path $_.FullName)
            }
            return
        }
        # Never keep bare Claude-Connect.exe / launchers / current.txt at versioned root.
        if ($name -match '^(?i)Claude-Connect\.(exe|vbs|cmd)$' -or $name -eq 'current.txt' -or $name -eq 'connect.bat') {
            [void](Remove-ConnectRootFileRetry -Path $_.FullName)
            return
        }
        if ($srcDir -and (Test-Path -LiteralPath $srcDir) -and ($name -match '(?i)\.(ps1|bat|vbs)$')) {
            $dest = Join-Path $srcDir $name
            if (-not (Test-Path -LiteralPath $dest)) {
                try {
                    Move-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction Stop
                    return
                } catch {}
            }
        }
        [void](Remove-ConnectRootFileRetry -Path $_.FullName)
    }

    Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '^\d{8}\.\d+$') { return }
        try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }

    if ($Ver -match '^\d{8}\.\d+$') {
        Set-ConnectInstallCurrent -Root $Root -Ver $Ver
        if (Get-Command Write-ConnectRootInstantLauncher -ErrorAction SilentlyContinue) {
            try { Write-ConnectRootInstantLauncher -Root $Root -Ver $Ver } catch {}
        }
    }
    # Final sweep: folders-only (catch races that re-drop EXE/current.txt).
    Get-ChildItem -LiteralPath $Root -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        [void](Remove-ConnectRootFileRetry -Path $_.FullName)
    }
    return $true
}

function Write-ConnectRootInstantLauncher {
    # Primary: Desktop\Claude-Connect.exe. Optional .vbs/.cmd beside folder — never inside root.
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Ver = ''
    )
    if (-not $Root) { return }
    try {
        try { $Root = [IO.Path]::GetFullPath($Root) } catch {}
        if ($Ver -notmatch '^\d{8}\.\d+$') {
            $Ver = Get-ConnectInstallCurrent -Root $Root
        }
        if ($Ver -notmatch '^\d{8}\.\d+$') { return }
        Set-ConnectInstallCurrent -Root $Root -Ver $Ver

        $desktop = Split-Path -Parent $Root
        if (-not $desktop) { $desktop = [Environment]::GetFolderPath('Desktop') }
        $vbsPath = Join-Path $desktop 'Claude-Connect.vbs'
        $cfgEsc = (Get-ConnectInstallCurrentPath) -replace '"', '""'
        $rootEsc = $Root -replace '"', '""'
        $vbs = @(
            "' Claude Connect launcher (folder root stays version-dirs only)"
            'Set sh = CreateObject("WScript.Shell")'
            'Set fso = CreateObject("Scripting.FileSystemObject")'
            ('root = "' + $rootEsc + '"')
            ('cfg = "' + $cfgEsc + '"')
            # Prefer VerDir we were written for. install-current only wins when that
            # tree exists under this root (sandbox/TEMP must not follow a foreign Desktop pointer).
            ('ver = "' + $Ver + '"')
            'If fso.FileExists(cfg) Then'
            '  Set tf = fso.OpenTextFile(cfg, 1)'
            '  cfgVer = Trim(tf.ReadLine)'
            '  tf.Close'
            '  If cfgVer <> "" Then'
            # install-current must be VERSION ONLY (20260803.6). A full path poison
            # made VBS look for root\C:\Users\...\20260803.6\src and fall back forever.
            '    If InStr(cfgVer, "\") > 0 Then cfgVer = Mid(cfgVer, InStrRev(cfgVer, "\") + 1)'
            '    If InStr(cfgVer, "/") > 0 Then cfgVer = Mid(cfgVer, InStrRev(cfgVer, "/") + 1)'
            '    If fso.FileExists(root & "\" & cfgVer & "\src\connect-boot.ps1") Then ver = cfgVer'
            '  End If'
            'End If'
            'boot = root & "\" & ver & "\src\connect-boot.ps1"'
            'If Not fso.FileExists(boot) Then'
            '  MsgBox "Missing connect-boot.ps1 for version " & ver & vbCrLf & boot, vbCritical, "Claude Connect"'
            '  WScript.Quit 1'
            'End If'
            'src = fso.GetParentFolderName(boot)'
            'sh.CurrentDirectory = src'
            'sh.Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File """ & boot & """", 1, False'
        ) -join "`r`n"
        # VBScript reads .vbs as system ANSI unless UTF-16 LE (BOM). Non-ASCII Desktop
        # paths (Persian/Arabic) break FileExists/Run when written as UTF-8.
        [IO.File]::WriteAllText($vbsPath, $vbs + "`r`n", [Text.Encoding]::Unicode)

        $cmdPath = Join-Path $desktop 'Claude-Connect.cmd'
        $cmd = "@echo off`r`nwscript.exe //B //Nologo `"%~dp0Claude-Connect.vbs`"`r`nexit /b 0`r`n"
        [IO.File]::WriteAllText($cmdPath, $cmd, [Text.UTF8Encoding]::new($false))

        # Primary launcher: Desktop\Claude-Connect.exe (copy of versioned SFX).
        # Root folder stays version-dirs only — never put EXE/scripts inside Claude-Connect\.
        $verExe = Join-Path $Root (Join-Path $Ver ("Claude-Connect-{0}.exe" -f $Ver))
        $deskExe = Join-Path $desktop 'Claude-Connect.exe'
        if (Test-Path -LiteralPath $verExe) {
            try { Copy-Item -LiteralPath $verExe -Destination $deskExe -Force -ErrorAction SilentlyContinue } catch {}
        }

        foreach ($stale in @('Claude-Connect.vbs', 'Claude-Connect.cmd', 'Claude-Connect.exe', 'connect.bat', 'current.txt')) {
            Remove-Item -LiteralPath (Join-Path $Root $stale) -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

Repair-ConnectWindowsProfileTempEnv

if ($EmitBatEnv) {
    if ($env:USERPROFILE -and ($env:USERPROFILE -notmatch '~')) {
        Write-Output ('USERPROFILE=' + $env:USERPROFILE)
    }
    if ($env:LOCALAPPDATA -and ($env:LOCALAPPDATA -notmatch '~')) {
        Write-Output ('LOCALAPPDATA=' + $env:LOCALAPPDATA)
    }
    if ($env:TEMP -and ($env:TEMP -notmatch '~')) {
        Write-Output ('TEMP=' + $env:TEMP)
        Write-Output ('TMP=' + $env:TEMP)
    }
}
