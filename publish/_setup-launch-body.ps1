#Requires -Version 5.1
# setup-launch.ps1 - IExpress AppLaunched entry point for Claude-Connect.exe.
#
# CRITICAL DESIGN (2026-07-25): this script MUST return within ~1s. The IExpress wextract.exe
# wrapper holds its own single-instance mutex for as long as this AppLaunched command runs.
# First install: DETACHED setup-worker.ps1 (optional network update + boot).
# Fast path (src already complete): direct connect-boot — no worker / no network.
# Day-to-day instant reopen: Claude-Connect.vbs (+ .cmd trampoline) beside the versioned EXE.
#
# VERSIONED LAYOUT (2026-07-27):
#   {launchParent}\Claude-Connect\{ver}\Claude-Connect-{ver}.exe
#   {launchParent}\Claude-Connect\{ver}\src\   <- scripts (ScriptDir)
# Fast path (~0ms feel): if src already complete for this ver -> skip copy/move; spawn worker.

$ErrorActionPreference = 'Stop'

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
        $day = "[$ts] [INFO] [$sid] SETUP: $m"
        [IO.File]::AppendAllText($f, $day + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        if ($m -match '(?i)fail|error|skip|exit=') {
            $bread = Join-Path $env:USERPROFILE '.config\claude-connect\last-fail.txt'
            [IO.File]::AppendAllText($bread, $day + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
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

function Test-VersionSrcComplete {
    # Hot path: a few Test-Path + one tiny read. No hashing, no tree walk.
    param([string]$SrcDir, [string]$Version)
    if (-not $SrcDir -or -not $Version) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $SrcDir 'connect.bat'))) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $SrcDir 'connect.ps1'))) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $SrcDir 'connect-boot.ps1'))) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $SrcDir 'connect-update.ps1'))) { return $false }
    $vf = Join-Path $SrcDir 'connect-version.txt'
    if (-not (Test-Path -LiteralPath $vf)) { return $false }
    try {
        $v = (Get-Content -LiteralPath $vf -Raw -ErrorAction Stop).Trim()
        return ($v -eq $Version)
    } catch { return $false }
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
    # Instant reopen beside the versioned EXE — no IExpress extract.
    # Prefer .vbs (no console). .cmd is a thin wscript trampoline that exits
    # immediately so Explorer double-click never leaves an orphan cmd window
    # (old start "title" powershell form could leave a titled empty console).
    param([string]$VerDir, [string]$SrcDir)
    if (-not $VerDir -or -not $SrcDir) { return }
    try {
        New-Item -ItemType Directory -Force -Path $VerDir | Out-Null
        $vbsPath = Join-Path $VerDir 'Claude-Connect.vbs'
        $vbs = @(
            "' Claude Connect - instant reopen (no cmd console)"
            'Set sh = CreateObject("WScript.Shell")'
            'Set fso = CreateObject("Scripting.FileSystemObject")'
            'dir = fso.GetParentFolderName(WScript.ScriptFullName)'
            'src = dir & "\src"'
            'boot = src & "\connect-boot.ps1"'
            'If Not fso.FileExists(boot) Then'
            '  MsgBox "Missing connect-boot.ps1 in:" & vbCrLf & src, vbCritical, "Claude Connect"'
            '  WScript.Quit 1'
            'End If'
            'sh.CurrentDirectory = src'
            'sh.Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File """ & boot & """", 1, False'
        ) -join "`r`n"
        [IO.File]::WriteAllText($vbsPath, $vbs + "`r`n", [Text.UTF8Encoding]::new($false))

        $cmdPath = Join-Path $VerDir 'Claude-Connect.cmd'
        $cmd = @(
            '@echo off'
            'REM Instant reopen — hand off to VBS (no lingering console).'
            'start "" /MIN wscript.exe //B //Nologo "%~dp0Claude-Connect.vbs"'
            'exit /b 0'
        ) -join "`r`n"
        [IO.File]::WriteAllText($cmdPath, $cmd + "`r`n", [Text.UTF8Encoding]::new($false))
        Log ("instant_launcher ok vbs={0} cmd={1}" -f $vbsPath, $cmdPath)
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
    # Prefer move (user asked); fall back to copy+delete if move fails (cross-volume / lock).
    try {
        if (Test-Path -LiteralPath $dstFull) {
            Copy-Item -LiteralPath $srcFull -Destination $dstFull -Force
            if ($srcFull -ne $dstFull) {
                Remove-Item -LiteralPath $srcFull -Force -ErrorAction SilentlyContinue
            }
        } else {
            Move-Item -LiteralPath $srcFull -Destination $dstFull -Force
        }
        return $true
    } catch {
        try {
            Copy-Item -LiteralPath $srcFull -Destination $dstFull -Force
            Remove-Item -LiteralPath $srcFull -Force -ErrorAction SilentlyContinue
            return $true
        } catch { return $false }
    }
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
                if ($_.Name -eq 'current.txt') { return }
                Move-Item -LiteralPath $_.FullName -Destination (Join-Path $migSrc $_.Name) -Force -ErrorAction SilentlyContinue
            }
            $version = $flatVer
            $VerDir = $migVerDir
            $SrcDir = $migSrc
            $DestExe = Join-Path $VerDir ("Claude-Connect-{0}.exe" -f $version)
            Set-Content -LiteralPath (Join-Path $Root 'current.txt') -Value $version -Encoding ASCII -NoNewline
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

    try {
        Set-Content -LiteralPath (Join-Path $Root 'current.txt') -Value $version -Encoding ASCII -NoNewline
    } catch { }

    Write-ConnectInstantLauncher -VerDir $VerDir -SrcDir $SrcDir

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
    # IExpress extract still costs time on *.exe clicks; use Claude-Connect.vbs for instant reopen.
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
