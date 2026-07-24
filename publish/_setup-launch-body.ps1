#Requires -Version 5.1

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
    # Do NOT scan Win32_Process CommandLine â€” that false-blocks when any connect UI is open.
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

    $skip = @('setup-claude-connect.cmd', 'setup-launch.ps1', 'READ-ME-USERS.txt')

    Get-ChildItem -LiteralPath $Src -File | Where-Object { $skip -notcontains $_.Name } | ForEach-Object {

        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Dest $_.Name) -Force

    }

    $upd = Join-Path $Dest 'connect-update.ps1'

    $boot = Join-Path $Dest 'connect-boot.ps1'

    if (-not (Test-Path -LiteralPath $upd)) { throw "connect-update.ps1 missing after copy: $upd" }

    if (-not (Test-Path -LiteralPath $boot)) { throw "connect-boot.ps1 missing after copy: $boot" }



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



    $launchMutex = $null

    $launchCreated = $false

    try {

        $launchMutex = New-Object System.Threading.Mutex($false, 'Global\ClaudeConnectExeLaunch', [ref]$launchCreated)

        $gotLaunch = $false

        try { $gotLaunch = $launchMutex.WaitOne(15000) } catch [System.Threading.AbandonedMutexException] { $gotLaunch = $true }

        if (-not $gotLaunch) {

            Log 'setup skip reason=exe_launch_mutex_busy'

            try {

                Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

                [System.Windows.Forms.MessageBox]::Show(

                    'Claude Connect is already starting. Please wait.',

                    'Claude Connect',

                    [System.Windows.Forms.MessageBoxButtons]::OK,

                    [System.Windows.Forms.MessageBoxIcon]::Information

                ) | Out-Null

            } catch { }

            exit 0

        }

    } catch {

        Log ("launch_mutex_warn $($_.Exception.Message)")

    }



    # No cmd.exe / connect.bat. Update here (WinForms progress ONLY if download needed),

    # then one PowerShell UI via connect-boot.ps1.

    $env:CLAUDE_CONNECT_FROM_EXE = '1'

    $env:CLAUDE_CONNECT_UPDATE_UI = '1'

    Log 'update check begin (no cmd; progress UI only if download)'

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

        Log 'setup skip boot reason=ui_already_open_after_update'

    } else {

        Log 'connect-boot start begin'

        $p = Start-Process -FilePath 'powershell.exe' -WorkingDirectory $Dest -ArgumentList @(

            '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $boot

        ) -PassThru -WindowStyle Normal

        if (-not $p) { throw 'Start-Process connect-boot.ps1 returned null' }

        Log ("connect-boot started pid=$($p.Id) dir=$Dest")

        # Bug 11/13 fix (2026-07-24, live repro): a flat 20s sleep here - while this script (and
        # therefore the whole outer IExpress-launched Claude-Connect.exe wrapper process, since
        # IExpress waits for it) is still holding Global\ClaudeConnectExeLaunch - was directly
        # responsible for two separate live-observed bugs: (a) the window looking frozen for
        # tens of seconds after a fresh launch with zero visible progress, and (b) a SECOND
        # launch attempt (Claude-Connect.exe or Claude-Connect-Setup.exe) within that same
        # window hitting IExpress's own "Setup has detected that Setup is currently running"
        # single-instance collision, even though the FIRST launch's real UI (connect-boot.ps1)
        # had already started successfully seconds earlier.
        #
        # Test-ConnectUiOpen only flips true once ALL 10 Global\ClaudeConnect# slots are full -
        # it cannot detect "this one newly-spawned connect-boot.ps1 finished claiming its own
        # slot" (that slot index isn't observable from here without added IPC), so a poll against
        # it would almost always just burn its full timeout in the common 1-2-window case. The
        # debounce's real purpose - stop a rapid double-click from racing a second setup attempt
        # in before the new connect-boot.ps1 process is up - only needs a short window, not 20s:
        # connect-boot.ps1's own slot-claim (Test-AcquireConnectUiSlot) is a handful of in-process
        # WaitOne(0) calls, essentially instant once the new powershell.exe process starts
        # executing. A short fixed wait covers real process-start latency without the old 20s tax
        # on every single launch.
        $debounceMs = 3000
        Start-Sleep -Milliseconds $debounceMs
        Log ("connect-boot debounce done ms=$debounceMs")

    }



    Log 'setup ok'

    if ($launchMutex) {

        try { $launchMutex.ReleaseMutex() } catch { }

        try { $launchMutex.Dispose() } catch { }

    }

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

    } catch { Start-Sleep -Seconds 6 }

    exit 1

}

