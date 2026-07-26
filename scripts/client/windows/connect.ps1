# connect.ps1 - Claude Code launcher for Windows.
# connect.bat invariant: g git (menu footer lives in connect-ui.ps1)
# Usage:  double-click connect.bat
#         connect.bat -Setup   (reconfigure username)

param(
    [switch]$Setup,
    [switch]$AdminFix,
    [ValidateSet('cursor','code','vscode')][string]$Ide = ''
)

$ErrorActionPreference = "Continue"
$script:ConnectScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Split-Path -Parent $MyInvocation.MyCommand.Path }


function Test-ConnectStaleUpdateFrame {
    param([string]$ScriptDir)
    $marker = Join-Path $ScriptDir '.client-update-relaunch'
    if (-not (Test-Path -LiteralPath $marker)) { return $false }
    try {
        $want = ((Get-Content -LiteralPath $marker -Raw -ErrorAction Stop) + '').Trim()
    } catch { return $false }
    if (-not $want) { return $false }
    $mine = ($env:CLAUDE_CONNECT_RUN_ID + '').Trim()
    if (($env:CLAUDE_CONNECT_IS_RELAUNCH -eq '1') -and $mine -eq $want) {
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
        return $false
    }
    return $true
}

if (Test-ConnectStaleUpdateFrame -ScriptDir $script:ConnectScriptDir) { exit 0 }

function Dot-SourceSibling {
    param([string]$Name)
    foreach ($base in @($script:ConnectScriptDir, (Split-Path $script:ConnectScriptDir -Parent), (Split-Path (Split-Path $script:ConnectScriptDir -Parent) -Parent))) {
        $p = Join-Path $base $Name
        if (Test-Path $p) { return $p }
    }
    return $null
}

$script:RunAdminFix = [bool]$AdminFix

# Elevate-when-needed: keep the main UI unelevated by default (no UAC on every start).
# Invoke-LaptopAdminOps / -AdminFix still elevates for sshd, firewall, and
# administrators_authorized_keys repairs when Ensure-LaptopSshReady requires it.

function Save-ConnectConfKey {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )
    $map = [ordered]@{}
    if (Test-Path -LiteralPath $Path) {
        Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
            if ($_ -match '^(.+?)=(.*)$') {
                $k = $Matches[1].Trim(); $v = $Matches[2]
                if ($k) { $map[$k] = $v }
            }
        }
    }
    $map[$Key] = $Value
    if (-not $map.Contains('LAPTOP_USER') -or -not [string]$map['LAPTOP_USER']) {
        if (Get-Command Get-InteractiveLaptopUser -ErrorAction SilentlyContinue) {
            $map['LAPTOP_USER'] = Get-InteractiveLaptopUser
        }
    }
    $lines = foreach ($k in $map.Keys) { "{0}={1}" -f $k, $map[$k] }
    $dir = Split-Path -Parent $Path
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $lines | Set-Content -Path $Path -Encoding ASCII
}


trap {
    Write-Host ''
    Write-Host "  [X] Unexpected error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "      $($_.InvocationInfo.PositionMessage)" -ForegroundColor DarkGray
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "UNHANDLED: $($_.Exception.Message) at $($_.InvocationInfo.PositionMessage)" 'ERROR'
        Write-ConnectLog ("FAIL UNHANDLED: {0}" -f $_.Exception.Message) 'ERROR'
    }
    # Error-flush: ensure day log sync attempted even if Write-ConnectLog sync was skipped/locked.
    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) {
        try { Sync-ConnectLogToServer -Force | Out-Null } catch { }
    }
    Write-Host ''
    # connect-ui may not be loaded yet - guard Wait-ConnectExit (bug wait-connect-exit-before-ui).
    if (Get-Command Wait-ConnectExit -ErrorAction SilentlyContinue) {
        Wait-ConnectExit -Reason 'unhandled' -Code 1
    } else {
        try { Read-Host '    Press Enter to close' | Out-Null } catch { }
        exit 1
    }
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    try {
        $d = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        $f = Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $sid = if ($env:CLAUDE_CONNECT_RUN_ID) { $env:CLAUDE_CONNECT_RUN_ID } else { '-' }
        [IO.File]::AppendAllText($f, "[$ts] [ERROR] [$sid] FAIL OpenSSH client (ssh.exe) not found`n", [Text.UTF8Encoding]::new($false))
    } catch { }
    Write-Host "  [X] OpenSSH client (ssh.exe) not found." -ForegroundColor Red
    Write-Host "      Install it via: Settings -> Apps -> Optional Features -> OpenSSH Client" -ForegroundColor DarkGray
    if (Get-Command Wait-ConnectExit -ErrorAction SilentlyContinue) {
        Wait-ConnectExit -Reason 'require_fail' -Code 1
    } else {
        try { Read-Host '    Press Enter to close' | Out-Null } catch { }
        exit 1
    }
}
$ServerIP = "192.168.210.240"
$Alias    = "claude-server"
$script:ServerIP = $ServerIP
$script:SshAlias = $Alias
$script:CursorProfileSite = 'Smart'
$script:ConnectVersion = '20260725.41'
# Internal-only build tag (never shown in the console UI) - logged to CONTEXT lines so we can
# tell exactly which build a session ran without the user seeing any version/update noise.
$script:ConnectBuildId = '21059021-b14e-4c6c-87a9-87815dbcbece'
$CfgDir   = Join-Path $env:USERPROFILE ".config\claude-connect"
$Cfg      = Join-Path $CfgDir "connect.conf"
$SshDir   = Join-Path $env:USERPROFILE ".ssh"
$CM       = '$HOME/.local/bin/claude-mount'

function Die($m) {
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "ERROR: $m" 'ERROR'
        Write-ConnectLog "FAIL DIE: $m" 'ERROR'
        if (Get-Command Close-ConnectLog -ErrorAction SilentlyContinue) { Close-ConnectLog }
    }
    Write-Host ""; Write-Host "  [X] $m" -ForegroundColor Red
    if (Get-Command Wait-ConnectExit -ErrorAction SilentlyContinue) {
        Wait-ConnectExit -Reason 'require_fail' -Code 1
    } else {
        try { Read-Host '    Press Enter to close' | Out-Null } catch { }
        exit 1
    }
}
function Test-PathLooksSepidz([string]$Dir) {
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    $n = $Dir.ToLowerInvariant()
    return ($n -match 'claude-code-sepidz') -or ($n -match 'claude-connect-sepidz')
}
# Smart package must never run from Sepidz folder names; Sepidz IP only under Sepidz tree.
try {
    $launchDir = if ($script:ConnectScriptDir) { $script:ConnectScriptDir } else { $PSScriptRoot }
    $sepidzPath = Test-PathLooksSepidz $launchDir
    if ($sepidzPath -and $ServerIP -ne '192.168.250.70') {
        Die 'REFUSE Smart/Sepidz contamination: Smart package under Sepidz path (claude-code-sepidz / Claude-Connect-Sepidz)'
    }
    $smartCanon = $false
    try {
        $canon = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
        if ($launchDir -and (Test-Path -LiteralPath $canon)) {
            $a = [IO.Path]::GetFullPath($launchDir).TrimEnd('\', '/').ToLowerInvariant()
            $b = [IO.Path]::GetFullPath($canon).TrimEnd('\', '/').ToLowerInvariant()
            if ($a -eq $b -or $a.StartsWith($b + '\')) { $smartCanon = $true }
        }
    } catch {}
    if ($ServerIP -eq '192.168.250.70' -and (-not $sepidzPath -or $smartCanon)) {
        Die 'REFUSE Smart/Sepidz contamination: ServerIP 192.168.250.70 outside Sepidz tree (or Smart Claude-Connect path)'
    }
} catch {}
function Warn($m) {
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) { Write-ConnectLog "WARN: $m" 'WARN' }
    Write-Host "  [!] $m" -ForegroundColor DarkYellow
}
function Step($m) {
    $script:currentStepName = $m
    $script:currentStepStartedAt = Get-Date
    $script:StepProgressActive = $false
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "STEP begin: $m"
    }
    if (-not $script:StepConsoleQuiet) {
        Write-Host ("    " + $m).PadRight(46, '.') -NoNewline -ForegroundColor DarkCyan
    }
}
function Update-StepProgress {
    param([string]$Detail)
    if (-not $script:currentStepName) { return }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "STEP progress: $($script:currentStepName) detail=$Detail" 'TRACE'
    }
    if ($script:StepConsoleQuiet) { return }
    $script:StepProgressActive = $true
    $left = ("    " + $script:currentStepName).PadRight(46, '.')
    $line = ($left + " " + $Detail)
    if ($line.Length -lt 78) { $line = $line.PadRight(78) }
    Write-Host ("`r" + $line) -NoNewline -ForegroundColor DarkCyan
}
function StepOk  {
    param([string]$d='')
    $ms = 0
    if ($script:currentStepStartedAt) {
        $ms = [int]((Get-Date) - $script:currentStepStartedAt).TotalMilliseconds
    }
    if ($script:ConnectPerf -and $script:currentStepName) {
        switch -Regex ($script:currentStepName) {
            'Mounting files' { $script:ConnectPerf.MountMs = $ms }
            'Syncing Cursor auth' { $script:ConnectPerf.AuthMs = $ms }
            'Opening' { $script:ConnectPerf.OpenMs = $ms }
        }
    }
    # Print UI result FIRST. Request-ConnectLogSync may inline-sync a multi-MB day log
    # over SSH (40s+) and used to run before Write-Host - so the step looked hung forever.
    # #Quiet-repeat: routine "ok" announcements only show console-side on the first
    # session-loop pass (StepConsoleQuiet=false); every recovery re-pass still logs the
    # full detail to the day log file, it just does not repaint the console with the same
    # "Verifying laptop SSH key...ok / Mounting files...ok / Syncing Cursor auth...ok"
    # burst every time a soft tunnel hiccup silently self-heals. Failures (StepFail) are
    # never gated - those must always be visible.
    if (-not $script:StepConsoleQuiet) {
        if ($script:StepProgressActive) {
            $left = ("    " + $script:currentStepName).PadRight(46, '.')
            $tail = if ($d) { " $d" } else { " ok" }
            Write-Host ("`r" + ($left + $tail).PadRight(78)) -ForegroundColor Green
            $script:StepProgressActive = $false
        } elseif ($d) {
            Write-Host " $d" -ForegroundColor Green
        } else {
            Write-Host " ok" -ForegroundColor Green
        }
    }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        $detail = if ($d) { $d } else { 'ok' }
        Write-ConnectLog "STEP end: $($script:currentStepName) ok ms=$ms detail=$detail"
    }
    # Timer-only drain - never inline sync here (blocks Loading projects -> project menu).
    if (Get-Command Request-ConnectLogSync -ErrorAction SilentlyContinue) { Request-ConnectLogSync -NoInline }
    if (-not $script:StepConsoleQuiet) {
        foreach ($fx in $script:pendingFixes) { Write-Host "      -> fixed: $fx" -ForegroundColor DarkGray }
    }
    $script:pendingFixes = @()
    $script:currentStepStartedAt = $null
}
function StepFail {
    param([string]$d='')
    $ms = 0
    if ($script:currentStepStartedAt) {
        $ms = [int]((Get-Date) - $script:currentStepStartedAt).TotalMilliseconds
    }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        $detail = if ($d) { $d } else { 'failed' }
        Write-ConnectLog "STEP end: $($script:currentStepName) failed ms=$ms detail=$detail" 'ERROR'
        Write-ConnectLog ("FAIL STEP name={0} detail={1}" -f $script:currentStepName, $detail) 'ERROR'
    }
    if ($script:StepProgressActive) {
        $left = ("    " + $script:currentStepName).PadRight(46, '.')
        Write-Host ("`r" + ($left + " failed").PadRight(78)) -ForegroundColor Red
        $script:StepProgressActive = $false
    } else {
        Write-Host " failed" -ForegroundColor Red
    }
    if ($d) { Write-Host "      -> $d" -ForegroundColor DarkGray }
    $script:pendingFixes = @()
    $script:currentStepStartedAt = $null
}
$script:pendingFixes = @()
$script:currentStepName = ''
$script:currentStepStartedAt = $null
$script:StepProgressActive = $false
$script:StepConsoleQuiet = $false

$script:ConnectScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# Shared editor launch (dot-sourced by all Windows connect launchers)
$_editorLaunch = Join-Path $script:ConnectScriptDir 'editor-launch.ps1'
if (Test-Path -LiteralPath (Join-Path $script:ConnectScriptDir 'cursor-proxy-sidecar.ps1')) {
    . (Join-Path $script:ConnectScriptDir 'cursor-proxy-sidecar.ps1')
    # Boot-once: reap an orphaned watchdog left by a crashed/killed prior Connect process
    # (stale lease PID no longer running) before any Ensure-CursorProxySidecar call.
    if (Get-Command Invoke-CursorProxySidecarBootReap -ErrorAction SilentlyContinue) {
        try { [void](Invoke-CursorProxySidecarBootReap) } catch {}
    }
}
if (-not (Test-Path $_editorLaunch)) {
    $_editorLaunch = Join-Path (Split-Path $script:ConnectScriptDir -Parent) 'editor-launch.ps1'
}
if (-not (Test-Path $_editorLaunch)) {
    $_editorLaunch = Join-Path (Split-Path (Split-Path $script:ConnectScriptDir -Parent) -Parent) 'editor-launch.ps1'
}
if (-not (Test-Path $_editorLaunch)) {
    Die "editor-launch.ps1 not found - re-copy the full windows package"
}
. $_editorLaunch
Show-ConnectConsoleIfHidden

$_gitMode = Join-Path $script:ConnectScriptDir 'git-mode.ps1'
if (-not (Test-Path $_gitMode)) {
    $_gitMode = Join-Path (Split-Path $script:ConnectScriptDir -Parent) 'git-mode.ps1'
}
if (-not (Test-Path $_gitMode)) {
    $_gitMode = Join-Path (Split-Path (Split-Path $script:ConnectScriptDir -Parent) -Parent) 'git-mode.ps1'
}
if (-not (Test-Path $_gitMode)) {
    Die "git-mode.ps1 not found - re-copy the full windows package"
}
. $_gitMode
$_cursorAuth = Join-Path $script:ConnectScriptDir 'cursor-auth-laptop.ps1'
if (-not (Test-Path $_cursorAuth)) {
    $_cursorAuth = Join-Path (Split-Path $script:ConnectScriptDir -Parent) 'cursor-auth-laptop.ps1'
}
if (-not (Test-Path $_cursorAuth)) {
    $_cursorAuth = Join-Path (Split-Path (Split-Path $script:ConnectScriptDir -Parent) -Parent) 'cursor-auth-laptop.ps1'
}
if (Test-Path $_cursorAuth) { . $_cursorAuth }

$_windowsMcp = Join-Path $script:ConnectScriptDir 'windows-mcp-laptop.ps1'
if (-not (Test-Path $_windowsMcp)) {
    $_windowsMcp = Join-Path (Split-Path $script:ConnectScriptDir -Parent) 'windows-mcp-laptop.ps1'
}
if (Test-Path $_windowsMcp) { . $_windowsMcp }

$_connectDiag = Dot-SourceSibling 'connect-diagnostic.ps1'
if (-not $_connectDiag) {
    $_connectDiag = Join-Path $script:ConnectScriptDir 'connect-diagnostic.ps1'
    if (-not (Test-Path $_connectDiag)) {
        $_connectDiag = Join-Path (Split-Path $script:ConnectScriptDir -Parent) 'connect-diagnostic.ps1'
    }
}
if (Test-Path $_connectDiag) { . $_connectDiag }
$_connectUi = Dot-SourceSibling 'connect-ui.ps1'
if (-not $_connectUi) { Die 'connect-ui.ps1 not found - re-copy the full windows package' }
. $_connectUi
if (Get-Command Enter-ConnectSingleInstance -ErrorAction SilentlyContinue) {
    if (-not (Enter-ConnectSingleInstance)) {
        # Block before session-start log so blocked launches do not pollute day log.
        Write-Host ''
        Write-Host '  [i] 10 Claude Connect windows already open - close one, then retry.' -ForegroundColor Yellow
        Write-Host ''
        try { Read-Host '    Press Enter to close' | Out-Null } catch { }
        exit 2
    }
}
# Heal/redirect away from dated publish folders (fleet: old dated shortcuts stay broken otherwise).
try {
    if ($env:CLAUDE_CONNECT_SKIP_HEAL -ne '1' -and $script:ConnectScriptDir) {
        $healPs1 = Join-Path $script:ConnectScriptDir 'connect-heal.ps1'
        if (Test-Path -LiteralPath $healPs1) {
            $hp = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $healPs1, '-Here', $script:ConnectScriptDir, '-Quiet'
            ) -Wait -PassThru -WindowStyle Hidden
            if ($hp -and $hp.ExitCode -eq 2) {
                $canon = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
                $marker = Join-Path $env:TEMP 'claude-connect-relaunch.dir'
                if (Test-Path -LiteralPath $marker) {
                    $m = (Get-Content -LiteralPath $marker -TotalCount 1 -ErrorAction SilentlyContinue)
                    if ($m) { $canon = $m.Trim() }
                }
                $bat = Join-Path $canon 'connect.bat'
                if (Test-Path -LiteralPath $bat) {
                    $env:CLAUDE_CONNECT_SKIP_HEAL = '1'
                    Start-Process -FilePath $bat -WorkingDirectory $canon -WindowStyle Normal
                    exit 0
                }
            }
        }
    }
} catch {}

Initialize-ConnectLog -ScriptDir $script:ConnectScriptDir -Version $script:ConnectVersion
if (Get-Command Write-ConnectSessionContext -ErrorAction SilentlyContinue) { Write-ConnectSessionContext -Phase 'startup' }
$script:ConnectPerf = @{
    SshMsTotal = 0
    SshCount   = 0
    MountMs    = 0
    AuthMs     = 0
    OpenMs     = 0
    DiagMs     = 0
}
$script:LaunchPerfFixes = @('F1', 'F2', 'F3', 'F5', 'F4', 'F7')
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Close-ConnectLog }

function Repair-SshPerm([string]$path, [string]$label) {
    if (-not (Test-Path $path)) { return }
    $out = (icacls $path 2>$null) -join ' '
    icacls $path /reset 2>$null | Out-Null
    icacls $path /inheritance:r /grant "$env:USERNAME`:F" 2>$null | Out-Null
    # When elevated as a different admin account, also grant the actual laptop user access
    if ($script:LaptopUser -and $script:LaptopUser -ne $env:USERNAME) {
        icacls $path /grant "$($script:LaptopUser)`:F" 2>$null | Out-Null
    }
    # OpenSSH needs SYSTEM read on authorized_keys; user must keep write for Connect updates.
    if ($path -match 'authorized_keys$') {
        icacls $path /grant "SYSTEM:R" 2>$null | Out-Null
    }
    if ($out -match '\(I\)|Everyone|BUILTIN\\Users') { $script:pendingFixes += "$label permissions" }
}

function Write-AuthorizedKeysFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Lines
    )
    # Ensure we can write BEFORE Set-Content (ACL may be Read-only from a prior repair/sshd).
    Repair-SshPerm $Path 'authorized_keys'
    try {
        Set-Content -Path $Path -Value $Lines -Encoding ASCII -ErrorAction Stop
        return
    } catch {
        Write-ConnectLog "AK_WRITE retry after ACL fix path=$Path err=$($_.Exception.Message)" 'WARN'
    }
    try { takeown /f $Path 2>$null | Out-Null } catch { }
    Repair-SshPerm $Path 'authorized_keys'
    Set-Content -Path $Path -Value $Lines -Encoding ASCII -ErrorAction Stop
}


function Ensure-OpenSshMuxLimits {
    # Multi-agent: default MaxSessions 10 + shared ControlMaster caused cascade blocks.
    # Applied before sshd restart so reverse-tunnel reconnect picks up new limits.
    $cfg = Join-Path $env:ProgramData 'ssh\sshd_config'
    if (-not (Test-Path $cfg)) { return $false }
    $bak = "$cfg.lex-bak"
    if (-not (Test-Path $bak)) { Copy-Item $cfg $bak -Force -ErrorAction SilentlyContinue }
    $c = Get-Content $cfg -Raw -ErrorAction SilentlyContinue
    if ($null -eq $c) { return $false }
    $orig = $c
    if ($c -match '(?m)^#?MaxSessions\s+\d+') {
        $c = [regex]::Replace($c, '(?m)^#?MaxSessions\s+\d+', 'MaxSessions 32')
    } else {
        $c = $c.TrimEnd() + "`r`nMaxSessions 32`r`n"
    }
    if ($c -match '(?m)^#?MaxStartups\s+\S+') {
        $c = [regex]::Replace($c, '(?m)^#?MaxStartups\s+\S+', 'MaxStartups 20:50:100')
    } else {
        $c = $c.TrimEnd() + "`r`nMaxStartups 20:50:100`r`n"
    }
    if ($c -eq $orig) { return $false }
    Set-Content -Path $cfg -Value $c -NoNewline -Encoding ascii -ErrorAction SilentlyContinue
    Write-Host "      -> sshd: MaxSessions=32 MaxStartups=20:50:100" -ForegroundColor DarkGray
    return $true
}

function Install-ServerKey([string]$pub, [bool]$ForceRestart = $false, [switch]$UserOnly) {
    $userFile = Join-Path $SshDir "authorized_keys"

    if ((-not $UserOnly) -and (Test-IsAdmin)) {
        $adminFile = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
        $adminDir = Split-Path $adminFile
        if (Test-Path $adminDir) {
            if (-not (Test-Path $adminFile)) { New-Item -ItemType File -Path $adminFile -Force | Out-Null }
            $_adminOut = (icacls $adminFile 2>$null) -join ' '
            icacls $adminFile /reset 2>$null | Out-Null
            icacls $adminFile /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" 2>$null | Out-Null
            if ($_adminOut -match '\(I\)|Everyone|BUILTIN\\Users') { $script:pendingFixes += "administrators_authorized_keys permissions" }
        }
    }

    $targets = @($userFile)
    if (-not $UserOnly) {
        # Only touch administrators_authorized_keys when elevated (from=loopback enforced below).
        $adminFile = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
        if ((Test-IsAdmin) -and (Test-Path (Split-Path $adminFile))) {
            $targets = @($adminFile) + $targets
        }
    }

    foreach ($akFile in $targets) {
        if (-not (Test-Path (Split-Path $akFile))) { continue }
        if (-not (Test-Path $akFile)) { New-Item -ItemType File -Path $akFile -Force -ErrorAction SilentlyContinue | Out-Null }
        if (-not (Test-Path $akFile)) { continue }
        $lines = @(Get-Content $akFile -ErrorAction SilentlyContinue | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        # SECURITY: always rewrite with from=loopback only. Never broaden to LAN/WAN -
        # the server claude_laptop key must only authenticate reverse-tunnel traffic.
        $restricted = "from=`"127.0.0.1,::1,localhost,::ffff:127.0.0.1`" $pub"
        $lines = @($lines | Where-Object { $_ -notlike "*$pub*" })
        $lines += $restricted
        Write-AuthorizedKeysFile -Path $akFile -Lines $lines
        if ($akFile -eq $userFile) { Repair-SshPerm $akFile "authorized_keys" }
    }

    # Always restart sshd when forced (e.g. after key rejection).
    # administrators_authorized_keys requires a restart on some Windows configurations.
    # On normal first-time setup, only start if stopped (no unnecessary restart).
    $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
    if (-not $UserOnly -and $ForceRestart -and $sshdSvc -and $sshdSvc.Status -eq 'Running') {
        $null = Ensure-OpenSshMuxLimits
        Write-Host "      -> sshd: restarting..." -ForegroundColor DarkGray
        Restart-Service sshd -ErrorAction SilentlyContinue
        # Wait until sshd is actually accepting connections (up to 20s).
        # A fixed 5s sleep races on slower machines and causes immediate retry failure.
        $deadline = (Get-Date).AddSeconds(20)
        $sshdReady = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 1
            $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
            if ($sshdSvc -and $sshdSvc.Status -eq 'Running') {
                try {
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    if ($tcp.BeginConnect('127.0.0.1', 22, $null, $null).AsyncWaitHandle.WaitOne(1000)) {
                        $tcp.Close(); $sshdReady = $true
                        Write-Host "      -> sshd: ready" -ForegroundColor DarkGray
                        break
                    }
                    $tcp.Close()
                } catch {}
            }
        }
        if (-not $sshdReady) {
            Warn "sshd did not become ready within 20s - mount retry may fail"
            $script:pendingFixes += "sshd restart failed - run connect.bat as administrator"
        }
    } elseif (-not $sshdSvc -or $sshdSvc.Status -ne 'Running') {
        Start-Service sshd -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

$script:adminFixAttempted = $false

function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InteractiveLaptopUser {
    if ($script:LaptopUser) { return $script:LaptopUser }
    try {
        $owner = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($owner) {
            $name = ($owner -split '\\')[-1]
            if ($name) { return $name }
        }
    } catch {}
    return $env:USERNAME
}

function Invoke-LaptopAdminOps {
    param(
        [string]$PubB = '',
        [switch]$FirewallFix,
        [switch]$ForceRestart
    )
    if (Test-IsAdmin) {
        if ($PubB) { Install-ServerKey $PubB -ForceRestart:$ForceRestart }
        if ($FirewallFix) {
            $fw = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
            if (-not $fw) {
                New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' `
                    -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any `
                    -ErrorAction SilentlyContinue | Out-Null
            } else {
                Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True -Profile Any -ErrorAction SilentlyContinue
            }
        }
        $script:adminFixAttempted = $true
        return $true
    }
    Write-Host ''
    Write-Host '    Administrator access is required to fix laptop SSH.' -ForegroundColor Yellow
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'LAPTOP_SSH: waiting_admin_prompt' 'WARN'
        Write-ConnectLog 'FAIL NEED_ADMIN: Server laptop key missing from administrators_authorized_keys - prompting user' 'ERROR'
    }
    $yn = (Read-ConnectPrompt '    Allow administrator access? [Y/n]' -Tag 'ADMIN_UAC').Trim()
    Write-ConnectDecision 'admin_access' $yn
    if ($yn -match '^[Nn]') {
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog 'FAIL ADMIN_DENIED: user declined administrator access' 'ERROR'
        }
        return $false
    }
    @(
        "PUB=$PubB",
        "LAPTOP_USER=$($script:LaptopUser)",
        "FIREWALL=$(if ($FirewallFix) { '1' } else { '0' })",
        "FORCE_RESTART=$(if ($ForceRestart) { '1' } else { '0' })"
    ) | Set-Content -Path (Join-Path $CfgDir 'adminfix.pending') -Encoding ASCII
    $elevArgs = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-AdminFix')
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'LAPTOP_SSH: waiting_uac' 'WARN'
    }
    $proc = Start-Process powershell.exe -Verb RunAs -ArgumentList $elevArgs -Wait -PassThru
    $script:adminFixAttempted = $true
    $ec = if ($null -eq $proc) { -1 } else { [int]$proc.ExitCode }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        if ($ec -eq 0) {
            Write-ConnectLog 'LAPTOP_SSH: admin_fix_ok' 'INFO'
        } else {
            Write-ConnectLog ("FAIL ADMIN_UAC: elevated fix exit={0} (user cancelled UAC or fix failed)" -f $ec) 'ERROR'
        }
    }
    return ($ec -eq 0)
}

function Test-AuthorizedKeyFragment {
    param(
        [string]$Path,
        [string]$PubFragment
    )
    # Returns: $true / $false / $null (= unreadable; do NOT treat as missing).
    if (-not $PubFragment -or -not (Test-Path $Path)) { return $false }
    try {
        $raw = Get-Content -LiteralPath $Path -ErrorAction Stop
        $pattern = [regex]::Escape($PubFragment)
        return [bool]($raw | Where-Object { $_ -match $pattern })
    } catch {
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("LAPTOP_SSH: cannot_read_ak path=$Path err=$($_.Exception.Message)") 'WARN'
        }
        return $null
    }
}

function Test-WindowsAccountIsLocalAdmin {
    param([string]$UserName = $script:LaptopUser)
    if (-not $UserName) { return $false }
    try {
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'
        $groupLabel = ($adminSid.Translate([System.Security.Principal.NTAccount]).Value -split '\\')[-1]
        $members = (& net localgroup $groupLabel 2>$null | Out-String)
        if ($LASTEXITCODE -ne 0) {
            $members = (& net localgroup Administrators 2>$null | Out-String)
        }
        return [bool]($members -match "(?m)^\s*$([regex]::Escape($UserName))\s*$")
    } catch {
        return $false
    }
}

function Test-LaptopSshReady {
    param([string]$PubFragment = '')
    $reasons = [System.Collections.Generic.List[string]]::new()
    $svc = Get-Service sshd -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne 'Running') { $reasons.Add('OpenSSH Server (sshd) is not running') }
    try {
        $fw = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction Stop
        if ($fw.Enabled.ToString() -ne 'True') { $reasons.Add('SSH firewall rule disabled') }
    } catch {
        if (-not (Test-IsAdmin)) { $reasons.Add('Cannot verify SSH firewall rule (need administrator)') }
    }
    if ($PubFragment) {
        $userAk = Join-Path $SshDir 'authorized_keys'
        $adminAk = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
        $adminDir = Split-Path $adminAk
        $userIsAdmin = Test-WindowsAccountIsLocalAdmin
        if ($userIsAdmin -and (Test-Path $adminDir)) {
            # Unelevated admin users cannot read administrators_authorized_keys (ACL=SYSTEM+Administrators).
            # Access-denied must NOT be treated as "key missing" or we infinite-prompt UAC.
            $akHit = Test-AuthorizedKeyFragment -Path $adminAk -PubFragment $PubFragment
            if ($null -eq $akHit) {
                if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                    Write-ConnectLog 'LAPTOP_SSH: admin_ak unreadable unelevated - skip membership check (key may already be installed)' 'WARN'
                }
            } elseif (-not $akHit) {
                $reasons.Add('Server laptop key not in administrators_authorized_keys (Windows admin user)')
            }
        } else {
            $akHit = Test-AuthorizedKeyFragment -Path $userAk -PubFragment $PubFragment
            if ($null -eq $akHit) {
                if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                    Write-ConnectLog 'LAPTOP_SSH: user authorized_keys unreadable' 'WARN'
                }
            } elseif (-not $akHit) {
                $reasons.Add('Server laptop key not in authorized_keys')
            }
        }
    }
    return [PSCustomObject]@{ Ready = ($reasons.Count -eq 0); Reasons = @($reasons) }
}

function Ensure-LaptopSshReady {
    param([string]$PubB = '')
    $frag = if ($PubB) { ($PubB -split '\s+')[1] } else { '' }
    $check = Test-LaptopSshReady -PubFragment $frag
    if ($check.Ready) { return $true }
    Write-Host ''
    foreach ($r in $check.Reasons) { Warn $r }
    return (Invoke-LaptopAdminOps -PubB $PubB -FirewallFix -ForceRestart)
}

if ($script:RunAdminFix) {
    $_cfg = Join-Path $env:USERPROFILE '.config\claude-connect\connect.conf'
    if (Test-Path $_cfg) {
        $conf = @{}; Get-Content $_cfg | ForEach-Object { if ($_ -match '^(.+?)=(.*)$') { $conf[$matches[1]] = $matches[2] } }
        if ($conf.LAPTOP_USER -and (Test-Path "C:\Users\$($conf.LAPTOP_USER)")) {
            $CfgDir = Join-Path "C:\Users\$($conf.LAPTOP_USER)" '.config\claude-connect'
        }
    }
    $fixFile = Join-Path $CfgDir 'adminfix.pending'
    if (-not (Test-Path $fixFile)) {
        try {
            $d = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            $f = Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
            $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
            $sid = if ($env:CLAUDE_CONNECT_RUN_ID) { $env:CLAUDE_CONNECT_RUN_ID } else { '-' }
            [IO.File]::AppendAllText($f, "[$ts] [ERROR] [$sid] FAIL ADMIN_FIX: No admin fix pending`n", [Text.UTF8Encoding]::new($false))
        } catch { }
        Write-Host '[X] No admin fix pending' -ForegroundColor Red
        exit 1
    }
    $fixLines = @{}; Get-Content $fixFile | ForEach-Object { if ($_ -match '^(.+?)=(.*)$') { $fixLines[$matches[1]] = $matches[2] } }
    Remove-Item $fixFile -Force -ErrorAction SilentlyContinue
    if ($fixLines.LAPTOP_USER) {
        $script:LaptopUser = $fixLines.LAPTOP_USER
        $SshDir = Join-Path "C:\Users\$($fixLines.LAPTOP_USER)" '.ssh'
        $CfgDir = Join-Path "C:\Users\$($fixLines.LAPTOP_USER)" '.config\claude-connect'
    }
    $pub = $fixLines.PUB
    if ($pub) { Install-ServerKey $pub -ForceRestart:($fixLines.FORCE_RESTART -eq '1') }
    if ($fixLines.FIREWALL -eq '1') {
        $fw = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
        if (-not $fw) {
            New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' `
                -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any `
                -ErrorAction SilentlyContinue | Out-Null
        } else {
            Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True -Profile Any -ErrorAction SilentlyContinue
        }
    }
    exit 0
}

function ConvertTo-ProcessArg([string]$Arg) {
    # Minimal CreateProcess-compatible quoting for ProcessStartInfo.Arguments: our args
    # are plain file paths / user@host:path strings with no embedded quotes or trailing
    # backslashes, so a straightforward "wrap if it has a space" is sufficient here.
    if ($Arg -match '[\s"]') { return '"' + ($Arg -replace '"', '\"') + '"' }
    return $Arg
}

function Start-ScpPushJob {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$RemoteDest
    )
    # ROOT CAUSE (confirmed via isolated repro, not guessed): Start-Process -PassThru
    # (without -Wait) reliably returns a Process object whose .ExitCode is $null on
    # this PowerShell/Windows build - verified with cmd.exe, native OpenSSH scp.exe,
    # and Git-for-Windows scp.exe alike, redirect or no redirect, 100% of iterations.
    # $job.Proc was NEVER null (the earlier null-Proc guard correctly never fired);
    # the null was in .ExitCode. Since "$null -ne 0" is $true in PowerShell, every
    # push - success or failure - fell into the "failed" branch, which then read the
    # stderr capture file via (Get-Content -Raw).Trim(); Get-Content -Raw returns
    # $null (not "") for a 0-byte file, and a silent successful scp writes 0 bytes of
    # stderr, so .Trim() crashed with "cannot call a method on a null-valued
    # expression" on essentially every successful, silent push. Fix: bypass
    # Start-Process entirely for this call and drive System.Diagnostics.Process /
    # ProcessStartInfo directly, which reports ExitCode correctly (confirmed over
    # repeated real pushes to the server, including paths containing spaces).
    $argsArray = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=30', '-q', $LocalPath, $RemoteDest)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'scp'
    $psi.Arguments = ($argsArray | ForEach-Object { ConvertTo-ProcessArg $_ }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardError = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    # Read stderr asynchronously (Task) so a large/slow stream can never deadlock the
    # child waiting on a full pipe buffer - not a concern for these tiny scripts, but
    # ReadToEndAsync costs nothing and removes any doubt.
    $errTask = $proc.StandardError.ReadToEndAsync()
    return @{ Name = $Name; Proc = $proc; ErrTask = $errTask }
}


function Get-SshConfigUserForServer {
    param([string]$Ip, [string]$FallbackUser)
    # Prefer developer REMOTE_USER first - IP defaults only when unset.
    if ($FallbackUser) { return $FallbackUser }
    if ($Ip -eq '192.168.250.70') { return 'sepidz' }
    if ($Ip -eq '192.168.210.240') { return 'smart' }
    return 'smart'
}

function Initialize-ServerSession {
    param(
        [Parameter(Mandatory)][string]$ConnectScriptDir,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$SshCfgPath
    )
    # Bug 12 fix (2026-07-24, live evidence: "Server setup" step alone took 50s across 8
    # sequential one-shot ssh calls): the mount/git hash-check call (below, formerly issued
    # AFTER Acquire-TunnelPort) has zero data dependency on the tunnel port - it only reads two
    # sha256sums to decide whether claude-mount.sh/claude-git-setup.sh need re-pushing. Folded
    # into this same initial round trip (which Acquire-TunnelPort's $uidStr parse must already
    # wait for) removes one full ~5-7s ssh handshake from the step, with no ordering change in
    # what any later code observes.
    if (Get-Command Update-StepProgress -ErrorAction SilentlyContinue) { Update-StepProgress 'key' }
    $initOut = (SshX "id -u && (test -f ~/.ssh/claude_laptop || ssh-keygen -t ed25519 -N '' -f ~/.ssh/claude_laptop -q) && cat ~/.ssh/claude_laptop.pub && mkdir -p ~/.local/bin && echo MOUNT_HASH:`$(sha256sum ~/.local/bin/claude-mount 2>/dev/null | awk '{print `$1}') && echo GIT_HASH:`$(sha256sum ~/.local/bin/claude-git-setup 2>/dev/null | awk '{print `$1}')") -join "`n"
    $lines = ($initOut -replace "`r",'') -split "`n" | Where-Object { $_.Trim() -ne '' }
    $uidStr = [string]($lines | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1) -replace '\D',''
    $pubB = ([string](($lines | Where-Object { $_ -match '^ssh-' } | Select-Object -First 1) + '')).Trim()
    $remoteHash = (($lines | Where-Object { $_ -match '^MOUNT_HASH:' } | Select-Object -First 1) -replace '^MOUNT_HASH:', '').Trim()
    $gitRemote = (($lines | Where-Object { $_ -match '^GIT_HASH:' } | Select-Object -First 1) -replace '^GIT_HASH:', '').Trim()
    # P0-S4: seed verified hash from Server setup MOUNT_HASH so
    # Prepare-ServerSessionParallel can skip the sha256sum SshX round trip when
    # local claude-mount already matches (ClaudeMountSyncVerifiedHash -eq localHash).
    if ($remoteHash) {
        $script:ClaudeMountSyncVerifiedHash = $remoteHash
    }
    $script:ServerUidStr = $uidStr
    if (Get-Command Update-StepProgress -ErrorAction SilentlyContinue) { Update-StepProgress 'port' }
    if (-not (Acquire-TunnelPort -UidStr $uidStr)) {
        $base = [int](Get-TunnelPortUserBase -UidStr $uidStr)
        # Port 20000 is reserved (guard: 20000 < PORT). UID 1000 base is 20000 -
        # fall back to slot 1 (20001) instead of invalid slot 0.
        if ($base -le 20000) {
            $script:Port = 20001
            $script:TunnelSlot = 1
        } else {
            $script:Port = $base
            $script:TunnelSlot = 0
        }
    }
    if ($script:Port -le 20000 -or $script:Port -gt 65535) {
        return @{ Ok = $false; Error = "invalid tunnel port $($script:Port) for UID $uidStr"; PubB = '' }
    }
    if (-not $pubB) {
        return @{ Ok = $false; Error = 'could not read server key'; PubB = '' }
    }

    # Non-atomic overwrite hazard: claude-mount/claude-git-setup are live-executed
    # (claude-watchdog polls claude-mount every 30s server-side). scp writes the
    # destination in place, so a concurrent exec can read a torn file mid-transfer.
    # Push to a .new sibling and mv it into place atomically once fully written.
    $scpJobs = @()
    $dir = Resolve-ServerScriptDir -ConnectScriptDir $ConnectScriptDir
    if ($dir) {
        $mountSrc = [System.IO.Path]::Combine($dir, 'claude-mount.sh')
        $gitSrc = [System.IO.Path]::Combine($dir, 'claude-git-setup.sh')
        $hasMountSrc = Test-Path $mountSrc
        $hasGitSrc = Test-Path $gitSrc
        # Bug 12 fix: $remoteHash/$gitRemote are now fetched above, folded into the initial
        # id-u/keygen/pubkey round trip (no data dependency on the tunnel port acquired in
        # between) - no separate SshX call needed here any more.
        if ($hasMountSrc) {
            $uploadSrc = Get-LfNormalizedShCopy -Src $mountSrc
            $localHash = (Get-FileHash -Algorithm SHA256 -Path $uploadSrc).Hash
            if (-not ($localHash -and $remoteHash -and ($localHash.ToLower() -eq $remoteHash.ToLower()))) {
                $scpJobs += Start-ScpPushJob -Name 'claude-mount' -LocalPath $uploadSrc -RemoteDest "${Alias}:~/.local/bin/claude-mount.new"
            } elseif ($localHash) {
                $script:ClaudeMountSyncVerifiedHash = $localHash
            }
        }
        if ($hasGitSrc) {
            $gitLocal = (Get-FileHash -Algorithm SHA256 -Path $gitSrc).Hash
            if (-not ($gitLocal -and $gitRemote -and ($gitLocal.ToLower() -eq $gitRemote.ToLower()))) {
                $scpJobs += Start-ScpPushJob -Name 'claude-git-setup' -LocalPath $gitSrc -RemoteDest "${Alias}:~/.local/bin/claude-git-setup.new"
            }
        }
    }

    if (Get-Command Update-StepProgress -ErrorAction SilentlyContinue) { Update-StepProgress 'laptop ssh' }
    Install-ServerKey $pubB
    if (-not (Ensure-LaptopSshReady -PubB $pubB)) {
        return @{ Ok = $false; Error = 'laptop SSH key setup failed'; PubB = $pubB }
    }

    if (Get-Command Update-StepProgress -ErrorAction SilentlyContinue) { Update-StepProgress 'ssh config' }
    Remove-SshHostBlock $SshCfgPath $Alias
    $sshCfgUser = Get-SshConfigUserForServer -Ip $ServerIP -FallbackUser $RemoteUser
    @"

Host $Alias
    HostName $ServerIP
    User $sshCfgUser
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
"@ | Add-Content -Path $SshCfgPath -Encoding ASCII
    Sanitize-SshAliasConfig -CfgPath $SshCfgPath -AliasName $Alias
    Repair-SshPerm $SshCfgPath "SSH config"
    if (Get-Command Update-StepProgress -ErrorAction SilentlyContinue) { Update-StepProgress 'conf' }
    Push-ServerConnectConf

    $pushOk = $true
    $pushedOk = @{}
    if ($scpJobs.Count -gt 0 -and (Get-Command Update-StepProgress -ErrorAction SilentlyContinue)) {
        Update-StepProgress 'scripts'
    }
    foreach ($job in $scpJobs) {
        try {
            # $job.Proc comes from Start-ScpPushJob (raw System.Diagnostics.Process), not
            # Start-Process, so .ExitCode is reliable here - see Start-ScpPushJob for why
            # that distinction matters (it's the actual root cause of the historical
            # "cannot call a method on a null-valued expression" crash on this loop).
            if ($null -eq $job.Proc) {
                throw "scp process object missing for $($job.Name)"
            }
            $job.Proc.WaitForExit()
            if ($job.Proc.ExitCode -ne 0) {
                $pushOk = $false
                $script:pendingFixes += 'server script push failed'
                $errText = '(no stderr captured)'
                try {
                    if ($job.ErrTask -and $job.ErrTask.Wait(2000) -and $job.ErrTask.Result) {
                        $t = $job.ErrTask.Result.Trim()
                        if ($t) { $errText = $t }
                    }
                } catch { }
                if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                    Write-ConnectLog "SCP_FAIL: name=$($job.Name) exit=$($job.Proc.ExitCode) stderr=$errText" 'ERROR'
                }
            } else {
                $pushedOk[$job.Name] = $true
                if ($job.Name -eq 'claude-mount' -and $localHash) {
                    $script:ClaudeMountSyncVerifiedHash = $localHash
                }
            }
        } catch {
            $pushOk = $false
            $script:pendingFixes += 'server script push failed'
            if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                Write-ConnectLog "SCP_EXCEPTION: name=$($job.Name) error=$($_.Exception.Message)" 'ERROR'
            }
        }
    }
    if ($dir -and $scpJobs.Count -gt 0) {
        # Finalize each .new file in place (sed/chmod), then atomically rename onto
        # the live path as the very last step - the live path is never half-written.
        $chmodCmd = @()
        if ($pushedOk.ContainsKey('claude-mount')) {
            $chmodCmd += "sed -i 's/\r$//' ~/.local/bin/claude-mount.new 2>/dev/null; chmod +x ~/.local/bin/claude-mount.new && mv -f ~/.local/bin/claude-mount.new ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=`$HOME/.local/bin:`$PATH\n' >> ~/.bashrc"
        }
        if ($pushedOk.ContainsKey('claude-git-setup')) {
            $chmodCmd += "sed -i 's/\r$//' ~/.local/bin/claude-git-setup.new 2>/dev/null; chmod +x ~/.local/bin/claude-git-setup.new && mv -f ~/.local/bin/claude-git-setup.new ~/.local/bin/claude-git-setup"
        }
        if ($chmodCmd.Count -gt 0) { SshX ($chmodCmd -join '; ') 2>$null | Out-Null }
    }

    # Script push failure is non-fatal (same as Mac v20260717.6+); port/key already OK.
    return @{ Ok = $true; PubB = $pubB; Error = ''; PushOk = $pushOk }
}

function Add-SshRecentLog([string]$Line) {
    if (-not $script:SshRecentLog) {
        $script:SshRecentLog = [System.Collections.Generic.List[string]]::new()
    }
    $script:SshRecentLog.Add($Line)
    while ($script:SshRecentLog.Count -gt 24) { $script:SshRecentLog.RemoveAt(0) }
}

function Invoke-SshXCore {
    param(
        [Parameter(Mandatory)][string]$RemoteCmd,
        [switch]$ApplyTimeout
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # No ControlMaster on Windows OpenSSH here: ControlPath/named-pipe mux fails with
    # "getsockname failed: Not a socket" and/or hangs on `ssh -MNf` (verified 2026-07-20).
    # Speedups stay in batched remote cmds (auth probe, laptop SSH probe, skip redundant greps).
    # Base64-encode: passing $RemoteCmd (often full of embedded double quotes) as a bare
    # native-exe argument to ssh.exe has intermittently corrupted the quoting in production
    # ("bash: -c: unexpected EOF while looking for matching `""), which then cascades into
    # killing what looks like an orphaned tunnel and failing the server-script push. A
    # base64 blob has no shell-special characters, so it can never be mangled in transit.
    # Run decoded bytes via stdin to bash (optionally wrapped in timeout 45) - never nest
    # bash -lc '...' single-quoted strings inside the payload (breaks on embedded quotes).
    # Bash remote payloads must be LF-only: Windows CRLF in here-docs/for-loops breaks `bash -c`.
    $RemoteCmd = $RemoteCmd -replace "`r`n", "`n" -replace "`r", "`n"
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($RemoteCmd))
    $runner = if ($ApplyTimeout) { 'timeout 45 bash' } else { 'bash' }
    $wrapped = "echo $b64|base64 -d|$runner"
    $sshArgs = @('-n', '-o', 'ClearAllForwardings=yes', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=30', '-o', 'ServerAliveInterval=10', '-o', 'ServerAliveCountMax=3')
    if ($script:ConnectSshExtraOptions -and $script:ConnectSshExtraOptions.Count -gt 0) { $sshArgs += $script:ConnectSshExtraOptions }
    # #P3: ServerAliveInterval/CountMax only detect a dead *transport*; a hung remote
    # pty/session negotiation (or a black-holed link that still ACKs keepalives) can
    # block the local ssh.exe forever even though the remote timeout wrapper should
    # have fired (observed: probe processes still alive 6+ hours later). Hard-cap the
    # client process itself so a single call can never outlive this function.
    if (-not $script:SshXCoreHardKillMs) { $script:SshXCoreHardKillMs = 75000 }
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    $exitCode = 124
    $outText = ''
    try {
        $fullArgs = @($sshArgs) + @($Alias, $wrapped)
        $proc = Start-Process -FilePath 'ssh' -ArgumentList $fullArgs -NoNewWindow -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        # Touch .Handle before WaitForExit: PowerShell 5.1's Start-Process -PassThru object
        # otherwise leaves .ExitCode null after exit (documented .NET Process quirk) unless a
        # full-access handle was retained early.
        if ($proc) { $null = $proc.Handle }
        if ($proc.WaitForExit([int]$script:SshXCoreHardKillMs)) {
            $exitCode = $proc.ExitCode
        } else {
            if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                Write-ConnectLog "SSH_HARD_KILL ms=$($script:SshXCoreHardKillMs) reason=client_wall_clock_cap pid=$($proc.Id)" 'ERROR'
            }
            try { $proc.Kill() } catch {}
            $exitCode = 124
        }
        $stdoutText = ''
        $stderrText = ''
        try { $stdoutText = [System.IO.File]::ReadAllText($stdoutPath) } catch {}
        try { $stderrText = [System.IO.File]::ReadAllText($stderrPath) } catch {}
        $outText = $stdoutText + $stderrText
    } catch {
        $exitCode = 124
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog "SSH_SPAWN_FAIL err=$($_.Exception.Message)" 'ERROR'
        }
    } finally {
        try { Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue } catch {}
    }
    $sw.Stop()
    $lines = @()
    if ($outText) { $lines = @($outText -split "`r?`n") }
    return [PSCustomObject]@{
        Exit = $exitCode
        Ms   = [int]$sw.ElapsedMilliseconds
        Out  = ($lines -join "`n")
        Lines = $lines
    }
}

function SshX([string]$Cmd, [switch]$NoRetryOnTimeout) {
    $origCmd = $Cmd
    $applyTimeout = $origCmd -notmatch '^\s*timeout\s'
    $remoteCmd = $origCmd
    $truncCmd = if ($origCmd.Length -gt 200) { $origCmd.Substring(0, 200) + '...' } else { $origCmd }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "SSH_BEGIN cmd=$truncCmd"
    }
    $result = Invoke-SshXCore -RemoteCmd $remoteCmd -ApplyTimeout:$applyTimeout
    if ($result.Exit -eq 124 -and -not $NoRetryOnTimeout) {
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog "SSH_TIMEOUT exit=124 cmd=$truncCmd - retrying once" 'ERROR'
        }
        $result = Invoke-SshXCore -RemoteCmd $remoteCmd -ApplyTimeout:$applyTimeout
    }
    $truncOut = ($result.Out.Trim() -replace '\s+', ' ')
    if ($truncOut.Length -gt 300) { $truncOut = $truncOut.Substring(0, 300) + '...' }
    if (-not $truncOut) { $truncOut = '(empty)' }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        $sshLevel = 'INFO'
        if ($result.Exit -eq 124) { $sshLevel = 'ERROR' }
        elseif ($result.Exit -ne 0) {
            # #18: expected pre-mount check noise must not WARN the day log.
            if ($truncOut -match '(?i)\bneed_mount\b' -and $truncOut -notmatch '(?i)Permission denied|Connection refused|Could not resolve|No route to host|Connection timed out|error:') {
                $sshLevel = 'TRACE'
            } else {
                $sshLevel = 'WARN'
            }
        }
        Write-ConnectLog "SSH_END exit=$($result.Exit) ms=$($result.Ms) out=$truncOut" $sshLevel
        if ($truncOut -match 'unexpected EOF while looking for matching') {
            Write-ConnectLog ("FAIL SSH_QUOTE: exit={0} cmd={1} out={2}" -f $result.Exit, $truncCmd, $truncOut) 'ERROR'
        } elseif ($result.Exit -ne 0 -and $result.Exit -ne 124 -and $truncOut -match '(?i)Permission denied|Connection refused|Could not resolve|No route to host|Connection timed out') {
            Write-ConnectLog ("FAIL SSH_END: exit={0} cmd={1}" -f $result.Exit, $truncCmd) 'ERROR'
        }
    }
    if ($script:ConnectPerf) {
        $script:ConnectPerf.SshMsTotal += $result.Ms
        $script:ConnectPerf.SshCount++
    }
    Add-SshRecentLog "exit=$($result.Exit) ms=$($result.Ms) cmd=$truncCmd"
    if ($result.Exit -ne 0 -and $result.Exit -ne 124) {
        $script:LastSshExit = $result.Exit
    }
    $global:LASTEXITCODE = $result.Exit
    return $result.Lines
}

function Start-MountProjectBackground {
    # User request (2026-07-24): "Mounting files" only matters for Cursor's remote file-tree
    # UI (SSHFS mounts the laptop disk onto the server) - agent work goes through laptop-exec /
    # SSH-first per CLAUDE.md, never through this mount, so nothing actually needs to wait on
    # it. Cold mounts measured 13-25s in real sessions; kicking it off detached and moving
    # straight to "Opening Cursor" removes that whole wait from the visible critical path.
    # Deliberately minimal (own plain `ssh` call, not the full Invoke-MountProject/SshX chain)
    # matching the established Start-WindowsMcpEnsureBackground pattern - a detached child
    # process cannot safely reuse this script's own top-level state.
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$LogDir,
        [Parameter(Mandatory)][string]$SessionId
    )
    $runnerDir = Join-Path $env:TEMP 'claude-connect-mountbg'
    if (-not (Test-Path -LiteralPath $runnerDir)) { New-Item -ItemType Directory -Force -Path $runnerDir | Out-Null }
    $runnerPath = Join-Path $runnerDir ("mount-bg-{0}.ps1" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    $runner = @'
param(
    [Parameter(Mandatory)][string]$ProjectId,
    [Parameter(Mandatory)][string]$Alias,
    [Parameter(Mandatory)][string]$LogDir,
    [Parameter(Mandatory)][string]$SessionId
)
$ErrorActionPreference = 'Continue'
function Write-MountBgLog([string]$Msg, [string]$Level = 'INFO') {
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
    $day = Join-Path $LogDir ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = "[$ts] [$Level] [$SessionId] $Msg"
    $dayTag = if ($day -match 'connect-(\d{8})\.log$') { $Matches[1] } else { Get-Date -Format 'yyyyMMdd' }
    $mutexName = "Global\ClaudeConnectDayLogWrite-$dayTag"
    $mutex = $null
    $got = $false
    try {
        $mutex = New-Object System.Threading.Mutex($false, $mutexName)
        $got = $mutex.WaitOne(5000)
        $fs = [System.IO.FileStream]::new($day, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        try {
            $null = $fs.Seek(0, [System.IO.SeekOrigin]::End)
            $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($line + "`r`n")
            $fs.Write($bytes, 0, $bytes.Length)
        } finally { $fs.Dispose() }
    } catch {
        try { Add-Content -LiteralPath ($day + '.mount-bg') -Value $line -Encoding UTF8 } catch { }
    } finally {
        if ($mutex) {
            if ($got) { try { $mutex.ReleaseMutex() } catch { } }
            try { $mutex.Dispose() } catch { }
        }
    }
}
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Write-MountBgLog "MOUNT_BG_BEGIN project=$ProjectId"
try {
    $mountCmd = "CLAUDE_TRUSTED_TUNNEL=1 CLAUDE_TUNNEL_BANNER_OK=1 `$HOME/.local/bin/claude-mount up '$ProjectId' 2>&1"
    $out = & ssh -n -o BatchMode=yes -o ConnectTimeout=15 $Alias $mountCmd 2>&1
    $ec = $LASTEXITCODE
    $sw.Stop()
    $outJoined = (($out -join ' ') -replace '\s+', ' ').Trim()
    if ($ec -eq 0) {
        Write-MountBgLog ("MOUNT_BG_OK project=$ProjectId ms={0} out={1}" -f $sw.ElapsedMilliseconds, $outJoined)
    } else {
        Write-MountBgLog ("MOUNT_BG_FAIL project=$ProjectId exit=$ec ms={0} out={1} - press O to reopen editor after fixing, or R to reconnect" -f $sw.ElapsedMilliseconds, $outJoined) 'WARN'
    }
} catch {
    Write-MountBgLog ("MOUNT_BG_EXCEPTION project=$ProjectId error=$($_.Exception.Message)") 'WARN'
}
'@
    Set-Content -LiteralPath $runnerPath -Value $runner -Encoding UTF8
    try {
        $argList = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
            '-File', $runnerPath,
            '-ProjectId', $ProjectId, '-Alias', $Alias, '-LogDir', $LogDir, '-SessionId', $SessionId
        )
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden -PassThru -ErrorAction Stop
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog "MOUNT_BG_STARTED project=$ProjectId pid=$($p.Id)" 'INFO'
        }
        return $true
    } catch {
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog "MOUNT_BG_START_FAILED project=$ProjectId error=$($_.Exception.Message)" 'WARN'
        }
        return $false
    }
}

function Begin-ConnectRecovery {
    param(
        [Parameter(Mandatory)][ValidateSet('manual', 'auto')][string]$Trigger,
        [Parameter(Mandatory)][string]$ProjectId,
        [bool]$EditorWasOpen
    )
    $script:RecoveryGeneration++
    $script:RecoveryStartedAt = Get-Date
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "RECOVERY_BEGIN trigger=$Trigger project=$ProjectId editor_opened=$EditorWasOpen gen=$($script:RecoveryGeneration)"
    }
    $script:ForceCursorAuthSync = $true
    $script:PostTunnelRecovery = $true
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'RECOVERY_STATE_RESET editor_opened=False force_auth=True post_recovery=True'
    }
}

function Complete-PostTunnelRecovery {
    param(
        [bool]$MountOk,
        [string]$AuthDetail = '',
        [string]$ProjectId = '',
        [string]$RemotePath = '',
        [string]$EditorCmd = '',
        [string]$EditorName = '',
        [bool]$OnFolder = $false,
        [bool]$DidLaunch = $false
    )
    if (-not $script:PostTunnelRecovery) { return }
    $elapsed = 0
    if ($script:RecoveryStartedAt) {
        $elapsed = [int]((Get-Date) - $script:RecoveryStartedAt).TotalMilliseconds
    }
    # Re-probe live mount before terminal recovery-end log (claimed MountOk can race SSHFS down).
    if ($MountOk -and $ProjectId -and (Get-Command Test-ProjectMountHealthy -ErrorAction SilentlyContinue)) {
        $liveMount = $false
        try { $liveMount = [bool](Test-ProjectMountHealthy -ProjectId $ProjectId) } catch { $liveMount = $false }
        if (-not $liveMount) { $MountOk = $false }
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog "RECOVERY_MOUNTOK_REASSERT live=$liveMount mount_ok=$MountOk project=$ProjectId" 'INFO'
        }
    } elseif ($MountOk -and (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue)) {
        Write-ConnectLog "RECOVERY_MOUNTOK_REASSERT live=unknown mount_ok=$MountOk project=$ProjectId" 'DEBUG'
    }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "RECOVERY_END elapsed_ms=$elapsed mount_ok=$MountOk gen=$($script:RecoveryGeneration) auth=$AuthDetail"
    }
    if ($MountOk -and (Get-Command Test-TunnelUp -ErrorAction SilentlyContinue) -and (Test-TunnelUp)) {
        if (Get-Command Invoke-ConnectSilentUpdateCheck -ErrorAction SilentlyContinue) {
            Write-ConnectLog 'UPDATE_SILENT phase=post_tunnel_recovery' 'DEBUG'
            Invoke-ConnectSilentUpdateCheck
        }
    }
    if (Get-Command Write-ConnectDiagnosticReport -ErrorAction SilentlyContinue) {
        $authOk = ($AuthDetail -match 'ok|already|skipped' -and $AuthDetail -notmatch 'fail|incomplete|missing')
        $null = Write-ConnectDiagnosticReport -Phase 'RECOVERY' `
            -EditorCmd $EditorCmd -EditorName $EditorName -Alias $Alias `
            -ProjectId $ProjectId -RemotePath $RemotePath `
            -TunnelUp (Test-TunnelUp) -MountOk $MountOk -OnFolder $OnFolder `
            -DidLaunch $DidLaunch -AuthOk $authOk -AuthDetail $AuthDetail `
            -ServerIP $ServerIP -Port $Port `
            -SshRecent @($script:SshRecentLog)
    }
    $script:PostTunnelRecovery = $false
    $script:RecoveryStartedAt = $null
}

function Write-SessionDiagnosticReport {
    param(
        [Parameter(Mandatory)][string]$Phase,
        [bool]$MountOk = $true,
        [string]$MountOut = '',
        [bool]$OnFolder = $false,
        [bool]$DidLaunch = $false,
        [bool]$AuthOk = $true,
        [string]$AuthDetail = '',
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$EditorCmd,
        [Parameter(Mandatory)][string]$EditorName
    )
    if (-not (Get-Command Write-ConnectDiagnosticReport -ErrorAction SilentlyContinue)) { return $null }
    $agentHome = $false
    $windowOpen = $false
    # Happy-path SESSION_OPEN (folder open + mount ok + auth not broken): the verdict returns
    # CURSOR_ON_FOLDER_OK before AgentHome/WindowOpen are ever consulted, so skip these two
    # process-scan probes - they were adding avoidable work right after the window already opened.
    # AuthOk=$false is the NORMAL steady state (auth-sync skipped when stamp current), so gate on
    # "auth not genuinely failed" - otherwise the light path never fires on a happy reconnect.
    $authFine = ($AuthOk -ne $false) -or ($AuthDetail -match 'skip')
    $lightOpen = ($Phase -eq 'SESSION_OPEN' -and $OnFolder -and $MountOk -and $authFine)
    if ($EditorCmd -eq 'cursor' -and -not $lightOpen) {
        if (Get-Command Test-RemoteEditorInAgentHome -ErrorAction SilentlyContinue) {
            $agentHome = Test-RemoteEditorInAgentHome
        }
        if (Get-Command Test-RemoteEditorWindowOpen -ErrorAction SilentlyContinue) {
            $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
        }
    }
    return Write-ConnectDiagnosticReport -Phase $Phase `
        -EditorCmd $EditorCmd -EditorName $EditorName -Alias $Alias `
        -ProjectId $ProjectId -RemotePath $RemotePath `
        -TunnelUp (Test-TunnelUp) -MountOk $MountOk -MountOut $MountOut `
        -OnFolder $OnFolder -AgentHome $agentHome -WindowOpen $windowOpen `
        -DidLaunch $DidLaunch -AuthOk $AuthOk -AuthDetail $AuthDetail `
        -ServerIP $ServerIP -Port $Port `
        -SshRecent @($script:SshRecentLog)
}

function PortOpen($ip, $port) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ok  = $tcp.BeginConnect($ip, $port, $null, $null).AsyncWaitHandle.WaitOne(3000)
        $tcp.Close()
        return $ok
    } catch { return $false }
}

function Remove-SshHostBlock($cfgPath, $alias) {
    if (-not (Test-Path $cfgPath)) { return }
    $out  = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($ln in (Get-Content $cfgPath)) {
        if ($ln -match '^\s*Host\s+(.+)$') { $skip = (($matches[1].Trim() -split '\s+') -contains $alias) }
        if (-not $skip) { $out.Add($ln) }
    }
    Set-Content -Path $cfgPath -Value $out -Encoding ASCII
}

function Get-Mounts {
    # Perf: these 3 checks (active mount id, live mount dirs, mount catalog) used to be 3
    # separate SshX round trips (~1.4s each of pure SSH handshake overhead on Windows, since
    # ControlMaster mux is unusable here - see Invoke-SshXCore comment). None of them depend
    # on each other's *result*, only on being read together, so ship them as one remote
    # script with plain-text markers and split the single reply locally instead.
    $combinedCmd = "echo ACTIVE_MOUNT_LINE:`$(grep -E '^ACTIVE_MOUNT=' ~/.claude-connect.conf 2>/dev/null); echo LIVE_MOUNTS_BEGIN; ls -1 `$HOME/mounts 2>/dev/null; echo LIVE_MOUNTS_END; $CM list 2>/dev/null"
    $activeId = ''
    $live = @{}
    $out = @()
    $section = 'none'
    try {
        foreach ($line in @(SshX $combinedCmd)) {
            if ($line -match '^ACTIVE_MOUNT_LINE:(.*)$') {
                $rest = $matches[1]
                if ($rest -match 'ACTIVE_MOUNT=(.*)$') { $activeId = $matches[1].Trim() }
                continue
            }
            $trimmed = $line.Trim()
            if ($trimmed -eq 'LIVE_MOUNTS_BEGIN') { $section = 'live'; continue }
            if ($trimmed -eq 'LIVE_MOUNTS_END') { $section = 'list'; continue }
            if ($section -eq 'live') {
                if ($trimmed) { $live[$trimmed] = $true }
                continue
            }
            if ($section -eq 'list' -and $trimmed -match '^([^\|]+)\|([^\|]*)\|([^\|]*)\|([^\|]+)$') {
                $id = $matches[1].Trim()
                $mounted = $live.ContainsKey($id) -or ($id -eq $activeId)
                $out += [PSCustomObject]@{
                    Id      = $id
                    Label   = $matches[2].Trim()
                    Rpath   = $matches[3].Trim()
                    Lpath   = $matches[4].Trim()
                    Path    = $matches[4].Trim()
                    Active  = ($id -eq $activeId)
                    Mounted = $mounted
                }
            }
        }
    } catch {}
    # Write-through cache: the catalog changes rarely, but every SSH here costs a full ~1.6s
    # handshake (no ControlMaster on Windows). Persist the freshest good result so the NEXT
    # launch can render the menu instantly from disk (Get-MountsCached) while this session
    # still shows live data. Only cache non-empty results (never poison the cache on a failed
    # fetch). add/edit/delete call Get-Mounts directly, so they rewrite the cache too.
    if (@($out).Count -gt 0) {
        try {
            $cp = Get-MountsCachePath
            $cdir = Split-Path -Parent $cp
            if ($cdir -and -not (Test-Path -LiteralPath $cdir)) { New-Item -ItemType Directory -Force -Path $cdir | Out-Null }
            (@($out) | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $cp -Encoding UTF8
        } catch {}
    }
    return $out
}

function Get-MountsCachePath {
    $dir = if ($script:CfgDir) { $script:CfgDir } elseif ($CfgDir) { $CfgDir } else { Join-Path $env:USERPROFILE '.config\claude-connect' }
    return (Join-Path $dir 'mounts-cache.json')
}

function Get-MountsCached {
    # Menu-path loader: return the on-disk catalog instantly when it is recent, else fall back to
    # a live Get-Mounts (which also refreshes the cache). TTL bounds staleness; add/edit/delete
    # always go through Get-Mounts, so user-driven changes are reflected immediately.
    param([int]$CacheTtlSec = 900)
    $cachePath = Get-MountsCachePath
    try {
        if (Test-Path -LiteralPath $cachePath) {
            $ageSec = ((Get-Date) - (Get-Item -LiteralPath $cachePath).LastWriteTime).TotalSeconds
            if ($ageSec -lt $CacheTtlSec) {
                $raw = Get-Content -LiteralPath $cachePath -Raw -ErrorAction Stop
                # PS 5.1 quirk: ConvertFrom-Json emits a JSON array as ONE non-enumerated pipeline
                # object, so wrapping that pipeline directly in an array subexpression collapses all
                # rows into a single element whose properties are arrays (the "1 garbled project"
                # bug). Assign the parse result to a variable FIRST, THEN wrap it in @().
                $parsed = $raw | ConvertFrom-Json
                $cached = @($parsed)
                if (@($cached).Count -gt 0) {
                    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                        Write-ConnectLog ("MENU: mounts_cache_hit count={0} age_s={1}" -f @($cached).Count, [int]$ageSec) 'DEBUG'
                    }
                    return $cached
                }
            }
        }
    } catch {}
    return @(Get-Mounts)
}

function Select-Mount($mounts, $n) {
    if ($n -match '^[0-9]+$') {
        $i = [int]$n - 1
        if ($i -ge 0 -and $i -lt $mounts.Count) { return $mounts[$i] }
    }
    return $null
}

function Add-Project {
    Write-ConnectDecision 'project_menu' 'add_begin'
    Write-Host ''
    Write-Host '    Add project' -ForegroundColor White
    Write-Host ''
    $picked = Pick-LaptopFolder
    if ($picked) {
        Write-Host "    Selected: $picked" -ForegroundColor DarkGray
        $nPath = $picked
    } else {
        $nPath = (Read-ConnectPrompt '    Folder on your laptop (e.g. D:\Smart)' -Tag 'ADD_PATH').Trim() -replace '\\','/'
    }
    if (-not $nPath) { Warn 'Path is required.'; return $null }
    if ($nPath -match '^[A-Za-z]:$') { $nPath = "$nPath/" }
    $idSrc = $nPath -replace '/+$',''
    $nId   = (($idSrc -split '/')[-1]).ToLower() -replace '[^a-z0-9_-]','-' -replace '-+','-' -replace '^-|-$',''
    $nLbl  = if ($nId) { (Get-Culture).TextInfo.ToTitleCase(($nId -replace '-',' ')) } else { "" }
    $d = (Read-ConnectPrompt "    Name [$nLbl]" -Tag 'ADD_NAME').Trim(); if ($d) { $nLbl = $d }
    Write-ConnectDecision 'project_add' ("id={0} label={1} path={2}" -f $nId, $nLbl, $nPath)
    if (-not $nId) { $nId = $nLbl.ToLower() -replace '[^a-z0-9_-]','-' -replace '-+','-' -replace '^-|-$','' }
    if (-not $nId) { Warn "Could not derive a project name."; return $null }
    $existing = @(Get-Mounts) | Where-Object { $_.Id -eq $nId }
    if ($existing.Count -gt 0) {
        Warn "Project '$nId' already exists. Enter a different name."
        return $null
    }
    $nLpath = "/home/$RemoteUser/mounts/$nId"
    Write-Host ""
    $nLbl_sh  = $nLbl  -replace "'", "'\\''"; $nPath_sh = $nPath -replace "'", "'\\''";
    $out = (SshX "$CM add '$nId' '$nLbl_sh' '$nPath_sh' '$nLpath'" 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) { Warn $out.Trim(); return $null }
    return ,([PSCustomObject]@{ Id = $nId; Path = $nLpath })
}

function Choose-Project {
    param([array]$Mounts)

    $mounts = @(Get-MountsForLaptop -Os 'windows' -Mounts $Mounts)
    $hiddenCount = Get-SkippedMountCountForLaptop -Os 'windows' -Mounts $Mounts
    while ($true) {
        if ($mounts.Count -eq 0) {
            if ($hiddenCount -gt 0) {
                Write-Host "    No PC projects ($hiddenCount Mac-only on server)." -ForegroundColor DarkGray
                Write-Host ''
            }
            $null = ($added = Add-Project)
            if (-not $added) { return $null }
            return ,$added
        }

        Write-GitModeBanner -GitMode (Get-GitMode)
        Write-ProjectTable -Mounts $mounts
        $c = (Read-ConnectPrompt '    >' -Tag 'MENU_PROJECT').Trim().ToLower()
        Write-Host ''
        if (-not $c) { Write-ConnectDecision 'project_menu' 'empty_retry'; continue }
        if ($c -match '^[0-9]+$') {
            $null = ($m = Select-Mount $mounts $c)
            if (-not $m) { Write-ConnectDecision 'project_select' "not_found:$c" 'WARN'; Warn "Not found."; continue }
            if (-not (Warn-InvalidProjectRpath -Rpath $m.Rpath -Num $c -Os 'windows')) { Write-ConnectDecision 'project_select' "invalid_rpath:$c"; continue }
            Write-ConnectDecision 'project_select' ("id={0} path={1} rpath={2}" -f $m.Id, $m.Path, $m.Rpath)
            return ,([PSCustomObject]@{ Id = $m.Id; Path = $m.Path; Rpath = $m.Rpath })
        }

        switch ($c) {
            "a" {
                Write-ConnectDecision 'project_menu' 'add'
                $null = ($r = Add-Project)
                if ($r) { return ,$r }
                $null = ($allMounts = @(Get-Mounts))
                $null = ($mounts = @(Get-MountsForLaptop -Os 'windows' -Mounts $allMounts))
                $hiddenCount = Get-SkippedMountCountForLaptop -Os 'windows' -Mounts $allMounts
            }
            'e' {
                Write-ConnectDecision 'project_menu' 'edit'
                $null = ($cur = Select-Mount $mounts (Read-ConnectPrompt '    Edit number' -Tag 'MENU_EDIT_NUM').Trim())
                if (-not $cur) { Warn 'Not found.'; continue }
                Write-Host ''
                $nLbl = (Read-ConnectPrompt "    Display name [$($cur.Label)]" -Tag 'MENU_EDIT_LABEL').Trim(); if (-not $nLbl) { $nLbl = $cur.Label }
                $nR   = (Read-ConnectPrompt "    Laptop folder [$($cur.Rpath)]" -Tag 'MENU_EDIT_PATH').Trim() -replace '\\','/'; if (-not $nR) { $nR = $cur.Rpath }
                Write-ConnectDecision 'project_edit' ("id={0} label={1} rpath={2}" -f $cur.Id, $nLbl, $nR)
                Write-Host "    Server path (read-only): $($cur.Lpath)" -ForegroundColor DarkGray
                $nL   = $cur.Lpath
                $nLbl_sh = $nLbl -replace "'", "'\\''"; $nR_sh = $nR -replace "'", "'\\''"
                $editOut = (SshX "$CM edit '$($cur.Id)' '$nLbl_sh' '$nR_sh' '$nL'" 2>&1) | Out-String
                if ($LASTEXITCODE -ne 0) { Warn $editOut.Trim() }
                $null = ($allMounts = @(Get-Mounts))
                $null = ($mounts = @(Get-MountsForLaptop -Os 'windows' -Mounts $allMounts))
                $hiddenCount = Get-SkippedMountCountForLaptop -Os 'windows' -Mounts $allMounts
            }
            "d" {
                Write-ConnectDecision 'project_menu' 'delete'
                $null = ($m = Select-Mount $mounts (Read-ConnectPrompt "    Delete number" -Tag 'MENU_DEL_NUM').Trim())
                if (-not $m) { Warn "Not found."; continue }
                if ((Read-ConnectPrompt "    Delete '$($m.Label)'? [y/N]" -Tag 'MENU_DEL_CONFIRM').Trim().ToLower() -eq "y") {
                    Write-ConnectDecision 'project_delete' $m.Id
                    $rmOut = (SshX "$CM rm '$($m.Id)'" 2>&1) | Out-String
                    if ($LASTEXITCODE -ne 0) { Warn $rmOut.Trim() }
                    $null = ($allMounts = @(Get-Mounts))
                    $null = ($mounts = @(Get-MountsForLaptop -Os 'windows' -Mounts $allMounts))
                    $hiddenCount = Get-SkippedMountCountForLaptop -Os 'windows' -Mounts $allMounts
                }
            }
            'c' {
                Write-ConnectDecision 'project_menu' 'config'
                Write-Host ''
                Write-Host '    Configuration' -ForegroundColor White
                Write-Host ''
                Write-Host "    Username   : $RemoteUser" -ForegroundColor DarkGray
                Write-Host "    Git mode   : $(Get-GitModeLabel) ($(Get-GitMode))" -ForegroundColor DarkGray
                Write-Host "    IDE        : $(Get-EditorPref -CfgDir $CfgDir)" -ForegroundColor DarkGray
                Write-Host ''
                Write-Host '    1  Change server username' -ForegroundColor DarkGray
                Write-Host '    2  Change IDE preference' -ForegroundColor DarkGray
                Write-Host '    3  Change git mode' -ForegroundColor DarkGray
                Write-Host ''
                $cfgChoice = (Read-ConnectPrompt '    >' -Tag 'MENU_CONFIG').Trim()
                Write-ConnectDecision 'config_choice' $cfgChoice
                switch ($cfgChoice) {
                    '1' {
                        $nUser = (Read-ConnectPrompt '    New server username (Enter to cancel)' -Tag 'CFG_USER').Trim()
                        if ($nUser -and $nUser -ne $RemoteUser) {
                            if ($nUser -match '[@/\\]') { Warn "Invalid server username." }
                            else {
                                Save-ConnectConfKey -Path $Cfg -Key 'REMOTE_USER' -Value $nUser
                                Save-ConnectConfKey -Path $Cfg -Key 'LAPTOP_USER' -Value (Get-InteractiveLaptopUser)
                                Remove-SshHostBlock $sshCfg $Alias
                                Write-Host ''; Write-Host '    Saved. Re-run connect.bat.' -ForegroundColor Green
                                Write-ConnectDecision 'config_username_saved_relaunch' $nUser
                                if (Get-Command Close-ConnectLog -ErrorAction SilentlyContinue) { Close-ConnectLog }
                                Write-Host ''; exit 0
                            }
                        }
                    }
                    '2' { Configure-EditorPref -CfgDir $CfgDir }
                    '3' { Configure-GitMode }
                    default { Write-Host '    Cancelled.' -ForegroundColor DarkGray; Write-Host '' }
                }
            }
            "g" { Write-ConnectDecision 'project_menu' 'git_mode'; Configure-GitMode }
            "q" { Write-ConnectDecision 'project_menu' 'quit'; if (Get-Command Close-ConnectLog -ErrorAction SilentlyContinue) { Close-ConnectLog }; Write-Host ""; exit 0 }
            default {
                $raw = [string]$_
                $isAscii = $raw.Length -ge 1 -and ($raw.ToCharArray() | Where-Object { [int]$_ -gt 127 } | Measure-Object).Count -eq 0
                if ($isAscii) {
                    Warn "Enter a number or a/e/d/c/g/q."
                } elseif (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                    Write-ConnectLog ("PROJECT_MENU ignore non_command choice={0}" -f $raw) 'INFO'
                }
            }
        }
    }
}



# config
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
if ($Setup -or -not (Test-Path $Cfg)) {
    Write-Host "  First-time setup" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "    Server username = your Linux account on the server" -ForegroundColor DarkGray
    Write-Host "    (NOT your Windows login. Ask admin if unsure.)" -ForegroundColor DarkGray
    Write-Host ""
    $RemoteUser = (Read-ConnectPrompt "    Server username" -Tag 'SETUP_USER').Trim()
    Write-ConnectDecision 'setup_remote_user' $RemoteUser
    if (-not $RemoteUser) { throw "Server username is required" }
    if ($RemoteUser -match '[@/\\]') { throw "Invalid server username: $RemoteUser" }
    $laptopUser = Get-InteractiveLaptopUser
    Save-ConnectConfKey -Path $Cfg -Key 'REMOTE_USER' -Value $RemoteUser
    Save-ConnectConfKey -Path $Cfg -Key 'LAPTOP_USER' -Value $laptopUser
    Write-Host ""
}

$conf = @{}
Get-Content $Cfg | ForEach-Object { if ($_ -match '^(.+?)=(.*)$'){ $conf[$matches[1]] = $matches[2] } }
$RemoteUser = $conf["REMOTE_USER"]
# Cross-site conf leak only: Smart REMOTE_USER=smart must not hit Sepidz IP.
# Do NOT force personal Sepidz accounts (farzadb/hosseinb/...) onto shared sepidz@.
if ($ServerIP -eq '192.168.250.70' -and $RemoteUser -eq 'smart') {
    Write-ConnectLog 'REMOTE_USER_OVERRIDE from=smart to=sepidz reason=cross_site_smart_conf' 'WARN'
    $RemoteUser = 'sepidz'
}
if ($ServerIP -eq '192.168.210.240' -and $RemoteUser -eq 'sepidz') {
    Write-ConnectLog 'REMOTE_USER_OVERRIDE from=sepidz to=smart reason=cross_site_sepidz_conf' 'WARN'
    $RemoteUser = 'smart'
}
$LaptopUser = $conf["LAPTOP_USER"]
$script:LaptopUser = $LaptopUser
# When elevated as a different admin account, $env:USERPROFILE may point to the wrong user profile.
# Use LAPTOP_USER from config for .ssh and editor prefs (same as SSH key paths).
if ($LaptopUser -and (Test-Path "C:\Users\$LaptopUser")) {
    $CfgDir = [System.IO.Path]::Combine("C:\Users\$LaptopUser", '.config', 'claude-connect')
    $Cfg    = [System.IO.Path]::Combine($CfgDir, 'connect.conf')
    $SshDir = [System.IO.Path]::Combine("C:\Users\$LaptopUser", '.ssh')
}
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
New-Item -ItemType Directory -Force -Path $SshDir  | Out-Null

Clear-Host
if (Test-IsAdmin) { Initialize-EditorLaunchTask | Out-Null }
Write-ConnectHeader -Alias $Alias -ServerIP $ServerIP -Version $script:ConnectVersion
$script:ConnectSystemProxy = $null
if (Get-Command Initialize-ConnectProxyForSsh -ErrorAction SilentlyContinue) {
    $script:ConnectSystemProxy = Initialize-ConnectProxyForSsh -ServerIP $ServerIP
} elseif (Get-Command Apply-ConnectProxyEnvironment -ErrorAction SilentlyContinue) {
    $script:ConnectSystemProxy = Apply-ConnectProxyEnvironment -ServerIp $ServerIP
}

Set-ConnectTitle 'Claude Connect'
Write-BootstrapHint -CfgDir $CfgDir
Write-Host ''

# Fix .ssh dir permissions (after LAPTOP_USER rebind when elevated)
$_dirOut = (icacls $SshDir 2>$null) -join ' '
$_dirFixed = $_dirOut -match '\(I\)|Everyone|BUILTIN\\Users'
icacls $SshDir /reset 2>$null | Out-Null
icacls $SshDir /inheritance:r /grant "$env:USERNAME`:(OI)(CI)F" 2>$null | Out-Null
if ($LaptopUser -and $LaptopUser -ne $env:USERNAME) {
    icacls $SshDir /grant "$($LaptopUser):(OI)(CI)F" 2>$null | Out-Null
}
if ($_dirFixed) { Write-Host "      -> fixed: .ssh directory permissions" -ForegroundColor DarkGray; Write-Host "" }

# SSH key
Step "Laptop SSH key"
$keyA = [System.IO.Path]::Combine($SshDir, 'id_ed25519')
if (-not (Test-Path $keyA)) { ssh-keygen -t ed25519 -N '""' -f $keyA -q }
if (Test-Path $keyA) {
    Repair-SshPerm $keyA "SSH private key"
    StepOk
} else { StepFail "could not create key"; Wait-ConnectExit -Reason 'ssh_key_create_fail' -Code 1 }

# SSH config
$sshCfg = [System.IO.Path]::Combine($SshDir, 'config')
if (-not (Test-Path $sshCfg)) { New-Item -ItemType File -Path $sshCfg | Out-Null }
Remove-SshHostBlock $sshCfg $Alias
$sshCfgUser = Get-SshConfigUserForServer -Ip $ServerIP -FallbackUser $RemoteUser
@"

Host $Alias
    HostName $ServerIP
    User $sshCfgUser
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
"@ | Add-Content -Path $sshCfg -Encoding ASCII
Sanitize-SshAliasConfig -CfgPath $sshCfg -AliasName $Alias
if (Get-Command Request-ConnectLogSync -ErrorAction SilentlyContinue) { Request-ConnectLogSync -NoInline | Out-Null } elseif (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null }  # ship BOOTSTRAP/UPDATE + session so far (async only - never block boot)
# Fix SSH config permissions silently - shown later under the step that calls StepOk
icacls $sshCfg /reset 2>$null | Out-Null
icacls $sshCfg /inheritance:r /grant "$env:USERNAME`:F" 2>$null | Out-Null

# connect - retry until reachable, 5s between attempts (direct first; optional SSH proxy fallback)
$connected = $false
$needsKey  = $false
$proxyInfo = if ($script:ConnectSystemProxy) { $script:ConnectSystemProxy } else { $null }
$serverBypassesProxy = $false
if ($proxyInfo -and (Get-Command Test-ConnectServerBypassesProxy -ErrorAction SilentlyContinue)) {
    $serverBypassesProxy = Test-ConnectServerBypassesProxy -ServerIP $ServerIP -Bypass @($proxyInfo.Bypass)
}
for ($attempt = 1; $attempt -le 10; $attempt++) {
    Write-Host -NoNewline ("    Connecting $attempt/10").PadRight(46, '.') -ForegroundColor DarkCyan
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("CONNECT_ATTEMPT n={0}/10 alias={1} target={2}@{3}" -f $attempt, $Alias, $RemoteUser, $ServerIP)
    }
    $probe = $null
    if (Get-Command Invoke-ConnectBootstrapSsh -ErrorAction SilentlyContinue) {
        $probe = Invoke-ConnectBootstrapSsh -Alias $Alias -ConnectTimeout 15
    } else {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=15 $Alias "true" 2>$null
        $sw.Stop()
        $probe = [PSCustomObject]@{ Exit = $LASTEXITCODE; Sec = [math]::Round($sw.Elapsed.TotalSeconds, 1); ViaProxy = $false }
    }
    $connT = $probe.Sec
    if ($probe.Exit -eq 0) {
        Write-Host " $RemoteUser@$ServerIP" -ForegroundColor Green
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("CONNECT_OK attempt={0} sec={1} target={2}@{3} via_proxy=0" -f $attempt, $connT, $RemoteUser, $ServerIP)
        }
        $connected = $true; break
    }
    $proxyWorked = $false
    if ($proxyInfo -and $proxyInfo.Enabled -and -not $serverBypassesProxy -and $script:ConnectSshProxyCommand -and (Get-Command Invoke-ConnectBootstrapSsh -ErrorAction SilentlyContinue)) {
        $proxyProbe = Invoke-ConnectBootstrapSsh -Alias $Alias -ConnectTimeout 15 -ViaProxy
        if ($proxyProbe.Exit -eq 0) {
            $connT = $proxyProbe.Sec
            $script:ConnectSshExtraOptions = @('-o', "ProxyCommand=$($script:ConnectSshProxyCommand)")
            Write-Host " $RemoteUser@$ServerIP (via proxy)" -ForegroundColor Green
            if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                Write-ConnectLog ("CONNECT_OK attempt={0} sec={1} target={2}@{3} via_proxy=1" -f $attempt, $connT, $RemoteUser, $ServerIP)
            }
            $connected = $true
            $proxyWorked = $true
            break
        }
    }
    if ($proxyWorked) { break }
    if (PortOpen $ServerIP 22) {
        Write-Host " auth failed (${connT}s) - no key, installing now" -ForegroundColor DarkYellow
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("CONNECT_AUTH_NEEDED attempt={0} sec={1} port22=open remote_user={2} ssh_cfg_user={3} alias={4}" -f $attempt, $connT, $RemoteUser, $sshCfgUser, $Alias) 'WARN'
        }
        $needsKey = $true; break
    }
    Write-Host " no response (${connT}s)" -ForegroundColor DarkGray
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("CONNECT_NO_RESPONSE attempt={0} sec={1}" -f $attempt, $connT) 'WARN'
    }
    if ($attempt -lt 10) {
        Write-Host "    Waiting 5s (VPN on? Server up?)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
    }
}

if (-not $connected -and -not $needsKey) {
    Write-Host ""
    Warn "Cannot reach $ServerIP after 10 attempts"
    Warn "VPN connected? Server running?"
    if (Get-Command Write-ConnectProxySshDirectFailedNote -ErrorAction SilentlyContinue) {
        Write-ConnectProxySshDirectFailedNote -ProxyInfo $proxyInfo -ServerBypassesProxy $serverBypassesProxy
    }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("FAIL CONNECT_UNREACHABLE: target={0}@{1} attempts=10" -f $RemoteUser, $ServerIP) 'ERROR'
    }
    Wait-ConnectExit -Reason 'require_fail' -Code 1
}

if ($needsKey) {
    Write-Host ""
    # Clear stale known_hosts entry so host key mismatch doesn't block auth
    ssh-keygen -R $ServerIP 2>$null | Out-Null
    $maxFixAttempts = 2
    $fixAttemptsUsed = 0
    $authOk = $false
    while (-not $authOk) {
        Write-Host "    Enter server password (one time only):" -ForegroundColor Yellow
        $pubKeyContent = (Get-Content "$keyA.pub").Trim() -replace "'", "'\''"
        ssh -o StrictHostKeyChecking=accept-new "$RemoteUser@$ServerIP" `
            "mkdir -p ~/.ssh && chmod 700 ~/.ssh && printf '%s\n' '$pubKeyContent' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        $keyCopyOk = ($LASTEXITCODE -eq 0)
        Step "Verifying connection"
        $verifySW = [System.Diagnostics.Stopwatch]::StartNew()
        ssh -n -o ClearAllForwardings=yes -o BatchMode=yes -o ConnectTimeout=15 $Alias "true" 2>$null
        $verifySW.Stop()
        $verifyT = [math]::Round($verifySW.Elapsed.TotalSeconds, 1)
        if ($LASTEXITCODE -eq 0) {
            $authOk = $true
            break
        }
        if (-not $keyCopyOk) { StepFail "key copy failed after ${verifyT}s - wrong password?" }
        else { StepFail "still cannot connect after ${verifyT}s" }
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("FAIL CONNECT_AUTH_VERIFY keyCopyOk={0} verify_s={1} alias={2} remote_user={3} host={4} ssh_cfg_user={5} fix_attempts={6}/{7}" -f $keyCopyOk, $verifyT, $Alias, $RemoteUser, $ServerIP, $sshCfgUser, $fixAttemptsUsed, $maxFixAttempts) 'ERROR'
            try {
                $bread = Join-Path $env:USERPROFILE '.config\claude-connect\last-fail.txt'
                $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
                $line = "[$ts] [ERROR] FAIL CONNECT_AUTH_VERIFY keyCopyOk=$keyCopyOk verify_s=$verifyT alias=$Alias remote_user=$RemoteUser host=$ServerIP ssh_cfg_user=$sshCfgUser fix_attempts=$fixAttemptsUsed/$maxFixAttempts`r`n"
                New-Item -ItemType Directory -Force -Path (Split-Path $bread) | Out-Null
                [IO.File]::AppendAllText($bread, $line, [Text.UTF8Encoding]::new($false))
            } catch { }
        }
        Write-Host ""
        Warn "Cannot connect - user=$RemoteUser  host=$ServerIP"
        Write-Host ""
        Write-Host "    Current username: $RemoteUser" -ForegroundColor DarkGray
        Write-Host "    (SSH auth failed - username usually unchanged; re-check password / VPN)" -ForegroundColor DarkGray
        if ($fixAttemptsUsed -ge $maxFixAttempts) {
            if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                Write-ConnectLog ("FAIL SSH_USER_FIX_EXHAUSTED attempts={0}/{1} remote_user={2}" -f $fixAttemptsUsed, $maxFixAttempts, $RemoteUser) 'ERROR'
            }
            Wait-ConnectExit -Reason 'require_fail' -Code 1
        }
        $fix = $null
        while ($true) {
            $fix = (Read-ConnectPrompt "    If server username is wrong, enter it (or Enter to exit)" -Tag 'SSH_USER_FIX').Trim()
            if (-not $fix) {
                Write-ConnectDecision 'ssh_username_fix' '(empty_exit)'
                Wait-ConnectExit -Reason 'require_fail' -Code 1
            }
            if ($fix -match '[@/\\]') {
                Warn "Invalid username (must not contain @ / \): $fix"
                if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                    Write-ConnectLog ("SSH_USER_FIX_INVALID user={0}" -f $fix) 'WARN'
                }
                Write-ConnectDecision 'ssh_username_fix' ("invalid:$fix")
                continue
            }
            break
        }
        $fixAttemptsUsed++
        Write-ConnectDecision 'ssh_username_fix' $fix
        $RemoteUser = $fix
        Save-ConnectConfKey -Path $Cfg -Key 'REMOTE_USER' -Value $RemoteUser
        Save-ConnectConfKey -Path $Cfg -Key 'LAPTOP_USER' -Value (Get-InteractiveLaptopUser)
        Remove-SshHostBlock $sshCfg $Alias
        $sshCfgUser = Get-SshConfigUserForServer -Ip $ServerIP -FallbackUser $RemoteUser
        @"

Host $Alias
    HostName $ServerIP
    User $sshCfgUser
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
"@ | Add-Content -Path $sshCfg -Encoding ASCII
        Sanitize-SshAliasConfig -CfgPath $sshCfg -AliasName $Alias
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("SSH_USER_FIX_RETRY in-process attempt={0}/{1} remote_user={2} ssh_cfg_user={3}" -f $fixAttemptsUsed, $maxFixAttempts, $RemoteUser, $sshCfgUser)
        }
        Write-Host ""
        Write-Host "    Retrying in-process with user=$RemoteUser (attempt $fixAttemptsUsed/$maxFixAttempts)..." -ForegroundColor Green
    }
    StepOk "$RemoteUser@$ServerIP"
}


# Guard: wrong server username / taking over another laptop's session
# NOTE (2026-07-21): this used to be a blocking `Sync-ConnectLogToServer -Force` so the audit
# trail was guaranteed on the server before a potential session takeover. Measured cost: the
# full sync path (mkdir+scp+cat, up to 3 SSH/SCP round trips) can take several real seconds
# under normal server load, and this sat squarely in the timed startup path on every single
# connect, not just the rare takeover case. Downgraded to the same best-effort async request
# used elsewhere (Request-ConnectLogSync) - the local day-log file already has the full record
# unconditionally (Force only affected how soon the SERVER's copy saw it), and the async drain
# still runs within ~1.5s or at the latest by session end (Complete-ConnectLogAsyncDrain -Force
# there is unchanged) - so the audit trail lands moments later instead of immediately, not lost.
if (Get-Command Request-ConnectLogSync -ErrorAction SilentlyContinue) { Request-ConnectLogSync -NoInline | Out-Null }
if (-not (Warn-ForeignServerSession)) {
    Wait-ConnectExit -Reason 'foreign_session' -Code 1
}

# Server setup (port + key + scripts in one step; script push runs parallel to local key install)
Step "Server setup"
$boot = Initialize-ServerSession -ConnectScriptDir $script:ConnectScriptDir -Alias $Alias -SshCfgPath $sshCfg
if ($boot.Error) { StepFail $boot.Error; Warn "Tip: confirm server username with: connect.bat -Setup"; Wait-ConnectExit -Reason "boot_error:$($boot.Error)" -Code 1 }
if (-not $boot.Ok) { StepFail ($script:pendingFixes -join ', '); Wait-ConnectExit -Reason 'boot_not_ok' -Code 1 }
if ($boot.ContainsKey('PushOk') -and -not $boot.PushOk) {
    Write-Host '    [!] server script push failed (continuing)' -ForegroundColor Yellow
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'FAIL SERVER_SCRIPT_PUSH: continuing without refreshed server scripts' 'ERROR'
    }
}
StepOk "port $Port slot=$($script:TunnelSlot) git=$(Get-GitMode)"
$PubB = $boot.PubB

Write-Host ''
if (Get-Command Request-ConnectLogSync -ErrorAction SilentlyContinue) { Request-ConnectLogSync -NoInline | Out-Null } elseif (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer | Out-Null }
Write-Host '    Ready' -ForegroundColor Green
Write-Host ''
Mark-BootstrapDone -CfgDir $CfgDir
$laptopReady = Ensure-LaptopSshReady -PubB $PubB
if (-not $laptopReady) {
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'FAIL LAPTOP_SSH_BOOT: Ensure-LaptopSshReady returned false (continuing; tunnel auth may still work)' 'ERROR'
    }
    Warn 'Laptop SSH admin fix incomplete - continuing; tunnel auth may fail until fixed'
} else {
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        $script:LaptopFirewallOk = $true
        Write-ConnectLog 'LAPTOP_SSH: boot_ready ok'
    }
}
$script:LaptopSshVerified = $false
$script:SessionBgTunnel = $null
$script:LastMountCheckOkAt = $null
$script:LastMountCheckOkProject = $null
$null = Initialize-SessionBgTunnel -Alias $Alias -SshCfgPath $sshCfg -Quiet

$script:tunnelAuthAdminFixAttempted = $false
$exitRequested = $false
:menuLoop while (-not $exitRequested) {
    Step "Loading projects"
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog 'MENU: loading_projects begin' 'DEBUG'
    }
    $null = ($allMounts = @(Get-MountsCached))
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("MENU: mounts_loaded count={0}" -f @($allMounts).Count) 'DEBUG'
    }
    StepOk (Get-MountListStepLabel -Os 'windows' -Mounts $allMounts)
    if (Get-Command Show-ConnectConsoleIfHidden -ErrorAction SilentlyContinue) { Show-ConnectConsoleIfHidden }
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog ("INTERACTIVE: project_menu_shown mounts={0}" -f @($allMounts).Count) 'INFO'
    }
    $go = @(Choose-Project -Mounts $allMounts)[-1]
    if (-not $go) {
        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog 'FAIL MENU_ABORT: Choose-Project returned empty (user quit or no selection)' 'ERROR'
        }
        break
    }
    Write-ConnectLog "PROJECT: id=$($go.Id) server_path=$($go.Path) laptop_path=$($go.Rpath)"
    if (Get-Command Write-ConnectDecision -ErrorAction SilentlyContinue) {
        Write-ConnectDecision 'project_selected' $go.Id
    }
if (Get-Command Write-ConnectSessionContext -ErrorAction SilentlyContinue) { Write-ConnectSessionContext -Phase 'project_selected' }
    $script:tunnelAuthAdminFixAttempted = $false
    $script:tunnelAuthRetryCount = 0

    if ($Ide) {
        $EditorCmd = if ($Ide -eq 'code' -or $Ide -eq 'vscode') { 'code' } else { 'cursor' }
        $EditorName = if ($EditorCmd -eq 'code') { 'VS Code' } else { 'Cursor' }
        Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'editor.conf')) -Value $EditorCmd -Encoding ASCII | Out-Null
        Ensure-EditorOnPath $EditorCmd | Out-Null
    } else {
        $editorChoice = @(Resolve-EditorChoice -CfgDir $CfgDir)[-1]
        if (-not $editorChoice) {
            Warn 'No editor found. Install Cursor or VS Code (+ Remote-SSH extension), then re-run.'
            Wait-ConnectExit -Reason 'project_fail' -Code 1
        }
        $EditorCmd = $editorChoice.EditorCmd
        $EditorName = $editorChoice.EditorName
    }

    Step "Checking SSH service"
    $svc = Get-Service sshd -ErrorAction SilentlyContinue
    if (-not $svc) {
        StepFail "OpenSSH Server not installed"
        Write-Host ""
        Write-Host "    OpenSSH Server not found - installing now..." -ForegroundColor Yellow
        $installed = $false
        # Method 1: Windows Capability (Win10/11 built-in) - requires Windows Update service
        $wuSvc = Get-Service wuauserv -ErrorAction SilentlyContinue
        if ($wuSvc -and $wuSvc.Status -ne 'Running') {
            Write-Host "    Starting Windows Update service for install..." -ForegroundColor DarkGray
            Start-Service wuauserv -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        try {
            Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop | Out-Null
            Write-Host "    OpenSSH Server installed ok (via Windows Capability)." -ForegroundColor Green
            $installed = $true
        } catch {
            Write-Host "    Windows Capability install failed: $($_.Exception.Message)" -ForegroundColor DarkGray
        }
        # Method 2: winget fallback
        if (-not $installed) {
            Write-Host "    Trying winget fallback..." -ForegroundColor DarkGray
            try {
                $wg = Get-Command winget -ErrorAction Stop
                & winget install --id Microsoft.OpenSSH.Beta -e --source winget --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
                $svc = Get-Service sshd -ErrorAction SilentlyContinue
                if ($svc) {
                    Write-Host "    OpenSSH Server installed ok (via winget)." -ForegroundColor Green
                    $installed = $true
                }
            } catch {
                Write-Host "    winget fallback failed: $($_.Exception.Message)" -ForegroundColor DarkGray
            }
        }
        if (-not $installed) {
            Write-Host "    Could not auto-install OpenSSH Server." -ForegroundColor Red
            Write-Host "    Manual fix: Settings -> Apps -> Optional Features -> OpenSSH Server" -ForegroundColor DarkGray
            Write-Host "    Or run as admin: Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0" -ForegroundColor DarkGray
            Wait-ConnectExit -Reason 'require_fail' -Code 1
        }
        Set-Service sshd -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service sshd -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $svc = Get-Service sshd -ErrorAction SilentlyContinue
        if (-not $svc -or $svc.Status -ne 'Running') {
            Write-Host "    Could not start sshd after install. Run as admin: Start-Service sshd" -ForegroundColor Red
            Wait-ConnectExit -Reason 'require_fail' -Code 1
        }
        Write-Host "    sshd started ok." -ForegroundColor Green
        # Re-run key setup: ProgramData\ssh\ now exists after install, first call skipped it.
        # ForceRestart=$true so sshd picks up administrators_authorized_keys (only re-read on start).
        if ($PubB) { $null = Invoke-LaptopAdminOps -PubB $PubB -ForceRestart }
    } elseif ($svc.Status -ne 'Running') {
        StepFail "OpenSSH Server not running"
        Write-Host ""
        Write-Host "    Trying to start sshd..." -ForegroundColor Yellow
        try {
            Start-Service sshd -ErrorAction Stop
            Start-Sleep -Seconds 1
            $svc = Get-Service sshd -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') {
                Write-Host "    sshd started ok." -ForegroundColor Green
            } else {
                Write-Host "    Could not start sshd. Run as admin: Start-Service sshd" -ForegroundColor Red
                Wait-ConnectExit -Reason 'require_fail' -Code 1
            }
        } catch {
            Write-Host "    Error starting sshd: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "    Run as admin: Start-Service sshd" -ForegroundColor DarkGray
            Wait-ConnectExit -Reason 'require_fail' -Code 1
        }
    } else {
        StepOk
    }
    # Firewall was already ensured during Laptop SSH boot / Ensure-LaptopSshReady.
    # Re-querying Get-NetFirewallRule here can stall 30-90s with no UI update (looks like
    # "Checking SSH service" is hung). Skip unless this session never marked it ok.
    if (-not $script:LaptopFirewallOk) {
        Step "Checking firewall"
        $fwRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
        if (-not $fwRule) {
            New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH SSH Server (sshd)" `
                -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any `
                -ErrorAction SilentlyContinue | Out-Null
        } elseif ($fwRule.Enabled.ToString() -ne 'True' -or $fwRule.Profile.ToString() -notmatch 'Any') {
            Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Enabled True -Profile Any -ErrorAction SilentlyContinue
        }
        $script:LaptopFirewallOk = $true
        StepOk
    }

    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) {
        # Tunnel already spawned before project menu - do not re-probe via SSH (and do not
        # open a "Preparing tunnel" step that can look hung while logs sync).
        Write-ConnectLog "PREPARE_TUNNEL skip reason=session_bg_alive pid=$($script:SessionBgTunnel.Id)" 'DEBUG'
    } else {
        Step "Preparing tunnel"
        $null = Initialize-SessionBgTunnel -Alias $Alias -SshCfgPath $sshCfg -Quiet
        StepOk
    }
    # First session-loop Ensure after this init is redundant (~7s). Reuse the bg tunnel.
    $script:SessionTunnelInitedForPick = [bool]($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited)

    $editorOpened = $false
    $script:EditorOpened = $false
    $script:EditorSeenOpen = $false
    $script:CursorAuthNeedsBootstrap = $false
    $script:RecoveryGeneration = 0
    $script:SessionLoopIter = 0
    $script:ForceCursorAuthSync = $false
    $script:PostTunnelRecovery = $false
    $script:RecoveryStartedAt = $null
    $script:SshRecentLog = [System.Collections.Generic.List[string]]::new()
    $script:LastAuthDetail = ''

    :mainLoop while ($true) {
    $alreadyDown  = $false
$script:WindowsMcpEnsured = $false
    $bgTunnel     = $script:SessionBgTunnel

    try {
        :sessionLoop while ($true) {
            $script:SessionLoopIter++
            # #Quiet-repeat: only the FIRST session-loop pass (the initial connect)
            # shows routine step "ok" lines on console; recovery re-passes stay file-only.
            $script:StepConsoleQuiet = ($script:SessionLoopIter -gt 1)
            if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                Write-ConnectLog "SESSION_LOOP begin iter=$($script:SessionLoopIter) recovery_gen=$($script:RecoveryGeneration) post_recovery=$($script:PostTunnelRecovery) force_auth=$($script:ForceCursorAuthSync)"
    if (Get-Command Write-ConnectSessionContext -ErrorAction SilentlyContinue) {
        # Always log full CONTEXT on the first session_loop pass; throttle later iterations
        # (same fields, just noisy) so a long-lived session does not spam the log every loop.
        $ctxThrottleOk = ($script:SessionLoopIter -eq 1) -or (-not $script:LastSessionLoopContextAt) -or
            (((Get-Date) - $script:LastSessionLoopContextAt).TotalSeconds -ge 300)
        if ($ctxThrottleOk) {
            Write-ConnectSessionContext -Phase 'session_loop'
            $script:LastSessionLoopContextAt = Get-Date
        } else {
            Write-ConnectLog "CONTEXT skip reason=throttle phase=session_loop iter=$($script:SessionLoopIter)" 'DEBUG'
        }
    }
            }
            $tunnelReused = $false
            if ($script:SessionLoopIter -eq 1 -and $script:SessionTunnelInitedForPick -and
                $bgTunnel -and -not $bgTunnel.HasExited) {
                $script:SessionTunnelInitedForPick = $false
                $needReseed = $false
                if (Get-Command Set-SocksProxyPortOnReuse -ErrorAction SilentlyContinue) {
                    Set-SocksProxyPortOnReuse -TunnelPid $bgTunnel.Id -Alias $Alias -SshCfgPath $sshCfg
                }
                if (Get-Command Test-TunnelNeedsProxyReseed -ErrorAction SilentlyContinue) {
                    $needReseed = [bool](Test-TunnelNeedsProxyReseed -TunnelPid $bgTunnel.Id -Alias $Alias -SshCfgPath $sshCfg)
                }
                if (-not $needReseed) {
                    $tunnelReused = $true
                    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                        Write-ConnectLog "ENSURE_TUNNEL skip reason=bg_init_same_pick pid=$($bgTunnel.Id) port=$Port socks=$($script:SocksProxyPort)" 'INFO'
                    }
                } elseif (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                    Write-ConnectLog "ENSURE_TUNNEL bg_init_reseed reason=proxy_leg pid=$($bgTunnel.Id) port=$Port" 'WARN'
                }
            }
            if (-not $tunnelReused -and -not (Ensure-SessionTunnel -Alias $Alias -SshCfgPath $sshCfg -BgTunnel ([ref]$bgTunnel) -TunnelReused ([ref]$tunnelReused))) {
                Step 'Starting SSH tunnel'
                StepFail "did not come up on port $Port"
                Write-Host ""
                Warn "Tunnel did not come up on port $Port"
                if (-not (PortOpen $ServerIP 22)) {
                    Warn "Server unreachable - VPN disconnected?"
                } else {
                    Warn "Check Windows Firewall - port 22 must allow inbound connections"
                }
                Write-Host ""
                Write-Host "    R = retry   Q = quit" -ForegroundColor DarkGray
                $rk = Read-RetryQuitKey
                if ($rk -eq 'r') { Write-Host ""; continue }
                Push-ServerConnectConf -ClearActiveMount
                $alreadyDown = $true; break sessionLoop
            }
            $script:SessionBgTunnel = $bgTunnel
            if (-not $tunnelReused) {
                # Wait-ForTunnelUp already printed progress lines
            } elseif ($tunnelReused) {
                Step 'SSH tunnel'
                StepOk "reusing pid $($bgTunnel.Id)"
            }

            $mountSrc = Get-ClaudeMountSrc -ConnectScriptDir $script:ConnectScriptDir
            Prepare-ServerSessionParallel -ProjectId $go.Id -MountSrc $mountSrc -Alias $Alias
            # Skip extra SSH when Push-ServerConnectConf already returned active= (saves ~600-900ms).
            if ($null -ne $script:LastPushConfActive) {
                $activeOnServer = 'ACTIVE_MOUNT=' + $script:LastPushConfActive
            } else {
                $activeOnServer = ((SshX "grep -E '^ACTIVE_MOUNT=' ~/.claude-connect.conf 2>/dev/null") -join '').Trim()
            }
            Write-ConnectLog "ACTIVE_MOUNT server_conf=$activeOnServer pushed_id=$($go.Id)"
            $amParsed = ($activeOnServer -replace '^ACTIVE_MOUNT=', '').Trim()
            if ($amParsed -and $go.Id -and ($amParsed -ne [string]$go.Id)) {
                Write-ConnectLog ("ACTIVE_MOUNT mismatch server_conf={0} pushed_id={1}" -f $amParsed, $go.Id) 'WARN'
            }
            if (Get-Command Write-ConnectSessionContext -ErrorAction SilentlyContinue) { Write-ConnectSessionContext -Phase 'server_ready' }

            # Sync mount health check (Invoke-RecoverIfNeeded -> Test-ProjectMountHealthy /
            # timeout 12 claude-mount check) is only needed for GIT_MODE=off skipRemount
            # reuse. Cold BG up skips it - agents use laptop-exec, not SSHFS.
            $recoverCheckOk = $false
            $gitModeOff = $false
            try { $gitModeOff = ((Get-GitMode) -eq 'off') } catch { $gitModeOff = $false }
            if ($gitModeOff) {
                # Session mount-ok TTL (2026-07-25): same ProjectId already passed
                # Invoke-RecoverIfNeeded / Test-ProjectMountHealthy within 60s - skip the
                # ~0.8s check SSH on re-pick / reconnect in the same Connect session.
                # Cold first pick and different ProjectId still run the full check.
                $mountCheckSessionOk = $false
                if ($script:LastMountCheckOkAt -and $script:LastMountCheckOkProject -and
                    [string]$script:LastMountCheckOkProject -eq [string]$go.Id -and
                    ((Get-Date) - $script:LastMountCheckOkAt).TotalSeconds -lt 60) {
                    $mountCheckSessionOk = $true
                    $recoverCheckOk = $true
                    Write-ConnectLog 'MOUNT_CHECK_SKIPPED reason=session_mount_ok' 'DEBUG'
                }
                if (-not $mountCheckSessionOk) {
                    $recoverCheckOk = Invoke-RecoverIfNeeded -ProjectId $go.Id -FreshTunnel:(-not $tunnelReused)
                    if ($recoverCheckOk) {
                        $script:LastMountCheckOkAt = Get-Date
                        $script:LastMountCheckOkProject = [string]$go.Id
                    } else {
                        $script:LastMountCheckOkAt = $null
                        $script:LastMountCheckOkProject = $null
                    }
                }

                if (-not (Test-TunnelUp)) {
                    Write-Host "      -> tunnel dropped during recover, restarting..." -ForegroundColor DarkGray
                    $script:LaptopSshVerified = $false
                    continue
                }
            }

            Step 'Verifying laptop SSH key'
            $laptopSshRc = Ensure-LaptopReverseSshCached -PubB $PubB
            if ($laptopSshRc -eq 0) {
                StepOk
            } elseif ($laptopSshRc -eq 1) {
                $script:tunnelAuthRetryCount++
                $failDetail = if ($script:LastLaptopReverseSshError) { $script:LastLaptopReverseSshError } else { 'tunnel auth failed' }
                StepFail $failDetail
                if ($failDetail -match 'Host key verification failed|Offending') {
                    Write-Host '      -> clearing stale server known_hosts for tunnel port...' -ForegroundColor DarkGray
                    Clear-ServerTunnelKnownHost
                    $script:LaptopSshVerified = $false
                } elseif ($failDetail -match 'Permission denied|publickey') {
                    # Likely claimed another laptop's reverse port (same Windows banner). Drop slot + reacquire.
                    Write-Host '      -> auth denied on tunnel port; dropping slot and reclaiming ours...' -ForegroundColor DarkGray
                    Write-ConnectLog "TUNNEL_AUTH: foreign_or_unauth port=$Port slot=$($script:TunnelSlot) - reacquire" 'WARN'
                    if ($Cfg -and (Test-Path $Cfg)) {
                        $cfgLines = @(Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object {
                            $_ -notmatch '^(TUNNEL_SLOT|PORT|TUNNEL_PORT)='
                        })
                        Set-Content -Path $Cfg -Value $cfgLines -Encoding ASCII
                    }
                    $script:TunnelSlot = $null
                    $uidStr = ((SshX 'id -u' 2>$null) -join '').Trim() -replace '\D', ''
                    if ($uidStr) { $null = Acquire-TunnelPort -UidStr $uidStr }
                    Clear-ServerTunnelKnownHost
                    $script:LaptopSshVerified = $false
                } elseif ($PubB -and -not $script:tunnelAuthAdminFixAttempted) {
                    $script:tunnelAuthAdminFixAttempted = $true
                    Write-Host '      -> reinstalling server key (admin authorized_keys)...' -ForegroundColor DarkGray
                    $null = Invoke-LaptopAdminOps -PubB $PubB -ForceRestart
                    Clear-ServerTunnelKnownHost
                    $script:LaptopSshVerified = $false
                }
                if ($script:tunnelAuthRetryCount -ge 5) {
                    Write-Host ''
                    Warn 'Tunnel auth failed 5 times - check sshd service and administrators_authorized_keys'
                    Write-Host '    R = retry   Q = quit' -ForegroundColor DarkGray
                    $rk = Read-RetryQuitKey
                    if ($rk -eq 'r') {
                        $script:tunnelAuthRetryCount = 0
                        $script:tunnelAuthAdminFixAttempted = $false
                        Write-Host ''
                        continue
                    }
                    Push-ServerConnectConf -ClearActiveMount
                    $alreadyDown = $true; break sessionLoop
                }
                Write-Host ''
                continue
            } else {
                StepFail 'server cannot authenticate to this PC'
                Write-Host ''
                Write-Host '    R = retry   Q = quit' -ForegroundColor DarkGray
                $rk = Read-RetryQuitKey
                if ($rk -eq 'r') { Write-Host ''; continue }
                Push-ServerConnectConf -ClearActiveMount
                $alreadyDown = $true; break sessionLoop
            }

            # Parallelize the Cursor-auth golden-stamp SSH fetch with the mount step below -
            # they're fully independent (mounting the SSHFS folder doesn't need Cursor auth
            # state, and the stamp check doesn't need the project mounted), but ran strictly
            # sequentially before. Kick it off now (only when the 45-min in-process cache in
            # Get-CursorGoldenExportedAtStamp would otherwise be cold and force a real SSH
            # round trip); harvest the result at "Syncing Cursor auth" below, by which point
            # the ~4s mount has almost certainly already covered its ~0.5-3s cost for free.
            # Raw Process (not Start-Process -PassThru) - see the SCP fix earlier the same day
            # for why: Start-Process -PassThru's .ExitCode is unreliable on this PS5.1 build.
            $script:BgAuthStampProc = $null
            $script:BgAuthStampTask = $null
            $stampCacheWarm = $script:CursorGoldenStampCache -and $script:CursorGoldenStampCache.At -and
                ((Get-Date) - $script:CursorGoldenStampCache.At).TotalMinutes -lt 45
            if (-not $stampCacheWarm) {
                try {
                    $bgPsi = New-Object System.Diagnostics.ProcessStartInfo
                    $bgPsi.FileName = 'ssh'
                    $bgPsi.Arguments = "-n -o BatchMode=yes -o ConnectTimeout=10 $Alias `"cat /etc/cursor-auth/golden/exported-at 2>/dev/null`""
                    $bgPsi.RedirectStandardOutput = $true
                    $bgPsi.RedirectStandardError = $true
                    $bgPsi.UseShellExecute = $false
                    $bgPsi.CreateNoWindow = $true
                    $script:BgAuthStampProc = [System.Diagnostics.Process]::Start($bgPsi)
                    $script:BgAuthStampTask = $script:BgAuthStampProc.StandardOutput.ReadToEndAsync()
                } catch {
                    $script:BgAuthStampProc = $null
                    $script:BgAuthStampTask = $null
                }
            }

            $skipRemount = $false
            try {
                if ($gitModeOff) { $skipRemount = [bool]$recoverCheckOk }
            } catch { $skipRemount = $false }
            if ($skipRemount) {
                Write-ConnectLog "MOUNT skip_remount reason=healthy git_mode=off project=$($go.Id)" 'INFO'
                # Step() must run unconditionally (not just under CLAUDE_CONNECT_VERBOSE) -
                # the unconditional StepOk "${mountT}s" below has no matching header on this
                # path otherwise, printing an orphaned " 0s" line with no step name on screen
                # and mislogging "STEP end" under whatever the PREVIOUS step happened to be
                # (currentStepName is stale when Step() was never called to update it).
                Step "Mounting files (already mounted)"
                $mountResult = [pscustomobject]@{ Ok = $true; Out = 'skip_remount_healthy'; Skipped = $true }
                $mountOut = $mountResult.Out
                $mountT = 0
            } else {
                # User request (2026-07-24): don't block the connect UI on a cold SSHFS mount -
                # it only serves Cursor's remote file-tree view (agent work goes through
                # laptop-exec, never this mount, per CLAUDE.md). Kick it off detached and
                # proceed straight to Opening Cursor; the background runner logs
                # MOUNT_BG_OK/MOUNT_BG_FAIL to this same day log (grep by session id) for
                # after-the-fact diagnosis instead of blocking with a synchronous retry/fail
                # prompt here.
                Step "Mounting files"
                Write-ConnectLog 'MOUNT_CHECK_SKIPPED reason=bg_up' 'DEBUG'
                [void](Start-MountProjectBackground -ProjectId $go.Id -Alias $Alias -LogDir (Join-Path $env:USERPROFILE '.config\claude-connect\logs') -SessionId (Get-ConnectSessionId))
                $mountResult = [pscustomobject]@{ Ok = $false; Out = 'started_in_background'; Skipped = $true; Pending = $true }
                $mountOut = $mountResult.Out
                $mountT = 0
            }
            $mountOk  = $mountResult.Ok

            if ($mountOut -eq 'started_in_background') {
                StepOk 'started in background'
            } else {
                StepOk "${mountT}s"
            }
            $alreadyDown = $false
            # Windows-MCP install/start/sync is intentionally backgrounded: uv/tool
            # install can take tens of seconds and must never slow the connect UI.
            if (-not $script:WindowsMcpEnsured -and (Get-Command Start-WindowsMcpEnsureBackground -ErrorAction SilentlyContinue)) {
                try {
                    $wmcpMod = $_windowsMcp
                    if (-not $wmcpMod -or -not (Test-Path -LiteralPath $wmcpMod)) {
                        $wmcpMod = Join-Path $script:ConnectScriptDir 'windows-mcp-laptop.ps1'
                    }
                    [void](Start-WindowsMcpEnsureBackground -ModulePath $wmcpMod -SshAlias $Alias)
                } catch {
                    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                        Write-ConnectLog ("WINDOWS_MCP: background_kick_failed {0}" -f $_.Exception.Message) 'WARN'
                    }
                } finally {
                    $script:WindowsMcpEnsured = $true
                }
            }
            Show-MountGitWarn $mountOut
            Write-ConnectLog "MOUNT_RAW: $($mountOut.Trim() -replace '\s+', ' ')"
            $cleanOut = ($mountOut.Trim() -replace '^already mounted:\s*', '' -replace '^mounted:\s*', '')
            $cleanOut = (($cleanOut -split '\r?\n')[0]).Trim()
            if ($cleanOut -and $cleanOut -notmatch '^warn:') {
                # Screen-only trim (user request): path detail stays in the file/server log
                # via Write-ConnectLog below, just no longer echoed to the console.
                Write-ConnectLog "MOUNT: $cleanOut"
            }
            if ($script:PostTunnelRecovery) {
                Warn 'Recovery complete - press O if Cursor is not on the project folder'
                Write-ConnectLog 'RECOVERY: user_warn press_o_if_cursor_not_on_folder'
            }

            $script:ActiveProjectId = $go.Id

            $script:CursorAuthNeedsBootstrap = $false
            $script:LastAuthDetail = if ($EditorCmd -eq 'cursor') { 'pending' } else { 'n/a' }
            $onCorrectFolder = $false
            $agentHome = $false
            $authRelaunch = $false
            if ($EditorCmd -eq 'cursor' -and (Get-Command Sync-CursorGoldenAuth -ErrorAction SilentlyContinue)) {
                $gsPath = Join-Path (Get-LocalCursorGlobalStorage) 'state.vscdb'
                $folderSw = [System.Diagnostics.Stopwatch]::StartNew()
                $onCorrectFolder = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                $agentHome = Test-RemoteEditorInAgentHome -RemotePath $go.Path
                $cursorRunning = $false
                if ($onCorrectFolder -and (Get-Command Test-RemoteEditorWindowOpenWhenOnFolder -ErrorAction SilentlyContinue)) {
                    $cursorRunning = Test-RemoteEditorWindowOpenWhenOnFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                }
                $folderSw.Stop()
                if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
                    Write-ConnectPerfLog -Mark 'auth_folder_check' -Ms $folderSw.ElapsedMilliseconds `
                        -Extra "on_folder=$onCorrectFolder window=$cursorRunning agent_home=$agentHome"
                }
                Write-ConnectLog "FOLDER_CHECK: on_folder=$onCorrectFolder agent_home=$agentHome window_open=$cursorRunning" 'DEBUG'
                $verboseLaunch = ($env:CLAUDE_CONNECT_VERBOSE_LAUNCH -eq '1')
                if ($verboseLaunch -and (Get-Command Get-RemoteEditorLaunchDiag -ErrorAction SilentlyContinue)) {
                    Write-ConnectLog (Get-RemoteEditorLaunchDiag -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path) 'DEBUG'
                } elseif (-not $verboseLaunch -and (Get-Command Get-RemoteEditorDetectionDiag -ErrorAction SilentlyContinue)) {
                    Write-ConnectLog "AUTH_CHECK: cursor_running=$cursorRunning on_folder=$onCorrectFolder" 'DEBUG'
                }
                # Harvest the background stamp fetch kicked off before "Mounting files" - by now
                # the mount step has almost certainly already covered its cost. A short WaitForExit
                # is just a safety margin, not the normal path (it should already be HasExited).
                # When mount is backgrounded that cover disappears - skip the 5s wait if local
                # stamp TTL already says current (Test-CursorAuthStampCurrent Source=local_ttl).
                $stampAlreadyCurrent = $false
                try {
                    if (Get-Command Test-CursorAuthStampCurrent -ErrorAction SilentlyContinue) {
                        $preStampCheck = Test-CursorAuthStampCurrent -DbPath $gsPath -Alias $Alias
                        $stampAlreadyCurrent = [bool]$preStampCheck.Current
                    }
                } catch { }
                if ($script:BgAuthStampProc) {
                    try {
                        if (-not $script:BgAuthStampProc.HasExited) {
                            if ($stampAlreadyCurrent) {
                                Write-ConnectLog 'AUTH_STAMP_WAIT_SKIPPED reason=local_ttl' 'DEBUG'
                            } else {
                                $null = $script:BgAuthStampProc.WaitForExit(5000)
                            }
                        }
                        if ($script:BgAuthStampProc.HasExited) {
                            $bgStamp = $script:BgAuthStampTask.Result.Trim()
                            if ($bgStamp -and $script:BgAuthStampProc.ExitCode -eq 0) {
                                if (-not $script:CursorGoldenStampCache) { $script:CursorGoldenStampCache = @{ Stamp = ''; At = $null } }
                                $script:CursorGoldenStampCache.Stamp = $bgStamp
                                $script:CursorGoldenStampCache.At = Get-Date
                                Write-ConnectLog "AUTH_STAMP_PREFETCH hit stamp=$bgStamp" 'DEBUG'
                                if (Get-Command Clear-CursorGoldenMissingCache -ErrorAction SilentlyContinue) {
                                    Clear-CursorGoldenMissingCache
                                }
                            }
                        }
                    } catch {
                        Write-ConnectLog "AUTH_STAMP_PREFETCH error=$($_.Exception.Message)" 'DEBUG'
                    }
                    $script:BgAuthStampProc = $null
                    $script:BgAuthStampTask = $null
                }
                Step "Syncing Cursor auth"
                # Single OpenDb session for both the completeness gate and the serviceMachineId
                # read used below to heal Electron's machineid file (no duplicate SQLite opens).
                $authState = if (Get-Command Get-LocalCursorAuthState -ErrorAction SilentlyContinue) {
                    Get-LocalCursorAuthState -DbPath $gsPath
                } else { $null }
                $authComplete = if ($authState) { [bool]$authState.Complete } else { Test-LocalCursorAuthComplete -DbPath $gsPath }
                $stampCurrent = $false
                $authNeedsRefresh = $false
                $stampCheck = $null
                if (-not $script:ForceCursorAuthSync -and -not $script:PostTunnelRecovery -and $authComplete -and
                    (Get-Command Test-CursorAuthStampCurrent -ErrorAction SilentlyContinue)) {
                    # Stamp-first: one SSH fetch of exported-at. When it already matches the local
                    # golden-synced-at stamp and auth is complete, the heavier Test-CursorAuthNeedsRefresh
                    # (which does 2 more SSH round trips for machineid + exported-at) is redundant.
                    $stampCheck = Test-CursorAuthStampCurrent -DbPath $gsPath -Alias $Alias
                    $stampCurrent = [bool]$stampCheck.Current
                    Write-ConnectLog "AUTH_DECISION stamp_check current=$stampCurrent synced_at=$($stampCheck.SyncedAt) golden_exported_at=$($stampCheck.GoldenExportedAt)" 'DEBUG'
                }
                if ($stampCurrent) {
                    Write-ConnectLog 'AUTH_DECISION stamp_first_skip_needs_refresh_check' 'DEBUG'
                } elseif ($authComplete -and $stampCheck -and $stampCheck.SyncedAt -and $stampCheck.GoldenExportedAt -and ($stampCheck.SyncedAt -ne $stampCheck.GoldenExportedAt)) {
                    # Stamp check already proved authoritative mismatch (both stamps non-empty) - skip the
                    # redundant Test-CursorAuthNeedsRefresh SSH round trips (machineid + duplicate exported-at).
                    # Sync still runs afterward (authNeedsRefresh=true below) - stamp mismatch NEVER skips Sync.
                    $authNeedsRefresh = $true
                    Write-ConnectLog "AUTH_DECISION stamp_mismatch_skip_needs_refresh_check reason=golden_stale synced_at=$($stampCheck.SyncedAt) golden_exported_at=$($stampCheck.GoldenExportedAt)" 'DEBUG'
                } elseif (Get-Command Test-CursorAuthNeedsRefresh -ErrorAction SilentlyContinue) {
                    $refreshCheck = Test-CursorAuthNeedsRefresh -DbPath $gsPath -AuthComplete $authComplete
                    $authNeedsRefresh = [bool]$refreshCheck.NeedsRefresh
                    if ($authNeedsRefresh -and $refreshCheck.Reasons.Count -gt 0) {
                        Write-ConnectLog "AUTH_DECISION needs_refresh reason=$($refreshCheck.Reasons -join ',')" 'DEBUG'
                    }
                }
                $skipAuth = $false
                if (-not $script:ForceCursorAuthSync -and -not $script:PostTunnelRecovery -and -not $authNeedsRefresh) {
                    if ($stampCurrent) { $skipAuth = $true }
                    elseif ($cursorRunning -and $authComplete) { $skipAuth = $true }
                }
                Write-ConnectLog "AUTH_DECISION skip=$skipAuth force=$($script:ForceCursorAuthSync) post_recovery=$($script:PostTunnelRecovery) cursor_running=$cursorRunning auth_complete=$authComplete stamp_current=$stampCurrent"
                # Skip process enum when auth sync itself is skipped (stamp current / editor open).
                if (-not $skipAuth -and (Get-Command Test-PersonalCursorDominant -ErrorAction SilentlyContinue)) {
                    if (Test-PersonalCursorDominant) {
                        # Console decluttered on user request (2026-07-24) - full detail stays in
                        # the day log for diagnosis; not actionable enough mid-session to warrant
                        # an inline console interruption every time it happens.
                        Write-ConnectLog 'AUTH_WARN personal_cursor_dominant' 'WARN'
                    }
                }
                if ($skipAuth) {
                    # Outer skip still heals machineid - lightweight, local SQLite only, no SSH/scp.
                    if (Get-Command Heal-CursorProfileMachineIdFromLocal -ErrorAction SilentlyContinue) {
                        $null = Heal-CursorProfileMachineIdFromLocal -DbPath $gsPath -KnownState $authState
                    }
                    if ($cursorRunning) {
                        StepOk 'skipped (editor open)'
                        $script:LastAuthDetail = 'skipped editor open'
                    } else {
                        StepOk 'skipped (stamp current)'
                        $script:LastAuthDetail = 'skipped stamp current'
                    }
                } else {
                    $authSync = Sync-CursorGoldenAuth -Alias $Alias -Force:$script:ForceCursorAuthSync
                    if ($authSync.Skipped) {
                        if ($authSync.AlreadyComplete) {
                            StepOk 'already ok'
                            $script:LastAuthDetail = 'already ok'
                            if ($script:ForceCursorAuthSync) { $script:ForceCursorAuthSync = $false }
                            if ($authNeedsRefresh) { $authRelaunch = $true }
                        }
                        else {
                            $why = [string]($authSync.Reason)
                            if (-not $why) { $why = 'unknown' }
                            # Green "skipped" hid real failures (golden_missing_cached) -> login prompt.
                            if ($why -match 'golden_missing|golden_read_failed') {
                                StepFail $why
                                $script:LastAuthDetail = "fail $why"
                                Warn "Cursor auth not synced ($why) - login may be required. Reconnect after admin fixes golden, or press O after login."
                            } else {
                                StepOk ("skipped ($why)")
                                $script:LastAuthDetail = "skipped $why"
                            }
                        }
                    }
                    elseif ($authSync.Ok) {
                        StepOk
                        $script:LastAuthDetail = 'ok'
                        $script:ForceCursorAuthSync = $false
                        $authRelaunch = $true
                        Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'cursor-auth.ok')) -Value (Get-Date -Format 'o') -Encoding ASCII | Out-Null
                    }
                    elseif ($authSync.TokensOnly) {
                        StepOk 'tokens only'
                        $script:LastAuthDetail = 'tokens only'
                        $authRelaunch = $true
                        Warn 'Partial auth on laptop - reconnect, or ask admin to run: sudo claude-server sync-cursor-auth'
                    }
                    elseif ($authSync.SqliteMissing) {
                        StepFail 'sqlite not available on laptop'
                        $script:LastAuthDetail = 'sqlite missing'
                        Warn 'Windows winsqlite3.dll or sqlite3.dll is required for auth merge'
                    }
                    elseif ($authSync.MergeFailed) {
                        StepFail 'could not merge server auth'
                        $script:LastAuthDetail = 'merge failed'
                        Warn 'Close all [Claude Server] Cursor windows and reconnect'
                    }
                    else {
                        StepFail 'could not merge server auth'
                        $script:LastAuthDetail = 'merge failed'
                        Warn 'Server auth is OK - laptop could not save it locally (reconnect or close Cursor windows)'
                    }
                }
                if (-not $onCorrectFolder -and (Get-Command Repair-CursorComposerWorkspaceBindings -ErrorAction SilentlyContinue)) {
                    $null = Repair-CursorComposerWorkspaceBindings -Alias $Alias -RemotePath $go.Path
                }
            }

            $didLaunch = $false
            $launchOk = $false
            # Heal sticky proxy front door before Cursor uses settings http.proxy=18998.
            if (Get-Command Ensure-CursorProxySidecar -ErrorAction SilentlyContinue) {
                try { [void](Ensure-CursorProxySidecar) } catch {}
            }
            if ($null -ne $script:LastProxyHealthOk -and -not $script:LastProxyHealthOk -and $script:SocksProxyPort) {
                # One more sidecar+health attempt after mount work (tunnel -L may have lagged).
                if (Get-Command Start-CursorProxySidecar -ErrorAction SilentlyContinue) {
                    try { [void](Start-CursorProxySidecar) } catch {}
                }
                if (Get-Command Test-ProxyHealth -ErrorAction SilentlyContinue) {
                    try { [void](Test-ProxyHealth) } catch {}
                }
            }
            if ($null -ne $script:LastProxyHealthOk -and -not $script:LastProxyHealthOk -and $script:SocksProxyPort) {
                # Console decluttered on user request (2026-07-24): this fires on a large
                # fraction of sessions (xray probe timing, see bug 3/4) and was pure noise by
                # then - full detail stays in the day log for diagnosis.
                Write-ConnectLog 'PROXY_HEALTH_UI warn international_path_down' 'WARN'
                if (Get-Command Clear-CursorProxySettingsSidecar -ErrorAction SilentlyContinue) {
                    try { [void](Clear-CursorProxySettingsSidecar) } catch {}
                }
            }

            # Tunnel recovery used to set force_auth -> AuthRelaunch -> soft-stop of ALL
            # ClaudeServerCursorProfile windows (profile_count=14..24). Auth merges in-place;
            # if any profile window is already open, skip relaunch entirely (VPN/tunnel flap safe).
            $profileAlreadyOpen = $false
            if ($authRelaunch -and $EditorCmd -eq 'cursor' -and (Get-Command Get-CursorProfileProcesses -ErrorAction SilentlyContinue)) {
                try { $profileAlreadyOpen = (@(Get-CursorProfileProcesses).Count -gt 0) } catch { $profileAlreadyOpen = $false }
            }
            # Preserve existing windows ONLY when we are already on the target folder (a pure auth
            # refresh after a tunnel flap - nothing new to open). If the target project folder is
            # NOT open yet, we MUST still open it: this branch used to swallow a FRESH project pick
            # whenever ANY profile window was open + auth was re-synced (e.g. daily golden refresh),
            # leaving CURSOR_NOT_OPEN with no launch attempt (live repro 2026-07-25, project=deploy
            # while 25 other-project windows were open). Launch-RemoteEditor never kills on
            # AuthRelaunch and opens a --new-window, so opening the picked project does not disturb
            # the other windows.
            $skipForPreserve = ($authRelaunch -and $profileAlreadyOpen -and $onCorrectFolder)
            if ($skipForPreserve) {
                Write-ConnectLog 'EDITOR_LAUNCH skip_auth_relaunch reason=profile_windows_open_preserve_after_tunnel_recovery' 'WARN'
                $launchOk = $true
            }
            if ($authRelaunch -and $profileAlreadyOpen -and -not $onCorrectFolder) {
                Write-ConnectLog 'EDITOR_LAUNCH new_project_new_window despite_profile_windows_open reason=target_folder_not_open' 'INFO'
            }
            if ((-not $skipForPreserve) -and ($authRelaunch -or (-not $editorOpened -and -not $onCorrectFolder))) {
                if ($authRelaunch -and $onCorrectFolder) {
                    Step "Reloading $EditorName (auth refresh)"
                    Write-ConnectLog 'EDITOR_LAUNCH auth_relaunch despite already_on_folder' 'INFO'
                } elseif (-not $editorOpened) {
                    Step "Opening $EditorName"
                }
                if ($authRelaunch -or -not $editorOpened) {
                    $launchOk = [bool](Launch-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -AuthRelaunch:$authRelaunch -KnownOnFolder:$onCorrectFolder)
                    if (-not $launchOk) {
                        StepFail "$EditorName did not open the project folder. Press O to retry (resets server Cursor profile windows if stuck), or open Cursor with ClaudeServerCursorProfile."
                        # Opening failed: drop sticky editor-open so session does not pretend Cursor is up.
                        # Keep sticky only when a window is still proven open (user may retry with O).
                        $windowOpenInit = $false
                        if (Get-Command Test-RemoteEditorWindowOpen -ErrorAction SilentlyContinue) {
                            try {
                                $windowOpenInit = [bool](Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path)
                            } catch { $windowOpenInit = $false }
                        }
                        if (-not $windowOpenInit) {
                            $script:EditorSeenOpen = $false
                            $script:EditorOpened = $false
                            $editorOpened = $false
                            Write-ConnectLog 'EDITOR_SEEN_CLEAR reason=opening_step_fail' 'INFO'
                        }
                    } elseif (Get-Command Confirm-RemoteEditorLaunchVisible -ErrorAction SilentlyContinue) {
                        if (-not (Confirm-RemoteEditorLaunchVisible -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path)) {
                            StepFail "elevated launch failed - no $EditorName window (try non-elevated Connect or check $EditorName install)"
                        } else {
                            StepOk $($go.Path)
                            $didLaunch = $true
                            if ($EditorCmd -eq 'cursor') {
                                Write-Host '      -> Server profile [Claude Server] - personal Cursor is separate' -ForegroundColor DarkGray
                            } elseif ($EditorCmd -eq 'code') {
                                Write-Host '      -> Server profile [Claude Server Code] - personal VS Code is separate' -ForegroundColor DarkGray
                            }
                        }
                    } else {
                        StepOk $($go.Path)
                        $didLaunch = $true
                        if ($EditorCmd -eq 'cursor') {
                            Write-Host '      -> Server profile [Claude Server] - personal Cursor is separate' -ForegroundColor DarkGray
                        } elseif ($EditorCmd -eq 'code') {
                            Write-Host '      -> Server profile [Claude Server Code] - personal VS Code is separate' -ForegroundColor DarkGray
                        }
                    }
                }
            } elseif ($onCorrectFolder) {
                Write-ConnectLog 'EDITOR_LAUNCH_SKIP reason=known_on_folder'
            }
            if ($didLaunch -and $launchOk) {
                # Trust path: the launch already confirmed the correct folder/window - do NOT
                # re-probe (possibly stale-cache) state here, which was causing a false
                # "not on target folder" relaunch (double launch) right after a successful open.
                $onFolderNow = $true
                Write-ConnectLog 'SESSION: trusting launch result (didLaunch+launchOk) - skip relaunch check' 'DEBUG'
            } else {
                $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                if (-not $onFolderNow -and -not $didLaunch -and (Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path)) {
                    Write-ConnectLog 'SESSION: cursor not on target folder - relaunching with new-window' 'WARN'
                    Warn 'Cursor is on Agent/home - reopening project folder...'
                    if (Launch-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path) {
                        $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    }
                }
            }
            if ($onFolderNow) {
                $editorOpened = $true
                $script:EditorOpened = $true
                $script:EditorSeenOpen = $true
            } else {
                $windowOpenInit = $false
                if (Get-Command Test-RemoteEditorWindowOpen -ErrorAction SilentlyContinue) {
                    try {
                        $windowOpenInit = [bool](Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path)
                    } catch { $windowOpenInit = $false }
                }
                $editorOpened = $false
                $script:EditorOpened = $false
                if (-not $windowOpenInit) {
                    if ($script:EditorSeenOpen) {
                        Write-ConnectLog 'EDITOR_SEEN_CLEAR reason=editor_closed phase=session_open' 'INFO'
                    }
                    $script:EditorSeenOpen = $false
                }
            }

            $sessionExtras = @()
            if ($EditorCmd -eq 'cursor') {
                if ($script:LastAuthDetail -match '^(ok|tokens only)$') {
                    $sessionExtras += 'Chat: Developer -> Reload Window if messages fail'
                }
            }
            if ($script:ConnectLogPath) {
                $sessionExtras += "Log: $($script:ConnectLogPath)"
            }
            Write-SessionBox -ExtraLines $sessionExtras
            Set-ConnectTitle ('Claude Connect | {0} | {1}' -f $go.Id, (Get-GitModeLabel))

            $authOkForDiag = ($script:LastAuthDetail -match '^(ok|already ok|skipped|tokens only|n/a)$')
            $diagSw = [System.Diagnostics.Stopwatch]::StartNew()
            $null = Write-SessionDiagnosticReport -Phase 'SESSION_OPEN' -MountOk $mountOk -MountOut $mountOut `
                -OnFolder $onFolderNow -DidLaunch $didLaunch -AuthOk $authOkForDiag `
                -AuthDetail $script:LastAuthDetail -ProjectId $go.Id -RemotePath $go.Path `
                -EditorCmd $EditorCmd -EditorName $EditorName
            $diagSw.Stop()
            if ($script:ConnectPerf) { $script:ConnectPerf.DiagMs = [int]$diagSw.ElapsedMilliseconds }
            if (Get-Command Write-ConnectSessionOpenSummary -ErrorAction SilentlyContinue) {
                Write-ConnectSessionOpenSummary
            }
            if (Get-Command Write-ConnectScorecard -ErrorAction SilentlyContinue) {
                Write-ConnectScorecard -Phase 'boot'
            }
            Complete-PostTunnelRecovery -MountOk $mountOk -AuthDetail $script:LastAuthDetail `
                -ProjectId $go.Id -RemotePath $go.Path -EditorCmd $EditorCmd -EditorName $EditorName `
                -OnFolder $onFolderNow -DidLaunch $didLaunch

            while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }

            $action = ''
            $gotKey = $false
            $lastStatusAt = [DateTime]::MinValue
            $script:lastToastAt = $null
            $tunnelSyncOk = $true
                        $lastEditorCheckAt = [DateTime]::MinValue
            $lastWmcpMaintainAt = [DateTime]::MinValue
            $onFolderNow = $editorOpened
            $editorLabel = if ($editorOpened) { $EditorName } else { 'closed' }
            $script:EditorClosedPollStreak = 0
            while ($true) {
                # Sync is authoritative (reattach + probe). Do NOT call Test-TunnelUp every tick.
                $tunnelSyncOk = [bool](Sync-SessionTunnelProcess -BgTunnel ([ref]$bgTunnel))
                if (-not $tunnelSyncOk) { break }
                # Keep windows-mcp forward alive without touching the reverse tunnel /
                # Cursor session. Every 3 min: listen + sync + HTTP probe (fail-soft).
                if ((Get-Date) - $lastWmcpMaintainAt -gt [TimeSpan]::FromMinutes(3)) {
                    $lastWmcpMaintainAt = Get-Date
                    try {
                        if (Get-Command Maintain-WindowsMcpSession -ErrorAction SilentlyContinue) {
                            [void](Maintain-WindowsMcpSession)
                        }
                    } catch {
                        if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
                            Write-ConnectLog ("WINDOWS_MCP: maintain_failed {0}" -f $_.Exception.Message) 'WARN'
                        }
                    }
                }
                # Editor CIM queries are expensive - at most every 2s (was every 200ms).
                if ($EditorCmd -eq 'cursor' -and ((Get-Date) - $lastEditorCheckAt -gt [TimeSpan]::FromSeconds(2))) {
                    # WS5: single-pass presence query (was two separate CIM walks: OnFolder + WindowOpen).
                    if (Get-Command Get-RemoteEditorSessionPresence -ErrorAction SilentlyContinue) {
                        $presence = Get-RemoteEditorSessionPresence -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    } else {
                        $presence = [pscustomobject]@{
                            OnFolder   = (Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path)
                            WindowOpen = (Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path)
                        }
                    }
                    $onFolderNow = [bool]$presence.OnFolder
                    $windowOpen = [bool]$presence.WindowOpen
                    if ($onFolderNow) {
                        $editorOpened = $true
                        $script:EditorOpened = $editorOpened
                        $script:EditorSeenOpen = $true
                        $script:EditorClosedPollStreak = 0
                        $script:AgentHomeStreak = 0
                    } elseif ($windowOpen) {
                        $editorOpened = $false
                        $script:EditorOpened = $editorOpened
                        $script:EditorClosedPollStreak = 0
                        # Auto-recover ONLY when Cursor is genuinely on Agent/home.
                        # Folder detection often flaps for ~15-30s after a successful open
                        # (title/cmdline lag while Remote-SSH settles). Counting any
                        # !onFolder && windowOpen as agent-home caused a second
                        # Launch-RemoteEditor (double Cursor window). Gate on
                        # Test-RemoteEditorInAgentHome; otherwise reset streak.
                        $reallyAgentHome = $false
                        if (Get-Command Test-RemoteEditorInAgentHome -ErrorAction SilentlyContinue) {
                            try { $reallyAgentHome = [bool](Test-RemoteEditorInAgentHome -RemotePath $go.Path) } catch { $reallyAgentHome = $false }
                        }
                        if (-not $reallyAgentHome) {
                            $script:AgentHomeStreak = 0
                        } else {
                            if (-not $script:AgentHomeStreak) { $script:AgentHomeStreak = 0 }
                            $script:AgentHomeStreak++
                            if ($script:AgentHomeStreak -ge 3 -and -not $script:AutoRelaunchAttempted) {
                                # Settings-focused Cursor lacks folder-uri titles - do not auto_relaunch.
                                $settingsFocused = $false
                                try {
                                    if (Get-Command Get-CursorMainProfileProcesses -ErrorAction SilentlyContinue) {
                                        foreach ($p in @(Get-CursorMainProfileProcesses)) {
                                            $title = ''
                                            try { $title = [string]$p.MainWindowTitle } catch { $title = '' }
                                            if ($title -match '(?i)settings') { $settingsFocused = $true; break }
                                        }
                                    }
                                } catch { $settingsFocused = $false }
                                if ($settingsFocused) {
                                    Write-ConnectLog 'SESSION: auto_relaunch_skip reason=cursor_settings' 'INFO'
                                } else {
                                    $script:AutoRelaunchAttempted = $true
                                    Write-ConnectLog "SESSION: auto_relaunch agent_home_streak=$($script:AgentHomeStreak) - reopening project folder" 'WARN'
                                    Warn 'Cursor drifted to Agent/home - reopening project folder automatically...'
                                    if (Launch-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path) {
                                        $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                                        if ($onFolderNow) {
                                            $editorOpened = $true
                                            $script:EditorOpened = $editorOpened
                                            $script:EditorSeenOpen = $true
                                            $script:AgentHomeStreak = 0
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        # Debounce: require 2 consecutive "closed" polls before clearing EditorSeenOpen
                        # / reporting closed - avoids a single stale/slow CIM read flipping status.
                        $script:EditorClosedPollStreak++
                        if ($script:EditorClosedPollStreak -ge 2) {
                            $editorOpened = $false
                            $script:EditorOpened = $editorOpened
                            if ($script:EditorSeenOpen) {
                                Write-ConnectLog 'EDITOR_SEEN_CLEAR reason=editor_closed phase=session_poll' 'INFO'
                            }
                            $script:EditorSeenOpen = $false
                        }
                    }
                    $editorLabel = if ($onFolderNow) { $EditorName } elseif ($windowOpen) { 'agent' } elseif ($script:EditorClosedPollStreak -ge 2) { 'closed' } else { $editorLabel }
                    $script:LastEditorPresence = [pscustomobject]@{ OnFolder = $onFolderNow; WindowOpen = $windowOpen; Label = $editorLabel; At = Get-Date }
                    $lastEditorCheckAt = Get-Date
                } elseif ($EditorCmd -ne 'cursor') {
                    $onFolderNow = $editorOpened
                    $editorLabel = ''
                }
                if ((Get-Date) - $lastStatusAt -gt [TimeSpan]::FromSeconds(30)) {
                    Update-SessionStatusLine -ProjectLabel $go.Id -GitLabel (Get-GitModeLabel) -TunnelOk $tunnelSyncOk `
                        -EditorOpen $onFolderNow -EditorName $EditorName -EditorLabel $editorLabel `
                        -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $lastStatusAt = Get-Date
                }
                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    $kc = $ki.KeyChar.ToString()
                    $code = if ($kc.Length -eq 1) { [int][char]$kc[0] } else { 0 }
                    $ascii = ($code -ge 32 -and $code -le 126)
                    $letter = if ($ascii) { $kc.ToLowerInvariant() } else { '' }
                    # VK fallback ONLY for null/control KeyChar - never for Persian/other printable non-ASCII (arrow glyph on Q).
                    $useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
                    $resolved = ''
                    if ($letter -eq 'r' -or ($useVk -and $ki.Key -eq [ConsoleKey]::R)) { $resolved = 'r' }
                    elseif ($letter -eq 'g' -or ($useVk -and $ki.Key -eq [ConsoleKey]::G)) { $resolved = 'g' }
                    elseif ($letter -eq 'o' -or ($useVk -and $ki.Key -eq [ConsoleKey]::O)) { $resolved = 'o' }
                    elseif ($letter -eq 'q' -or ($useVk -and $ki.Key -eq [ConsoleKey]::Q) -or $ki.Key -eq [ConsoleKey]::Enter) { $resolved = 'q' }
                    Write-ConnectDecision 'session_key' ("action={0} key={1} keychar={2} ascii={3} useVk={4}" -f $resolved, $ki.Key, $ki.KeyChar, $ascii, $useVk)
                    if (-not $resolved) {
                        Write-ConnectLog ("SESSION_KEY ignore non_command key={0} keychar={1}" -f $ki.Key, $ki.KeyChar) 'INFO'
                        continue
                    }
                    $action = $resolved
                    $gotKey = $true
                    break
                }
                Start-Sleep -Milliseconds 800
            }
            if (-not $gotKey -and -not $tunnelSyncOk) {
                if (-not $script:lastToastAt -or ((Get-Date) - $script:lastToastAt).TotalSeconds -gt 60) {
                    Set-ConnectTitle 'Claude Connect - reconnecting...'
                    Show-ConnectToast 'Tunnel dropped - reconnecting...'
                    $script:lastToastAt = Get-Date
                }
                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    $kc = $ki.KeyChar.ToString()
                    $code = if ($kc.Length -eq 1) { [int][char]$kc[0] } else { 0 }
                    $ascii = ($code -ge 32 -and $code -le 126)
                    $letter = if ($ascii) { $kc.ToLowerInvariant() } else { '' }
                    $useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
                    if ($letter -eq 'r' -or ($useVk -and $ki.Key -eq [ConsoleKey]::R)) { $action = 'r' }
                    elseif ($letter -eq 'q' -or ($useVk -and $ki.Key -eq [ConsoleKey]::Q) -or $ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }
                    else {
                        Write-ConnectLog ("SESSION_KEY ignore non_command(during_drop) key={0} keychar={1}" -f $ki.Key, $ki.KeyChar) 'INFO'
                    }
                } else {
                    $action = 'r'
                    $bgPid = 0
                    if ($bgTunnel -and -not $bgTunnel.HasExited) { $bgPid = [int]$bgTunnel.Id }
                    if (Get-Command Write-TunnelDropLog -ErrorAction SilentlyContinue) {
                        Write-TunnelDropLog -Reason 'auto_reconnect' -TunnelSyncOk:$tunnelSyncOk -ProjectId $go.Id `
                            -EditorOpened:$editorOpened -EditorSeen:$script:EditorSeenOpen -RecoveryGen $script:RecoveryGeneration -TunnelPid $bgPid
                    } else {
                        Write-ConnectLog ("TUNNEL_DROP reason=auto_reconnect tunnel_sync_ok={0} project={1} editor_opened={2} editor_seen={3} gen={4}" -f $tunnelSyncOk, $go.Id, $editorOpened, $script:EditorSeenOpen, $script:RecoveryGeneration) 'WARN'
                    }
                    Write-Host "    Connection dropped - reconnecting..." -ForegroundColor Yellow
                }
            }

            if (-not $tunnelSyncOk -and $action -eq '') {
                Write-ConnectLog 'SESSION: fallthrough_recover reason=tunnel_down_empty_action' 'WARN'
                $action = 'r'
            }

            if ($action -eq 'g') {
                Configure-GitMode
                continue sessionLoop
            }

            if ($action -eq 'o') {
                $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                if (-not $onFolderNow) {
                    Write-Host ''
                    Step "Reopening $EditorName"
                    if (-not (Launch-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path)) {
                        StepFail "$EditorName did not open the project folder. Press O to retry (resets server Cursor profile windows if stuck), or open Cursor with ClaudeServerCursorProfile."
                        $windowOpenRetry = $false
                        if (Get-Command Test-RemoteEditorWindowOpen -ErrorAction SilentlyContinue) {
                            try {
                                $windowOpenRetry = [bool](Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path)
                            } catch { $windowOpenRetry = $false }
                        }
                        if (-not $windowOpenRetry) {
                            $script:EditorSeenOpen = $false
                            $script:EditorOpened = $false
                            $editorOpened = $false
                            Write-ConnectLog 'EDITOR_SEEN_CLEAR reason=opening_step_fail' 'INFO'
                        }
                    } elseif (Get-Command Confirm-RemoteEditorLaunchVisible -ErrorAction SilentlyContinue) {
                        if (-not (Confirm-RemoteEditorLaunchVisible -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path)) {
                            StepFail "elevated launch failed - no $EditorName window (try non-elevated Connect or check $EditorName install)"
                        } else {
                            StepOk $go.Path
                            $editorOpened = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                            $script:EditorOpened = $editorOpened
                            if ($editorOpened) { $script:EditorSeenOpen = $true }
                        }
                    } else {
                        StepOk $go.Path
                        $editorOpened = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                        $script:EditorOpened = $editorOpened
                        if ($editorOpened) { $script:EditorSeenOpen = $true }
                    }
                    Write-Host ''
                }
                continue sessionLoop
            }

            if ($action -eq 'r') {
                if ($gotKey) {
                    Begin-ConnectRecovery -Trigger 'manual' -ProjectId $go.Id -EditorWasOpen $editorOpened
                    $script:EditorSeenOpen = $false
                    $editorOpened = $false
                    $script:EditorOpened = $editorOpened
                    $script:LaptopSshVerified = $false
                    $alreadyDown = $false
                    Write-Host ''
                    Write-Host '    Reconnecting...' -ForegroundColor Cyan
                    Write-Host ''
                    continue sessionLoop
                }
                $skipRecoveryClear = $false
                # Stage 4: presence API (WindowOpen without requiring on-folder). Do NOT use
                # Test-RemoteEditorWindowOpen here - that helper is auth-gated to on-folder only.
                if (Get-Command Get-RemoteEditorSessionPresence -ErrorAction SilentlyContinue) {
                    try {
                        $presence = Get-RemoteEditorSessionPresence -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                        if ($presence.OnFolder) {
                            $skipRecoveryClear = $true
                            $editorOpened = $true
                            $script:EditorOpened = $editorOpened
                            $script:EditorSeenOpen = $true
                        } elseif ($presence.WindowOpen) {
                            # Window open but not on folder: preserve mount, do not fake on-folder.
                            $skipRecoveryClear = $true
                            $editorOpened = $false
                            $script:EditorOpened = $editorOpened
                            Write-ConnectLog 'RECOVERY_SKIP_CLEAR_MOUNT reason=editor_window_open_not_on_folder' 'INFO'
                        } else {
                            if ($script:EditorSeenOpen) {
                                Write-ConnectLog 'EDITOR_SEEN_CLEAR reason=editor_closed phase=auto_recovery' 'INFO'
                            }
                            $script:EditorSeenOpen = $false
                            $editorOpened = $false
                            $script:EditorOpened = $editorOpened
                        }
                    } catch {
                        # Transient CIM failure: keep prior sticky only if still marked; do not force editorOpened.
                        if ($script:EditorSeenOpen) {
                            $skipRecoveryClear = $true
                            Write-ConnectLog 'RECOVERY_SKIP_CLEAR_MOUNT reason=editor_check_failed_sticky' 'WARN'
                        }
                        Write-ConnectLog "RECOVERY_EDITOR_CHECK_FAILED error=$($_.Exception.Message)" 'WARN'
                    }
                } elseif ($editorOpened) {
                    $skipRecoveryClear = $true
                }
                Begin-ConnectRecovery -Trigger 'auto' -ProjectId $go.Id -EditorWasOpen $skipRecoveryClear
                Write-Host '    Connection dropped - recovering...' -ForegroundColor Yellow
                if ($skipRecoveryClear) {
                    # Keep EditorSeenOpen if already set by on-folder/window checks; never force editorOpened from sticky alone.
                    if ($editorOpened) { $script:EditorSeenOpen = $true }
                    try {
                        $null = Initialize-SessionBgTunnel -Alias $Alias -SshCfgPath $sshCfg -Quiet
                        if ($script:SessionBgTunnel) { $bgTunnel = $script:SessionBgTunnel }
                    } catch {
                        Write-ConnectLog "RECOVERY_REENSURE_FAILED error=$($_.Exception.Message)" 'WARN'
                    }
                    Write-ConnectLog 'RECOVERY_SKIP_CLEAR_MOUNT reason=editor_open' 'WARN'
                    Write-ConnectLog 'TUNNEL: recovering session (preserve mount, re-ensure tunnel)' 'WARN'
                    $alreadyDown = $false
                } else {
                    $editorOpened = $false
                    $script:EditorOpened = $editorOpened
                    Write-ConnectLog 'TUNNEL: recovering session (down mount, restart tunnel)' 'WARN'
                    Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -Reason 'auto_recovery'
                    Stop-SessionTunnelCleanup -BgTunnel ([ref]$bgTunnel) -ClearServerForward
                    $alreadyDown = $true
                }
                $script:LaptopSshVerified = $false
                Write-Host ''
                continue sessionLoop
            }

            if ($action -eq 'q') {
                # Explicit quit only (never fall through from ignored Persian keys / empty action).
                $script:EditorSeenOpen = $false
                $editorOpened = $false
                $script:EditorOpened = $editorOpened
                Write-Host ""
                Write-Host "    Disconnecting..." -ForegroundColor DarkGray
                Write-ConnectLog "SESSION: disconnect project=$($go.Id) reason=user_quit"
                Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -Reason 'user_quit'
                Stop-SessionTunnelCleanup -BgTunnel ([ref]$bgTunnel) -ClearServerForward
                $alreadyDown = $true
                Write-Host "    Laptop folder restored." -ForegroundColor Green
                break sessionLoop
            }

            Write-ConnectLog ("SESSION: ignore_empty_action gotKey={0} tunnel={1}" -f $gotKey, $tunnelSyncOk) 'WARN'
            continue sessionLoop
        }
    } finally {
        # Explicit Q already performed cleanup and must retain its clear + stop behavior.
        $keepTunnelForEditor = $false
        if (-not $alreadyDown) {
            $keepTunnelForEditor = $false
            if (Get-Command Test-RemoteEditorOnCorrectFolder -ErrorAction SilentlyContinue) {
                try {
                    if (Test-RemoteEditorOnCorrectFolder `
                        -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path) {
                        $keepTunnelForEditor = $true
                        $editorOpened = $true
                        $script:EditorOpened = $editorOpened
                        $script:EditorSeenOpen = $true
                    } else {
                        $windowStillOpen = $false
                        if (Get-Command Test-RemoteEditorWindowOpen -ErrorAction SilentlyContinue) {
                            $windowStillOpen = [bool](Test-RemoteEditorWindowOpen `
                                -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path)
                        }
                        if ($windowStillOpen) {
                            $keepTunnelForEditor = $true
                            $editorOpened = $false
                            $script:EditorOpened = $editorOpened
                            Write-ConnectLog 'FINALLY_KEEP_TUNNEL reason=editor_window_open' 'INFO'
                        } else {
                            if ($script:EditorSeenOpen) {
                                Write-ConnectLog 'EDITOR_SEEN_CLEAR reason=editor_closed phase=finally' 'INFO'
                            }
                            $script:EditorSeenOpen = $false
                            $editorOpened = $false
                            $script:EditorOpened = $editorOpened
                            $keepTunnelForEditor = $false
                        }
                    }
                } catch {
                    if ($script:EditorSeenOpen) {
                        $keepTunnelForEditor = $true
                        Write-ConnectLog 'FINALLY_KEEP_TUNNEL reason=editor_check_failed_sticky' 'WARN'
                    }
                    Write-ConnectLog "FINALLY_EDITOR_CHECK_FAILED error=$($_.Exception.Message)" 'WARN'
                }
            } else {
                $keepTunnelForEditor = [bool]$editorOpened
            }
        }
        if ($keepTunnelForEditor) {
            Write-ConnectLog 'FINALLY_KEEP_TUNNEL reason=editor_open' 'WARN'
            # Bug 5 fix: without this, Windows auto-closes our un-inherited KILL_ON_JOB_CLOSE job
            # handle the instant THIS process exits normally (right after this finally block),
            # killing the tunnel (and every sidecar job sibling) anyway despite deliberately
            # skipping Stop-SessionTunnelCleanup above. Duplicate the job handle into the tunnel
            # process itself so the job (and thus every member, including sidecar relay/watchdog)
            # survives our own exit - see Detach-CursorProxySidecarJobProcess in
            # cursor-proxy-sidecar.ps1 for the exact Win32 DuplicateHandle mechanism.
            if ($bgTunnel -and (Get-Command Detach-CursorProxySidecarJobProcess -ErrorAction SilentlyContinue)) {
                try {
                    $detachOk = [bool](Detach-CursorProxySidecarJobProcess -Process $bgTunnel)
                    Write-ConnectLog ("FINALLY_KEEP_TUNNEL detach_from_job ok={0}" -f [int]$detachOk) 'INFO'
                } catch {
                    Write-ConnectLog ("FINALLY_KEEP_TUNNEL detach_from_job_fail err={0}" -f $_.Exception.Message) 'WARN'
                }
            }
        } else {
            if (-not $alreadyDown) {
                Write-Host ""
                Write-Host "    Disconnecting..." -ForegroundColor DarkGray
                if (Get-Command Write-ConnectScorecard -ErrorAction SilentlyContinue) { Write-ConnectScorecard -Phase 'end' }
                Clear-SessionMount -ProjectId $go.Id -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path -Reason 'session_end'
                Write-Host "    Laptop folder restored." -ForegroundColor Green
                Write-Host ""
            }
            Stop-SessionTunnelCleanup -BgTunnel ([ref]$bgTunnel) -ClearServerForward
            # Clean disconnect only (never when keepTunnelForEditor - editor still needs the
            # sidecar proxy). Stop the watchdog before the relays so it cannot immediately
            # respawn a relay we are about to kill.
            if (Get-Command Stop-CursorProxySidecarWatchdog -ErrorAction SilentlyContinue) {
                try { Stop-CursorProxySidecarWatchdog } catch {}
            }
            if (Get-Command Stop-CursorProxySidecarRelays -ErrorAction SilentlyContinue) {
                try { Stop-CursorProxySidecarRelays } catch {}
            }
        }
    }

    while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }

    $postKey = Read-PostDisconnectKey -DefaultChar M -TimeoutSec 10
    switch ($postKey) {
        'm' {
            Write-Host '    Back to project menu...' -ForegroundColor Green
            $editorOpened = $false
            $script:EditorOpened = $editorOpened
            $null = Initialize-SessionBgTunnel -Alias $Alias -SshCfgPath $sshCfg -Quiet
            Start-Sleep -Seconds 1
            Write-Host ''
            break mainLoop
        }
        'c' {
            Write-Host '    Reconnecting...' -ForegroundColor Green
            $editorOpened = $false
            $script:EditorOpened = $editorOpened
            Start-Sleep -Seconds 1
            Write-Host ''
            continue mainLoop
        }
        default {
            Write-Host '    Exiting...' -ForegroundColor DarkGray
            $exitRequested = $true
            break mainLoop
        }
    }

    } # end :mainLoop
} # end :menuLoop
Write-Host ''
Close-ConnectLog




