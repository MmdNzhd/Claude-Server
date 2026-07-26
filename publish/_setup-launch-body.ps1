#Requires -Version 5.1
# setup-launch.ps1 - IExpress AppLaunched entry point for Claude-Connect.exe.
#
# CRITICAL DESIGN (2026-07-25): this script MUST return within ~1s. The IExpress wextract.exe
# wrapper holds its own single-instance mutex for as long as this AppLaunched command runs, and
# only releases it when this process exits. Any slow work here (the network update check, the UI
# boot, a debounce) kept that mutex held for ~5-13s, which (a) made a 2nd double-click of
# Claude-Connect.exe hit wextract's built-in "Setup has detected that Setup is currently running"
# dialog, and (b) left the transient extractor cmd window lingering. So all the slow/gated work now
# runs in a DETACHED worker (setup-worker.ps1) that outlives this process; this script just copies
# files and spawns the worker, then exits fast to release wextract's mutex.

$ErrorActionPreference = 'Stop'

$Dest = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$Src = $PSScriptRoot
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
        $day = "[$ts] [INFO] [$sid] SETUP: $m"
        [IO.File]::AppendAllText($f, $day + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        if ($m -match '(?i)fail|error|skip|exit=') {
            $bread = Join-Path $env:USERPROFILE '.config\claude-connect\last-fail.txt'
            [IO.File]::AppendAllText($bread, $day + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        }
    } catch { }
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

try {
    if (-not $env:CLAUDE_CONNECT_RUN_ID) {
        $env:CLAUDE_CONNECT_RUN_ID = [guid]::NewGuid().ToString('N').Substring(0, 12)
    }
    Log ("setup begin src={0} pid={1} run_id={2}" -f $Src, $PID, $env:CLAUDE_CONNECT_RUN_ID)
    Log ("setup dest={0}" -f $Dest)

    if (-not (Test-Path -LiteralPath $Dest)) {
        New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    }

    # setup-worker.ps1 is copied explicitly to $Dest below (it must live in the persistent Dest, not
    # in the temp extraction dir that wextract deletes the moment this script exits).
    $skip = @('setup-claude-connect.cmd', 'setup-launch.ps1', 'setup-worker.ps1', 'READ-ME-USERS.txt')

    Get-ChildItem -LiteralPath $Src -File | Where-Object { $skip -notcontains $_.Name } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Dest $_.Name) -Force
    }

    $upd = Join-Path $Dest 'connect-update.ps1'
    $boot = Join-Path $Dest 'connect-boot.ps1'
    if (-not (Test-Path -LiteralPath $upd)) { throw "connect-update.ps1 missing after copy: $upd" }
    if (-not (Test-Path -LiteralPath $boot)) { throw "connect-boot.ps1 missing after copy: $boot" }

    # Copy the detached worker into the persistent Dest (survives wextract temp cleanup).
    $workerSrc = Join-Path $Src 'setup-worker.ps1'
    $workerDest = Join-Path $Dest 'setup-worker.ps1'
    if (-not (Test-Path -LiteralPath $workerSrc)) { throw "setup-worker.ps1 missing in package: $workerSrc" }
    Copy-Item -LiteralPath $workerSrc -Destination $workerDest -Force

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

    # Spawn the detached worker (hidden) and EXIT FAST. This releases wextract's single-instance
    # mutex within ~1s, so a 2nd double-click no longer hits "Setup is currently running" and the
    # extractor cmd window closes immediately. The worker runs the update check (WinForms progress
    # UI only if a download is needed) and starts the connect UI. The Global\ClaudeConnectExeLaunch
    # double-launch gate lives in the worker now (see _setup-worker-body.ps1).
    $env:CLAUDE_CONNECT_FROM_EXE = '1'
    # Remember where the user double-clicked the SFX so updates can drop Claude-Connect-VER.exe
    # next to that folder (e.g. Desktop\claude-publish), not only Desktop\Claude-Connect.
    try {
        $launchExe = $null
        try { $launchExe = (Get-Process -Id $PID -ErrorAction Stop).Path } catch {}
        if (-not $launchExe) {
            try { $launchExe = [Environment]::GetCommandLineArgs()[0] } catch {}
        }
        if ($launchExe -and (Test-Path -LiteralPath $launchExe)) {
            $launchDir = Split-Path -Parent $launchExe
            $env:CLAUDE_CONNECT_LAUNCH_EXE = $launchExe
            $env:CLAUDE_CONNECT_LAUNCH_DIR = $launchDir
            $stampDir = Join-Path $env:USERPROFILE '.config\claude-connect'
            New-Item -ItemType Directory -Force -Path $stampDir | Out-Null
            Set-Content -LiteralPath (Join-Path $stampDir 'last-launch-dir.txt') -Value $launchDir -Encoding ASCII -NoNewline
            Log ("launch_dir={0}" -f $launchDir)
        }
    } catch {
        Log ("launch_dir_warn $($_.Exception.Message)")
    }
    Start-Process -FilePath 'powershell.exe' -WorkingDirectory $Dest -ArgumentList @(
        '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $workerDest
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
