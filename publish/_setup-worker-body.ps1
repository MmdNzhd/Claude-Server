#Requires -Version 5.1
# setup-worker.ps1 - detached background worker spawned by setup-launch.ps1.
#
# 1) Optional relocate cleanup
# 2) Pre-boot update DISABLED — updates are menu-only (press u). Never auto-apply.
# 3) Boot Connect UI from versioned src dir (no install MessageBox / no confirm)

$ErrorActionPreference = 'Stop'
$Log = Join-Path $env:TEMP 'claude-connect-setup.log'

function Log([string]$m) {
    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    try { Add-Content -LiteralPath $Log -Value $line -Encoding UTF8 } catch { }
    try {
        $d = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        $f = Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = if ($env:CLAUDE_CONNECT_RUN_ID) { $env:CLAUDE_CONNECT_RUN_ID } else { 'setup' }
        $day = "[$ts] [INFO] [$sid] SETUP_WORKER: $m"
        [IO.File]::AppendAllText($f, $day + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        if ($m -match '(?i)fail|error|skip|exit=') {
            $bread = Join-Path $env:USERPROFILE '.config\claude-connect\last-fail.txt'
            [IO.File]::AppendAllText($bread, $day + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        }
    } catch { }
}

function Test-ConnectBootPresent {
    param([string]$Dir)
    if (-not $Dir) { return $false }
    try {
        return (Test-Path -LiteralPath (Join-Path ([IO.Path]::GetFullPath($Dir)) 'connect-boot.ps1'))
    } catch { return $false }
}

function Find-NewestVersionedSrc {
    param([string]$Root)
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { return $null }
    $dirs = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{8}\.\d+$' } |
        Sort-Object {
            if ($_.Name -match '^(\d{8})\.(\d+)$') { [int64]$Matches[1] * 10000 + [int]$Matches[2] } else { 0 }
        } -Descending)
    foreach ($d in $dirs) {
        $src = Join-Path $d.FullName 'src'
        if (Test-ConnectBootPresent -Dir $src) { return $src }
    }
    return $null
}

function Resolve-ConnectWorkerDest {
    # Always returns a directory that contains connect-boot.ps1, or $null.
    # Never returns Claude-Connect\ root when only versioned {ver}\src exists.
    $dest = $null
    if ($env:CLAUDE_CONNECT_INSTALL_DIR) {
        try {
            $cand = [IO.Path]::GetFullPath($env:CLAUDE_CONNECT_INSTALL_DIR.Trim())
            if (Test-ConnectBootPresent -Dir $cand) { $dest = $cand }
        } catch { }
    }

    $rootHint = $null
    if ($env:CLAUDE_CONNECT_ROOT) {
        try { $rootHint = [IO.Path]::GetFullPath($env:CLAUDE_CONNECT_ROOT.Trim()) } catch { }
    }
    if (-not $rootHint -and $dest) {
        try {
            $verDir = Split-Path -Parent $dest
            $maybeRoot = Split-Path -Parent $verDir
            if ((Split-Path -Leaf $dest) -eq 'src' -and (Split-Path -Leaf $maybeRoot) -eq 'Claude-Connect') {
                $rootHint = $maybeRoot
            }
        } catch { }
    }
    if (-not $rootHint -and $env:CLAUDE_CONNECT_VER_DIR) {
        try {
            $vd = [IO.Path]::GetFullPath($env:CLAUDE_CONNECT_VER_DIR.Trim())
            $rootHint = Split-Path -Parent $vd
        } catch { }
    }
    if (-not $rootHint) {
        $rootHint = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
    }

    $curFile = Join-Path $rootHint 'current.txt'
    if (Test-Path -LiteralPath $curFile) {
        $cv = (Get-Content -LiteralPath $curFile -Raw -ErrorAction SilentlyContinue).Trim()
        $cand = Join-Path (Join-Path $rootHint $cv) 'src'
        if ($cv -and (Test-ConnectBootPresent -Dir $cand)) { return $cand }
    }

    if ($dest) { return $dest }

    $newest = Find-NewestVersionedSrc -Root $rootHint
    if ($newest) { return $newest }

    if (Test-ConnectBootPresent -Dir $rootHint) { return $rootHint }

    $desk = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
    if ($rootHint -ne $desk) {
        $cur2 = Join-Path $desk 'current.txt'
        if (Test-Path -LiteralPath $cur2) {
            $cv2 = (Get-Content -LiteralPath $cur2 -Raw -ErrorAction SilentlyContinue).Trim()
            $cand2 = Join-Path (Join-Path $desk $cv2) 'src'
            if ($cv2 -and (Test-ConnectBootPresent -Dir $cand2)) { return $cand2 }
        }
        $n2 = Find-NewestVersionedSrc -Root $desk
        if ($n2) { return $n2 }
        if (Test-ConnectBootPresent -Dir $desk) { return $desk }
    }
    return $null
}

function Test-ConnectUiOpen {
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

function Stop-OldConnectUiBestEffort {
    param([string]$KeepSrcDir)
    try {
        $keep = ''
        try { $keep = [IO.Path]::GetFullPath($KeepSrcDir).TrimEnd('\') } catch { $keep = $KeepSrcDir }
        Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
            $cmd = [string]$_.CommandLine
            if (-not $cmd) { return }
            if ($cmd -notmatch '(?i)connect-(boot|ui)\.ps1|connect\.ps1') { return }
            if ($keep -and $cmd -like ("*{0}*" -f $keep)) { return }
            try {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
                Log ("relocate_closed_old_ui pid={0}" -f $_.ProcessId)
            } catch { }
        }
    } catch { }
}

try {
    if (-not $env:CLAUDE_CONNECT_RUN_ID) {
        $env:CLAUDE_CONNECT_RUN_ID = [guid]::NewGuid().ToString('N').Substring(0, 12)
    }

    $Dest = Resolve-ConnectWorkerDest
    if (-not (Test-ConnectBootPresent -Dir $Dest)) {
        throw 'No usable Claude Connect install found (connect-boot.ps1 missing). Open a fresh Claude-Connect-*.exe from Desktop\claude-publish.'
    }
    Log ("worker begin dest={0} pid={1} run_id={2}" -f $Dest, $PID, $env:CLAUDE_CONNECT_RUN_ID)

    $upd = Join-Path $Dest 'connect-update.ps1'
    $boot = Join-Path $Dest 'connect-boot.ps1'
    if (-not (Test-Path -LiteralPath $upd)) { throw "connect-update.ps1 missing: $upd" }

    $launchMutex = $null
    $launchCreated = $false
    try {
        $launchMutex = New-Object System.Threading.Mutex($false, 'Global\ClaudeConnectExeLaunch', [ref]$launchCreated)
        $gotLaunch = $false
        try { $gotLaunch = $launchMutex.WaitOne(15000) } catch [System.Threading.AbandonedMutexException] { $gotLaunch = $true }
        if (-not $gotLaunch) {
            Log 'worker skip reason=exe_launch_mutex_busy (another launch already in progress)'
            exit 0
        }
    } catch {
        Log ("launch_mutex_warn $($_.Exception.Message)")
    }

    $env:CLAUDE_CONNECT_FROM_EXE = '1'
    $env:CLAUDE_CONNECT_INSTALL_DIR = $Dest

    if ($env:CLAUDE_CONNECT_RELOCATE -eq '1') {
        Stop-OldConnectUiBestEffort -KeepSrcDir $Dest
    }

    try {
        Get-ChildItem -LiteralPath $Dest -File -ErrorAction SilentlyContinue | ForEach-Object {
            try { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } catch { }
        }
        Log 'unblock_motw ok'
    } catch {
        Log ("unblock_motw_warn $($_.Exception.Message)")
    }

    # Manual-only updates: never run connect-update from EXE worker.
    # User presses u in the Connect menu when they want an update.
    Log 'preboot update skipped reason=manual_only'
    if ($env:CLAUDE_CONNECT_SETUP_NO_UPDATE -eq '1' -or $env:CLAUDE_CONNECT_FAST_PATH -eq '1') {
        Log 'preboot update note=also_fast_path_or_NO_UPDATE'
    }

    $boot = Join-Path $Dest 'connect-boot.ps1'
    if (-not (Test-ConnectBootPresent -Dir $Dest)) {
        throw "connect-boot.ps1 missing before boot: $boot"
    }

    if (Test-ConnectUiOpen) {
        Log 'worker skip boot reason=ui_already_open'
    } else {
        Log 'connect-boot start begin (after_preboot_update=0 manual_only=1)'
        # Quote -File: ArgumentList array does not auto-quote paths with spaces.
        $p = Start-Process -FilePath 'powershell.exe' -WorkingDirectory $Dest -ArgumentList @(
            '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass',
            '-File', "`"$boot`""
        ) -PassThru -WindowStyle Normal
        if (-not $p) { throw 'Start-Process connect-boot.ps1 returned null' }
        Log ("connect-boot started pid=$($p.Id) dir=$Dest")

        # Short hold so a double-click does not spawn a second worker while boot starts.
        $debounceMs = 100
        if ($debounceMs -gt 0) {
            Start-Sleep -Milliseconds $debounceMs
        }
        Log ("connect-boot debounce done ms=$debounceMs")
    }

    Log 'worker ok'
    if ($launchMutex) {
        try { $launchMutex.ReleaseMutex() } catch { }
        try { $launchMutex.Dispose() } catch { }
    }
    exit 0

} catch {
    $msg = $_.Exception.Message -replace '[\r\n]', ' '
    $stack = ''
    try { $stack = ($_.ScriptStackTrace -replace '[\r\n]', ' | ') } catch { }
    Log ("SETUP_WORKER_FAIL $msg")
    if ($stack) { Log ("SETUP_WORKER_FAIL_STACK $stack") }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            ("Claude Connect failed to start: {0}`r`nLog: {1}" -f $_.Exception.Message, $Log),
            'Claude Connect',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch { }
    exit 1
}
