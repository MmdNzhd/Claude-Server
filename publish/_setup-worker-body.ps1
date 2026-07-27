#Requires -Version 5.1
# setup-worker.ps1 - detached background worker spawned by setup-launch.ps1.
#
# WHY THIS EXISTS (2026-07-25): the IExpress self-extractor (wextract.exe) that wraps
# Claude-Connect.exe holds its OWN single-instance mutex for the ENTIRE lifetime of the
# AppLaunched command (setup-launch.ps1), which IExpress blocks on until it exits. The old
# setup-launch.ps1 ran the (network) update check + started the UI + slept a debounce all
# inline, so wextract kept its mutex for ~5-13s. During that window:
#   - a 2nd double-click of Claude-Connect.exe hit wextract's built-in
#     "Setup has detected that Setup is currently running. Please close all instances..." dialog;
#   - the transient extractor cmd window lingered for the whole update instead of closing fast.
#
# Fix: setup-launch.ps1 now only copies files (fast) then spawns THIS worker detached and exits
# within ~1s, releasing wextract's mutex immediately. All the slow/gated work lives here, in a
# process that OUTLIVES the IExpress wrapper. The Global\ClaudeConnectExeLaunch double-launch gate
# (and the post-boot debounce) moved here too, so two rapid launches still can't race a double UI.
$ErrorActionPreference = 'Stop'

$Dest = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
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

function Test-ConnectUiOpen {
    # True only when zero free Global\ClaudeConnect#0..#9 slots (same pool as connect-boot).
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
    Log ("worker begin dest={0} pid={1} run_id={2}" -f $Dest, $PID, $env:CLAUDE_CONNECT_RUN_ID)

    $upd = Join-Path $Dest 'connect-update.ps1'
    $boot = Join-Path $Dest 'connect-boot.ps1'
    if (-not (Test-Path -LiteralPath $upd)) { throw "connect-update.ps1 missing: $upd" }
    if (-not (Test-Path -LiteralPath $boot)) { throw "connect-boot.ps1 missing: $boot" }

    # Double-launch gate (moved here from setup-launch.ps1 so it is held across update+boot by a
    # process that outlives the IExpress wrapper, NOT by wextract's own mutex). WaitOne timeout is
    # short: if another worker already holds it, a UI is already coming up - just exit quietly.
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
    # Clear Mark-of-the-Web on install folder only (helps Defender/SmartScreen FP on unsigned SFX).
    # Never disables Defender / real-time protection.
    try {
        Get-ChildItem -LiteralPath $Dest -File -ErrorAction SilentlyContinue | ForEach-Object {
            try { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } catch { }
        }
        Log 'unblock_motw ok'
    } catch {
        Log ("unblock_motw_warn $($_.Exception.Message)")
    }
    $env:CLAUDE_CONNECT_UPDATE_UI = '1'
    Log 'update check begin (detached worker; WinForms progress UI only if a download is needed)'
    $updEc = 0
    try {
        & $upd -ScriptDir $Dest -Quiet
        if ($null -ne $LASTEXITCODE) { $updEc = [int]$LASTEXITCODE }
    } catch {
        Log ("update_warn $($_.Exception.Message)")
        $updEc = 1
    }
    Log ("UPDATE_EXIT exit=$updEc")
    if ($updEc -eq 2) {
        Log 'UPDATE_EXIT exit=2 need_relaunch continuing_to_connect_boot (EXE path; no bat_relaunch)'
    } elseif ($updEc -eq 1) {
        Log 'UPDATE_EXIT exit=1 update_failed continuing_to_connect_boot'
    }

    if (Test-ConnectUiOpen) {
        Log 'worker skip boot reason=ui_already_open_after_update'
    } else {
        Log 'connect-boot start begin'
        $p = Start-Process -FilePath 'powershell.exe' -WorkingDirectory $Dest -ArgumentList @(
            '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $boot
        ) -PassThru -WindowStyle Normal
        if (-not $p) { throw 'Start-Process connect-boot.ps1 returned null' }
        Log ("connect-boot started pid=$($p.Id) dir=$Dest")

        # Short debounce so a racing 2nd worker sees this launch in progress (mutex held) before we
        # release the gate - long enough for the new connect-boot.ps1 to claim its own UI slot,
        # short enough to add no meaningful tax. This no longer holds wextract's mutex (the worker
        # is detached), so it can never re-trigger "Setup is currently running".
        $debounceMs = 3000
        Start-Sleep -Milliseconds $debounceMs
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
