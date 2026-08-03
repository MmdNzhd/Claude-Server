#Requires -Version 5.1
# setup-launch.ps1 - IExpress AppLaunched entry point for Claude-Connect.exe.
#
# CRITICAL DESIGN (2026-07-25): this script MUST return within ~1s. The IExpress wextract.exe
# wrapper holds its own single-instance mutex for as long as this AppLaunched command runs.
# First install: DETACHED setup-worker.ps1 (optional network update + boot).
# Fast path (src already complete): direct connect-boot — no worker / no network.
# Day-to-day: double-click Desktop\Claude-Connect.exe (SFX). Optional .vbs/.cmd beside it.
#
# VERSIONED LAYOUT (2026-07-27):
#   {launchParent}\Claude-Connect\{ver}\Claude-Connect-{ver}.exe
#   {launchParent}\Claude-Connect\{ver}\src\   <- scripts (ScriptDir)
# Fast path (~0ms feel): if src already complete for this ver -> skip copy/move; spawn worker.

$ErrorActionPreference = 'Stop'

$_connectEnvRepair = Join-Path $PSScriptRoot 'connect-env-repair.ps1'
if (Test-Path -LiteralPath $_connectEnvRepair) {
    . $_connectEnvRepair
} else {
    try {
        $fp = [Environment]::GetFolderPath('UserProfile')
        if ($fp -and ($fp -notmatch '~') -and (Test-Path -LiteralPath $fp)) {
            if (-not $env:USERPROFILE -or ($env:USERPROFILE -match '~')) { $env:USERPROFILE = $fp }
            $ll = Join-Path $fp 'AppData\Local'
            if ((Test-Path -LiteralPath $ll) -and (-not $env:LOCALAPPDATA -or ($env:LOCALAPPDATA -match '~'))) {
                $env:LOCALAPPDATA = $ll
            }
        }
        $t = if ($env:LOCALAPPDATA -and ($env:LOCALAPPDATA -notmatch '~')) { Join-Path $env:LOCALAPPDATA 'Temp' } else { Join-Path $env:SystemRoot 'Temp' }
        if ($t -notmatch '~') {
            if (-not (Test-Path -LiteralPath $t)) { New-Item -ItemType Directory -Force -Path $t -EA SilentlyContinue | Out-Null }
            if (Test-Path -LiteralPath $t) { $env:TEMP = $t; $env:TMP = $t }
        }
    } catch {}
}
$_connectEnvRepair = $null

$Src = $PSScriptRoot
$Log = Join-Path $env:TEMP 'claude-connect-setup.log'
$FallbackRoot = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'

function Log([string]$m) {
    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    try { Add-Content -LiteralPath $Log -Value $line -Encoding UTF8 } catch { }
    try {
        $d = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        $f = Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = if ($env:CLAUDE_CONNECT_RUN_ID) { $env:CLAUDE_CONNECT_RUN_ID } else { 'setup' }
        $day = "[$ts] [INFO] [$sid] SETUP: $m" + [Environment]::NewLine
        # FileShare.ReadWrite: connect.ps1 holds the day log open; AppendAllText fails silently.
        $utf8 = [Text.UTF8Encoding]::new($false)
        $bytes = $utf8.GetBytes($day)
        $fs = $null
        try {
            $fs = [IO.FileStream]::new(
                $f,
                [IO.FileMode]::Append,
                [IO.FileAccess]::Write,
                [IO.FileShare]::ReadWrite)
            $null = $fs.Seek(0, [IO.SeekOrigin]::End)
            $fs.Write($bytes, 0, $bytes.Length)
            $fs.Flush()
        } finally {
            if ($fs) { try { $fs.Dispose() } catch { } }
        }
        if ($m -match '(?i)fail|error|skip|exit=') {
            $bread = Join-Path $env:USERPROFILE '.config\claude-connect\last-fail.txt'
            try {
                [IO.File]::AppendAllText($bread, $day, $utf8)
            } catch { }
        }
    } catch { }
}

function Test-IsBadInstallDir([string]$Dir, [string]$ExtractSrc) {
    if (-not $Dir) { return $true }
    try {
        $full = [IO.Path]::GetFullPath($Dir)
        $srcFull = [IO.Path]::GetFullPath($ExtractSrc)
    } catch { return $true }
    if ($full -eq $srcFull) { return $true }
    if ($full -match '(?i)(?:^|[\\/])(?:WindowsPowerShell|System32|SysWOW64)(?:[\\/]|$)') { return $true }
    if ($full -match '(?i)[\\/]Temp[\\/](IXP|IE[A-Z0-9]{3}|wextract)') { return $true }
    return $false
}

function Resolve-ConnectLaunchExe {
    param([string]$ExtractSrc)
    # Returns @{ LaunchParent; Exe; How }
    try {
        $cur = $PID
        for ($i = 0; $i -lt 14; $i++) {
            $p = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
            if (-not $p) { break }
            $ep = [string]$p.ExecutablePath
            if ($ep -and (Test-Path -LiteralPath $ep) -and ($ep -match '(?i)[\\/]Claude-Connect[^\\/]*\.exe$')) {
                $dir = Split-Path -Parent $ep
                if (-not (Test-IsBadInstallDir -Dir $dir -ExtractSrc $ExtractSrc)) {
                    return @{ LaunchParent = [IO.Path]::GetFullPath($dir); Exe = $ep; How = 'parent_chain' }
                }
            }
            $pp = 0
            try { $pp = [int]$p.ParentProcessId } catch { $pp = 0 }
            if ($pp -le 4) { break }
            $cur = $pp
        }
    } catch { }

    try {
        foreach ($proc in @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Claude-Connect%'" -ErrorAction SilentlyContinue)) {
            $ep = [string]$proc.ExecutablePath
            if (-not $ep -or -not (Test-Path -LiteralPath $ep)) { continue }
            if ($ep -notmatch '(?i)[\\/]Claude-Connect[^\\/]*\.exe$') { continue }
            $dir = Split-Path -Parent $ep
            if (-not (Test-IsBadInstallDir -Dir $dir -ExtractSrc $ExtractSrc)) {
                return @{ LaunchParent = [IO.Path]::GetFullPath($dir); Exe = $ep; How = 'process_scan' }
            }
        }
    } catch { }

    # IExpress AppLaunched chain (wextract->wscript->cmd->powershell) often hides the
    # original EXE from the parent chain — prefer known Desktop / publish EXEs.
    foreach ($cand in @(
            (Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'),
            (Join-Path $env:USERPROFILE 'Desktop\claude-publish\Claude-Connect.exe'),
            (Join-Path $FallbackRoot 'Claude-Connect.exe')
        )) {
        if ($cand -and (Test-Path -LiteralPath $cand)) {
            try {
                $dir = Split-Path -Parent $cand
                if (-not (Test-IsBadInstallDir -Dir $dir -ExtractSrc $ExtractSrc)) {
                    return @{ LaunchParent = [IO.Path]::GetFullPath($dir); Exe = [IO.Path]::GetFullPath($cand); How = 'known_path' }
                }
            } catch {}
        }
    }
    try {
        Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE 'Desktop\claude-publish') -Filter 'Claude-Connect-*.exe' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 |
            ForEach-Object {
                return @{ LaunchParent = $_.DirectoryName; Exe = $_.FullName; How = 'publish_newest' }
            }
    } catch {}

    return @{ LaunchParent = [IO.Path]::GetFullPath((Split-Path -Parent $FallbackRoot)); Exe = $null; How = 'fallback_desktop' }
}

function Get-PackagedConnectVersion {
    param([string]$ExtractSrc, [string]$LaunchExe)
    $vf = Join-Path $ExtractSrc 'connect-version.txt'
    if (Test-Path -LiteralPath $vf) {
        $v = (Get-Content -LiteralPath $vf -Raw -ErrorAction SilentlyContinue).Trim()
        if ($v -match '^\d{8}\.\d+$') { return $v }
    }
    if ($LaunchExe) {
        $leaf = Split-Path -Leaf $LaunchExe
        if ($leaf -match '^Claude-Connect-(\d{8}\.\d+)\.exe$') { return $Matches[1] }
    }
    return ''
}

function Resolve-VersionedTree {
    param([string]$LaunchParent, [string]$Version)
    # If EXE already lives in Claude-Connect\{ver}\, root is that Claude-Connect folder.
    $lp = $LaunchParent
    $leaf = Split-Path -Leaf $lp
    $parent = Split-Path -Parent $lp
    $grandLeaf = if ($parent) { Split-Path -Leaf $parent } else { '' }
    if ($leaf -match '^\d{8}\.\d+$' -and $grandLeaf -eq 'Claude-Connect') {
        $root = $parent
        $verDir = $lp
    } elseif ($leaf -eq 'Claude-Connect') {
        $root = $lp
        $verDir = Join-Path $root $Version
    } elseif ($leaf -eq 'src' -and ((Split-Path -Leaf (Split-Path -Parent $lp)) -match '^\d{8}\.\d+$')) {
        $verDir = Split-Path -Parent $lp
        $root = Split-Path -Parent $verDir
    } else {
        $root = Join-Path $lp 'Claude-Connect'
        $verDir = Join-Path $root $Version
    }
    $srcDir = Join-Path $verDir 'src'
    $destExe = Join-Path $verDir ("Claude-Connect-{0}.exe" -f $Version)
    return @{
        Root    = [IO.Path]::GetFullPath($root)
        VerDir  = [IO.Path]::GetFullPath($verDir)
        SrcDir  = [IO.Path]::GetFullPath($srcDir)
        DestExe = [IO.Path]::GetFullPath($destExe)
    }
}

function Test-VersionSrcStructural {
    # Structural src check (folder leaf may differ from package version stamp).
    param([string]$SrcDir)
    if (-not $SrcDir) { return $false }
    foreach ($n in @('connect.bat', 'connect.ps1', 'connect-boot.ps1', 'connect-update.ps1', 'editor-launch.ps1', 'connect-ui.ps1', 'connect-env-repair.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $SrcDir $n))) { return $false }
    }
    return $true
}

function Get-ConnectPs1EmbeddedVersionLocal {
    param([string]$ConnectPs1Path)
    if (Get-Command Get-ConnectPs1EmbeddedVersion -ErrorAction SilentlyContinue) {
        try { return [string](Get-ConnectPs1EmbeddedVersion -ConnectPs1Path $ConnectPs1Path) } catch { }
    }
    if (-not $ConnectPs1Path -or -not (Test-Path -LiteralPath $ConnectPs1Path)) { return '' }
    try {
        $head = Get-Content -LiteralPath $ConnectPs1Path -TotalCount 250 -ErrorAction Stop | Out-String
        if ($head -match "(?m)ConnectVersion\s*=\s*'([^']+)'") { return $Matches[1].Trim() }
    } catch {}
    return ''
}

function Get-ConnectVersionSortKeyLocal {
    param([string]$Ver)
    if (Get-Command Get-ConnectVersionSortKey -ErrorAction SilentlyContinue) {
        try { return [int64](Get-ConnectVersionSortKey -Ver $Ver) } catch { }
    }
    if ($Ver -match '^(\d{8})\.(\d+)$') {
        return ([int64]$Matches[1] * 10000L + [int64]$Matches[2])
    }
    return [int64](-1)
}

function Set-SrcVersionStamp {
    param([string]$SrcDir, [string]$Version)
    if (-not $SrcDir -or $Version -notmatch '^\d{8}\.\d+$') { return }
    $ps1Ver = Get-ConnectPs1EmbeddedVersionLocal -ConnectPs1Path (Join-Path $SrcDir 'connect.ps1')
    if ($ps1Ver -match '^\d{8}\.\d+$' -and $ps1Ver -ne $Version) {
        # Never lie: keep txt honest to connect.ps1 so EXE fast_path cannot revive poison.
        try {
            Set-Content -LiteralPath (Join-Path $SrcDir 'connect-version.txt') -Value $ps1Ver -Encoding ASCII -NoNewline
        } catch {}
        return
    }
    try {
        Set-Content -LiteralPath (Join-Path $SrcDir 'connect-version.txt') -Value $Version -Encoding ASCII -NoNewline
    } catch {}
}

function Test-VersionSrcComplete {
    # Hot path: structural + folder/txt/ps1 MUST agree (2026-08-03 EXE poison).
    # txt-only match previously let fast_path boot VerDirs where stamp lied vs connect.ps1.
    # Also reject STALE-SHADOW ui/diagnostic (same class as Test-ConnectVerSrcComplete).
    param([string]$SrcDir, [string]$Version)
    if (-not $SrcDir -or -not $Version) { return $false }
    if (-not (Test-VersionSrcStructural -SrcDir $SrcDir)) { return $false }
    $vf = Join-Path $SrcDir 'connect-version.txt'
    if (-not (Test-Path -LiteralPath $vf)) { return $false }
    try {
        $v = (Get-Content -LiteralPath $vf -Raw -ErrorAction Stop).Trim()
        if ($v -ne $Version) { return $false }
    } catch { return $false }
    $ps1Ver = Get-ConnectPs1EmbeddedVersionLocal -ConnectPs1Path (Join-Path $SrcDir 'connect.ps1')
    if (-not $ps1Ver -or $ps1Ver -ne $Version) { return $false }
    foreach ($n in @('connect-diagnostic.ps1', 'connect-ui.ps1')) {
        $p = Join-Path $SrcDir $n
        if (-not (Test-Path -LiteralPath $p)) { continue }
        try {
            $head = (Get-Content -LiteralPath $p -TotalCount 8 -ErrorAction Stop) -join "`n"
            if ($head -match 'STALE-SHADOW') { return $false }
        } catch { return $false }
    }
    return $true
}

function Repair-SetupVerDirContract {
    # After install: VerDir = src + Claude-Connect-{ver}.exe only.
    param([string]$Root, [string]$VerDir, [string]$SrcDir, [string]$Version)
    if (-not $VerDir -or -not $Version) { return }
    $leaf = Split-Path -Leaf $VerDir
    # verdir_leaf_wins: DestExe / stamp always follow folder leaf when it is a version.
    if ($leaf -match '^\d{8}\.\d+$' -and $leaf -ne $Version) {
        $Version = $leaf
    }
    Set-SrcVersionStamp -SrcDir $SrcDir -Version $Version
    $wantExe = Join-Path $VerDir ("Claude-Connect-{0}.exe" -f $Version)
    Get-ChildItem -LiteralPath $VerDir -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match ('^(?i)Claude-Connect-' + [regex]::Escape($Version) + '\.exe$')) { return }
        if ($_.Name -match '^(?i)Claude-Connect\.exe$') {
            if (-not (Test-Path -LiteralPath $wantExe)) {
                try { Move-Item -LiteralPath $_.FullName -Destination $wantExe -Force } catch {
                    try { Copy-Item -LiteralPath $_.FullName -Destination $wantExe -Force } catch {}
                }
            }
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            return
        }
        if ($_.Name -match '(?i)\.(vbs|cmd)$') {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            return
        }
        $dest = Join-Path $SrcDir $_.Name
        if (-not (Test-Path -LiteralPath $dest)) {
            try { Move-Item -LiteralPath $_.FullName -Destination $dest -Force } catch {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        } else {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    Get-ChildItem -LiteralPath $VerDir -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -eq 'src') { return }
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($Root -and $Version -match '^\d{8}\.\d+$') {
        if (Get-Command Set-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
            try { Set-ConnectInstallCurrent -Root $Root -Ver $Version } catch {}
        }
        Remove-Item -LiteralPath (Join-Path $Root 'current.txt') -Force -ErrorAction SilentlyContinue
    }
}

function Test-ConnectUiOpen {
    # True only when zero free Global\ClaudeConnect#0..#9 slots (same pool as connect-boot).
    # Do NOT scan Win32_Process CommandLine - that false-blocks when any connect UI is open.
    $free = 0
    for ($i = 0; $i -lt 10; $i++) {
        $name = "Global\ClaudeConnect#$i"
        $created = $false
        $m = $null
        try {
            $m = New-Object System.Threading.Mutex($false, $name, [ref]$created)
            $got = $false
            try { $got = $m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
            if ($got) {
                $free++
                try { $m.ReleaseMutex() } catch { }
            }
            try { $m.Dispose() } catch { }
        } catch {
            try { if ($m) { $m.Dispose() } } catch { }
        }
    }
    return ($free -eq 0)
}

function Copy-PayloadToSrc {
    param([string]$ExtractSrc, [string]$SrcDir)
    New-Item -ItemType Directory -Force -Path $SrcDir | Out-Null
    $skip = @(
        'setup-claude-connect.cmd', 'setup-run-hidden.vbs', 'setup-launch.ps1',
        'setup-worker.ps1', 'READ-ME-USERS.txt'
    )
    Get-ChildItem -LiteralPath $ExtractSrc -File | Where-Object { $skip -notcontains $_.Name } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $SrcDir $_.Name) -Force
    }
}

function Write-ConnectInstantLauncher {
    # Claude-Connect\ root = version folders ONLY.
    # Desktop\Claude-Connect.exe is the primary launcher (rebuilt SFX). Optional .vbs/.cmd beside it.
    param([string]$VerDir, [string]$SrcDir, [string]$Root = '')
    if (-not $VerDir -or -not $SrcDir) { return }
    try {
        if (-not $Root) { $Root = Split-Path -Parent $VerDir }
        $ver = Split-Path -Leaf $VerDir
        if ($ver -notmatch '^\d{8}\.\d+$') { return }
        if (Get-Command Repair-SetupVerDirContract -ErrorAction SilentlyContinue) {
            Repair-SetupVerDirContract -Root $Root -VerDir $VerDir -SrcDir $SrcDir -Version $ver
        }
        if (Get-Command Set-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
            Set-ConnectInstallCurrent -Root $Root -Ver $ver
        } else {
            # Same TEMP/sandbox guard as Set-ConnectInstallCurrent (do not poison live pointer).
            $skipGlobal = $false
            try {
                $rf = [IO.Path]::GetFullPath($Root)
                foreach ($tEnv in @($env:TEMP, $env:TMP)) {
                    if (-not $tEnv) { continue }
                    $tr = [IO.Path]::GetFullPath($tEnv).TrimEnd('\')
                    if ($rf.StartsWith($tr + '\', [StringComparison]::OrdinalIgnoreCase) -or
                        [string]::Equals($rf, $tr, [StringComparison]::OrdinalIgnoreCase)) {
                        $skipGlobal = $true
                        break
                    }
                }
            } catch {}
            if (-not $skipGlobal) {
                try {
                    $cfgDir = Join-Path $env:USERPROFILE '.config\claude-connect'
                    New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
                    Set-Content -LiteralPath (Join-Path $cfgDir 'install-current.txt') -Value $ver -Encoding ASCII -NoNewline
                } catch {}
            }
        }
        if (Get-Command Write-ConnectRootInstantLauncher -ErrorAction SilentlyContinue) {
            Write-ConnectRootInstantLauncher -Root $Root -Ver $ver
        } else {
            # Inline fallback (tests / thin extract without env-repair): Desktop sibling launchers.
            $desk = Split-Path -Parent $Root
            if (-not $desk) { $desk = [Environment]::GetFolderPath('Desktop') }
            $cfgEsc = (Join-Path $env:USERPROFILE '.config\claude-connect\install-current.txt') -replace '"', '""'
            $rootEsc = $Root -replace '"', '""'
            $vbsPath = Join-Path $desk 'Claude-Connect.vbs'
            $vbs = @(
                "' Claude Connect - Desktop sibling (folder root = version dirs only)"
                'Set sh = CreateObject("WScript.Shell")'
                'Set fso = CreateObject("Scripting.FileSystemObject")'
                ('root = "' + $rootEsc + '"')
                ('cfg = "' + $cfgEsc + '"')
                # Prefer VerDir we were written for. install-current only wins when that
                # tree exists under this root (sandbox/TEMP must not follow a foreign Desktop pointer).
                ('ver = "' + $ver + '"')
                'If fso.FileExists(cfg) Then'
                '  Set tf = fso.OpenTextFile(cfg, 1)'
                '  cfgVer = Trim(tf.ReadLine)'
                '  tf.Close'
                '  If cfgVer <> "" Then'
                '    If fso.FileExists(root & "\" & cfgVer & "\src\connect-boot.ps1") Then ver = cfgVer'
                '  End If'
                'End If'
                'boot = root & "\" & ver & "\src\connect-boot.ps1"'
                'If Not fso.FileExists(boot) Then'
                '  MsgBox "Missing connect-boot.ps1 for version " & ver, vbCritical, "Claude Connect"'
                '  WScript.Quit 1'
                'End If'
                'src = fso.GetParentFolderName(boot)'
                'sh.CurrentDirectory = src'
                'sh.Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File """ & boot & """", 1, False'
            ) -join "`r`n"
            # VBScript needs UTF-16 LE (BOM) for non-ASCII paths; UTF-8 mojibakes ط/و etc.
            [IO.File]::WriteAllText($vbsPath, $vbs + "`r`n", [Text.Encoding]::Unicode)
            $cmdPath = Join-Path $desk 'Claude-Connect.cmd'
            $cmd = "@echo off`r`nwscript.exe //B //Nologo `"%~dp0Claude-Connect.vbs`"`r`nexit /b 0`r`n"
            [IO.File]::WriteAllText($cmdPath, $cmd, [Text.UTF8Encoding]::new($false))
            $verExe = Join-Path $VerDir ("Claude-Connect-{0}.exe" -f $ver)
            if (Test-Path -LiteralPath $verExe) {
                try { Copy-Item -LiteralPath $verExe -Destination (Join-Path $desk 'Claude-Connect.exe') -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
        if (Get-Command Repair-ConnectRootLayout -ErrorAction SilentlyContinue) {
            [void](Repair-ConnectRootLayout -Root $Root -Ver $ver)
        }
        foreach ($stale in @('Claude-Connect.vbs', 'Claude-Connect.cmd', 'Claude-Connect.exe', 'connect.bat', 'current.txt')) {
            Remove-Item -LiteralPath (Join-Path $Root $stale) -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path $VerDir $stale) -Force -ErrorAction SilentlyContinue
        }
        Log ("instant_launcher ok root={0} ver={1} (folders-only)" -f $Root, $ver)
    } catch {
        Log ("instant_launcher_warn $($_.Exception.Message)")
    }
}

function Move-LaunchExeIntoVerDir {
    param([string]$LaunchExe, [string]$DestExe, [string]$LaunchParent, [string]$VerDir)
    if (-not $LaunchExe -or -not (Test-Path -LiteralPath $LaunchExe)) { return $false }
    try {
        $srcFull = [IO.Path]::GetFullPath($LaunchExe)
        $dstFull = [IO.Path]::GetFullPath($DestExe)
    } catch { return $false }
    if ($srcFull -eq $dstFull) { return $false }
    New-Item -ItemType Directory -Force -Path $VerDir | Out-Null
    # Keep Desktop / claude-publish EXE in place so user can always double-click EXE.
    $keepSrc = $false
    try {
        $desk = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'Desktop'))
        if ($srcFull.StartsWith($desk, [StringComparison]::OrdinalIgnoreCase)) { $keepSrc = $true }
        if ($srcFull -match '(?i)[\\/]claude-publish[\\/]') { $keepSrc = $true }
    } catch {}
    try {
        Copy-Item -LiteralPath $srcFull -Destination $dstFull -Force
        if (-not $keepSrc -and $srcFull -ne $dstFull) {
            Remove-Item -LiteralPath $srcFull -Force -ErrorAction SilentlyContinue
        }
        return $true
    } catch { return $false }
}

function Prune-OldVersionDirs {
    param([string]$Root, [int]$Keep = 3)
    if (-not (Test-Path -LiteralPath $Root)) { return }
    $dirs = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{8}\.\d+$' } |
        Sort-Object {
            if ($_.Name -match '^(\d{8})\.(\d+)$') { [int64]$Matches[1] * 10000 + [int]$Matches[2] } else { 0 }
        } -Descending)
    if ($dirs.Count -le $Keep) { return }
    foreach ($d in $dirs[$Keep..($dirs.Count - 1)]) {
        try {
            Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Log ("prune_removed ver={0}" -f $d.Name)
        } catch { }
    }
}

try {
    if (-not $env:CLAUDE_CONNECT_RUN_ID) {
        $env:CLAUDE_CONNECT_RUN_ID = [guid]::NewGuid().ToString('N').Substring(0, 12)
    }

    $resolved = Resolve-ConnectLaunchExe -ExtractSrc $Src
    $launchParent = [string]$resolved.LaunchParent
    $launchExe = [string]$resolved.Exe
    if ($resolved.How -eq 'fallback_desktop') {
        $launchParent = Split-Path -Parent $FallbackRoot
    }

    $version = Get-PackagedConnectVersion -ExtractSrc $Src -LaunchExe $launchExe
    if (-not $version) { throw 'connect-version.txt missing from package (and EXE name has no version)' }

    $tree = Resolve-VersionedTree -LaunchParent $launchParent -Version $version
    $Root = $tree.Root
    $VerDir = $tree.VerDir
    $SrcDir = $tree.SrcDir
    $DestExe = $tree.DestExe

    Log ("setup begin src={0} pid={1} run_id={2}" -f $Src, $PID, $env:CLAUDE_CONNECT_RUN_ID)
    Log ("setup tree root={0} ver={1} src={2} how={3} launch_exe={4}" -f `
        $Root, $version, $SrcDir, $resolved.How, $(if ($launchExe) { $launchExe } else { '-' }))

    # Fleet always double-clicks Desktop\Claude-Connect.exe. Stale SFX packages must NOT
    # fast_path/boot an older VerDir when a newer healthy tree already exists on disk
    # (seen 2026-08-03: EXE package 20260802.4 -> fast_path -> connect.ps1 still .1).
    $diskBest = ''
    if (Get-Command Get-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
        try { $diskBest = [string](Get-ConnectInstallCurrent -Root $Root) } catch { $diskBest = '' }
    }
    if ($diskBest -match '^\d{8}\.\d+$' -and
        ((Get-ConnectVersionSortKeyLocal -Ver $diskBest) -gt (Get-ConnectVersionSortKeyLocal -Ver $version))) {
        $preferSrc = Join-Path $Root (Join-Path $diskBest 'src')
        $preferOk = $false
        if (Get-Command Test-ConnectVerSrcComplete -ErrorAction SilentlyContinue) {
            $preferOk = [bool](Test-ConnectVerSrcComplete -SrcDir $preferSrc -Ver $diskBest)
        } else {
            $preferOk = Test-VersionSrcComplete -SrcDir $preferSrc -Version $diskBest
        }
        if ($preferOk) {
            Log ("setup prefer_disk_newer disk={0} pkg={1}" -f $diskBest, $version)
            $version = $diskBest
            $tree = Resolve-VersionedTree -LaunchParent $launchParent -Version $version
            $Root = $tree.Root
            $VerDir = $tree.VerDir
            $SrcDir = $tree.SrcDir
            $DestExe = $tree.DestExe
        }
    }

    # One-time flat -> versioned migrate (Desktop\Claude-Connect with scripts at root).
    if ((Test-Path -LiteralPath (Join-Path $Root 'connect.ps1')) -and -not (Test-Path -LiteralPath (Join-Path $SrcDir 'connect.ps1'))) {
        try {
            $flatVer = $version
            $fv = Join-Path $Root 'connect-version.txt'
            if (Test-Path -LiteralPath $fv) {
                $t = (Get-Content -LiteralPath $fv -Raw -ErrorAction SilentlyContinue).Trim()
                if ($t -match '^\d{8}\.\d+$') { $flatVer = $t }
            }
            $migVerDir = Join-Path $Root $flatVer
            $migSrc = Join-Path $migVerDir 'src'
            New-Item -ItemType Directory -Force -Path $migSrc | Out-Null
            Get-ChildItem -LiteralPath $Root -File -ErrorAction SilentlyContinue | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination (Join-Path $migSrc $_.Name) -Force -ErrorAction SilentlyContinue
            }
            $version = $flatVer
            $VerDir = $migVerDir
            $SrcDir = $migSrc
            $DestExe = Join-Path $VerDir ("Claude-Connect-{0}.exe" -f $version)
            if (Get-Command Set-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
                try { Set-ConnectInstallCurrent -Root $Root -Ver $version } catch {}
            }
            Remove-Item -LiteralPath (Join-Path $Root 'current.txt') -Force -ErrorAction SilentlyContinue
            Log ("setup flat_migrated ver={0} src={1}" -f $version, $SrcDir)
            $env:CLAUDE_CONNECT_RELOCATE = '1'
        } catch {
            Log ("setup flat_migrate_warn $($_.Exception.Message)")
        }
    }

    $complete = Test-VersionSrcComplete -SrcDir $SrcDir -Version $version
    $didInstall = $false
    $didMove = $false

    if ($complete) {
        Log ("setup fast_path ver={0} src_complete=1" -f $version)
        # Ensure versioned EXE exists beside src (best-effort, no rewrite if present).
        if ($launchExe -and -not (Test-Path -LiteralPath $DestExe)) {
            $didMove = [bool](Move-LaunchExeIntoVerDir -LaunchExe $launchExe -DestExe $DestExe -LaunchParent $launchParent -VerDir $VerDir)
            if ($didMove) { Log 'setup move_exe_into_ver (src already complete)' }
        }
    } else {
        Log ("setup install_or_repair ver={0}" -f $version)
        New-Item -ItemType Directory -Force -Path $VerDir, $SrcDir | Out-Null
        Copy-PayloadToSrc -ExtractSrc $Src -SrcDir $SrcDir
        if (-not (Test-VersionSrcComplete -SrcDir $SrcDir -Version $version)) {
            throw "src incomplete after copy: $SrcDir"
        }
        $didInstall = $true
        if ($launchExe) {
            $didMove = [bool](Move-LaunchExeIntoVerDir -LaunchExe $launchExe -DestExe $DestExe -LaunchParent $launchParent -VerDir $VerDir)
            Log ("setup move_exe ok={0} dest={1}" -f [int]$didMove, $DestExe)
        } elseif (Test-Path -LiteralPath (Join-Path $Src 'Claude-Connect.exe')) {
            # Package may ship unversioned Claude-Connect.exe inside SFX payload.
            try {
                Copy-Item -LiteralPath (Join-Path $Src 'Claude-Connect.exe') -Destination $DestExe -Force
            } catch { }
        }
        Prune-OldVersionDirs -Root $Root -Keep 3
    }

    # verdir_leaf_wins: if EXE already lives under Claude-Connect\{ver}\, that leaf is authoritative.
    $verDirLeaf = Split-Path -Leaf $VerDir
    if ($verDirLeaf -match '^\d{8}\.\d+$') {
        $version = $verDirLeaf
        $DestExe = Join-Path $VerDir ("Claude-Connect-{0}.exe" -f $version)
    }

    if (Get-Command Set-ConnectInstallCurrent -ErrorAction SilentlyContinue) {
        try { Set-ConnectInstallCurrent -Root $Root -Ver $version } catch {}
    }
    Set-SrcVersionStamp -SrcDir $SrcDir -Version $version
    Repair-SetupVerDirContract -Root $Root -VerDir $VerDir -SrcDir $SrcDir -Version $version

    Write-ConnectInstantLauncher -VerDir $VerDir -SrcDir $SrcDir -Root $Root

    # Root = version folders ONLY (no flat script dump from IExpress).
    if (Get-Command Repair-ConnectRootLayout -ErrorAction SilentlyContinue) {
        try {
            [void](Repair-ConnectRootLayout -Root $Root -Ver $version)
            Log ("setup root_layout_ok ver={0}" -f $version)
        } catch {
            Log ("setup root_layout_warn $($_.Exception.Message)")
        }
    }

    if ($env:CLAUDE_CONNECT_SETUP_NO_LAUNCH -eq '1') {
        Log 'setup skip reason=NO_LAUNCH=1 files-only'
        exit 0
    }

    if (Test-ConnectUiOpen) {
        Log 'setup skip reason=ui_already_open'
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            [System.Windows.Forms.MessageBox]::Show(
                '10 Claude Connect windows already open - close one, then retry.',
                'Claude Connect',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        } catch { }
        exit 0
    }

    $env:CLAUDE_CONNECT_FROM_EXE = '1'
    $env:CLAUDE_CONNECT_INSTALL_DIR = $SrcDir
    $env:CLAUDE_CONNECT_LAUNCH_DIR = $VerDir
    $env:CLAUDE_CONNECT_ROOT = $Root
    $env:CLAUDE_CONNECT_VER_DIR = $VerDir
    if ($DestExe) { $env:CLAUDE_CONNECT_LAUNCH_EXE = $DestExe }
    elseif ($launchExe) { $env:CLAUDE_CONNECT_LAUNCH_EXE = $launchExe }
    Remove-Item Env:CLAUDE_CONNECT_SHOW_INSTALL_NOTICE -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_CONNECT_NOTICE_VER -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_CONNECT_NOTICE_DIR -ErrorAction SilentlyContinue

    try {
        $stampDir = Join-Path $env:USERPROFILE '.config\claude-connect'
        New-Item -ItemType Directory -Force -Path $stampDir | Out-Null
        Set-Content -LiteralPath (Join-Path $stampDir 'last-launch-dir.txt') -Value $VerDir -Encoding ASCII -NoNewline
        Log ("launch_dir={0}" -f $VerDir)
    } catch {
        Log ("launch_dir_warn $($_.Exception.Message)")
    }

    # FAST PATH: src already complete — boot UI directly (no worker, no network update).
    # Spawn Connect UI as the only visible window (no intermediate cmd).
    if ($complete -and -not $didInstall) {
        $boot = Join-Path $SrcDir 'connect-boot.ps1'
        if (-not (Test-Path -LiteralPath $boot)) { throw "connect-boot.ps1 missing: $boot" }
        Start-Process -FilePath 'powershell.exe' -WorkingDirectory $SrcDir -ArgumentList @(
            '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass',
            '-File', "`"$boot`""
        ) -WindowStyle Normal | Out-Null
        Log ("setup ok fast_path direct_boot dir={0}" -f $SrcDir)
        exit 0
    }

    if ($didMove -or $didInstall) {
        $env:CLAUDE_CONNECT_RELOCATE = '1'
        Log ("setup relocate ver={0} ver_dir={1} src={2}" -f $version, $VerDir, $SrcDir)
    }

    # First install / repair: refresh worker + run update then boot.
    $workerSrc = Join-Path $Src 'setup-worker.ps1'
    $workerDest = Join-Path $SrcDir 'setup-worker.ps1'
    if (-not (Test-Path -LiteralPath $workerSrc)) { throw "setup-worker.ps1 missing in package: $workerSrc" }
    Copy-Item -LiteralPath $workerSrc -Destination $workerDest -Force

    try {
        Get-ChildItem -LiteralPath $SrcDir -File -ErrorAction SilentlyContinue | ForEach-Object {
            try { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } catch { }
        }
        Log 'unblock_motw ok'
    } catch {
        Log ("unblock_motw_warn $($_.Exception.Message)")
    }

    Start-Process -FilePath 'powershell.exe' -WorkingDirectory $SrcDir -ArgumentList @(
        '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', "`"$workerDest`""
    ) -WindowStyle Hidden | Out-Null

    Log 'setup ok detached worker spawned; exiting fast to release wextract single-instance mutex'
    exit 0

} catch {
    $msg = $_.Exception.Message -replace '[\r\n]', ' '
    $stack = ''
    try { $stack = ($_.ScriptStackTrace -replace '[\r\n]', ' | ') } catch { }
    Log ("SETUP_FAIL $msg")
    if ($stack) { Log ("SETUP_FAIL_STACK $stack") }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            ("Setup failed: {0}`r`nLog: {1}" -f $_.Exception.Message, $Log),
            'Claude Connect',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch { }
    exit 1
}
