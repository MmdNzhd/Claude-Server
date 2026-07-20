$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'

function Set-Lf([string]$Path, [string]$Text) {
    $Text = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    [IO.File]::WriteAllText($Path, $Text)
}

# ========== connect-ui.ps1 ==========
$ui = Join-Path $root 'scripts\client\connect-ui.ps1'
$uiRaw = [IO.File]::ReadAllText($ui)

$oldInit = @'
function Initialize-ConnectLog {
    param(
        [Parameter(Mandatory)][string]$ScriptDir,
        [string]$Version = ''
    )
    # Durable logs live on the server only (~/.claude/logs). Laptop uses a TEMP buffer.
    $script:ConnectLogSyncOffset = 0
    try {
        $legacy = Join-Path $ScriptDir 'connect.log'
        if (Test-Path -LiteralPath $legacy) { Remove-Item -LiteralPath $legacy -Force -ErrorAction SilentlyContinue }
        $legacy1 = Join-Path $ScriptDir 'connect.log.1'
        if (Test-Path -LiteralPath $legacy1) { Remove-Item -LiteralPath $legacy1 -Force -ErrorAction SilentlyContinue }
    } catch { }
    $tmpRoot = $env:TEMP
    if (-not $tmpRoot) { $tmpRoot = $env:TMP }
    if (-not $tmpRoot) { $tmpRoot = [System.IO.Path]::GetTempPath() }
    $script:ConnectLogPath = Join-Path $tmpRoot ("claude-connect-{0}.log" -f $PID)
    try {
        $script:ConnectLogWriter = [System.IO.StreamWriter]::new(
            $script:ConnectLogPath, $false, [System.Text.UTF8Encoding]::new($false))
        $script:ConnectLogWriter.AutoFlush = $true
    } catch {
        $script:ConnectLogWriter = $null
        return
    }
    $elev = 'unknown'
    if (Get-Command Test-IsElevatedShell -ErrorAction SilentlyContinue) {
        $elev = if (Test-IsElevatedShell) { 'yes' } else { 'no' }
    }
    Write-ConnectLog "======== session start v$Version user=$env:USERNAME elevated=$elev pid=$PID ========"
    Write-ConnectLog "log sink: server:~/.claude/logs/ (temp buffer only on laptop)"
    Write-ConnectLog "script_dir: $ScriptDir connect_version: $Version" 'DEBUG'
}
'@

$newInit = @'
function Get-ConnectLogDir {
    $dir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch { }
    return $dir
}

function Get-ConnectLogDayPath {
    $day = Get-Date -Format 'yyyyMMdd'
    return (Join-Path (Get-ConnectLogDir) ("connect-{0}.log" -f $day))
}

function Initialize-ConnectLog {
    param(
        [Parameter(Mandatory)][string]$ScriptDir,
        [string]$Version = ''
    )
    # Durable on laptop AND server. Temp-only was losing all logs when SSH/update failed
    # (Farzad empty ~/.claude/logs). Always append local day file; sync new bytes to server.
    try {
        $legacy = Join-Path $ScriptDir 'connect.log'
        if (Test-Path -LiteralPath $legacy) { Remove-Item -LiteralPath $legacy -Force -ErrorAction SilentlyContinue }
        $legacy1 = Join-Path $ScriptDir 'connect.log.1'
        if (Test-Path -LiteralPath $legacy1) { Remove-Item -LiteralPath $legacy1 -Force -ErrorAction SilentlyContinue }
    } catch { }
    $script:ConnectLogPath = Get-ConnectLogDayPath
    $script:ConnectLogSyncOffset = 0
    try {
        if (Test-Path -LiteralPath $script:ConnectLogPath) {
            $script:ConnectLogSyncOffset = ([System.IO.FileInfo]$script:ConnectLogPath).Length
        }
        $script:ConnectLogWriter = [System.IO.StreamWriter]::new(
            $script:ConnectLogPath, $true, [System.Text.UTF8Encoding]::new($false))
        $script:ConnectLogWriter.AutoFlush = $true
    } catch {
        $script:ConnectLogWriter = $null
        return
    }
    $elev = 'unknown'
    if (Get-Command Test-IsElevatedShell -ErrorAction SilentlyContinue) {
        $elev = if (Test-IsElevatedShell) { 'yes' } else { 'no' }
    }
    Write-ConnectLog "======== session start v$Version user=$env:USERNAME elevated=$elev pid=$PID ========"
    Write-ConnectLog "log sink: local:$($script:ConnectLogPath) + server:~/.claude/logs/"
    Write-ConnectLog "script_dir: $ScriptDir connect_version: $Version" 'DEBUG'
}
'@

if ($uiRaw.IndexOf($oldInit) -lt 0) {
    # try index-based replace of function body
    $s = $uiRaw.IndexOf('function Initialize-ConnectLog')
    if ($s -lt 0) { throw 'Initialize-ConnectLog not found' }
    $e = $uiRaw.IndexOf('function Sync-ConnectLogToServer', $s)
    if ($e -lt 0) { throw 'Sync-ConnectLogToServer not found' }
    $uiRaw = $uiRaw.Substring(0, $s) + $newInit + "`n" + $uiRaw.Substring($e)
    Write-Host 'init replaced by index'
} else {
    $uiRaw = $uiRaw.Replace($oldInit, $newInit)
    Write-Host 'init exact replace'
}

# Close-ConnectLog: keep local file
$oldClose = @'
    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer }
    try {
        if ($script:ConnectLogPath -and (Test-Path -LiteralPath $script:ConnectLogPath)) {
            Remove-Item -LiteralPath $script:ConnectLogPath -Force -ErrorAction SilentlyContinue
        }
    } catch { }
    $script:ConnectLogPath = ''
    $script:ConnectLogSyncOffset = 0
}
'@
$newClose = @'
    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer }
    # Keep durable local day log (do not delete) so offline / failed-SSH sessions are still auditable.
    Write-Host '' # no-op keep structure
    $script:ConnectLogPath = ''
    $script:ConnectLogSyncOffset = 0
}
'@
# cleaner without Write-Host
$newClose = @'
    if (Get-Command Sync-ConnectLogToServer -ErrorAction SilentlyContinue) { Sync-ConnectLogToServer }
    # Keep durable local day log so offline / failed-SSH sessions remain auditable.
    $script:ConnectLogPath = ''
    $script:ConnectLogSyncOffset = 0
}
'@

if ($uiRaw.IndexOf($oldClose) -lt 0) { throw 'Close-ConnectLog tail not found' }
$uiRaw = $uiRaw.Replace($oldClose, $newClose)

# Retention +1 -> +7 in sync cleanup command
$uiRaw = $uiRaw.Replace('mtime +1 -delete', 'mtime +7 -delete')

[IO.File]::WriteAllText($ui, $uiRaw)
Write-Host 'connect-ui.ps1 OK'

# ========== connect-update.ps1: durable update log ==========
$cu = Join-Path $root 'scripts\client\windows\connect-update.ps1'
$cuRaw = [IO.File]::ReadAllText($cu)
if ($cuRaw -notmatch 'Write-UpdateFileLog') {
    $helper = @'

function Get-UpdateLogPath {
    $dir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch { }
    $day = Get-Date -Format 'yyyyMMdd'
    return (Join-Path $dir ("connect-{0}.log" -f $day))
}

function Write-UpdateFileLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        $line = "[$ts] [$Level] UPDATE: $Message"
        Add-Content -LiteralPath (Get-UpdateLogPath) -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

'@
    # insert after Write-UpdateMsg function - find "function Get-ConnectVersionParts"
    $idx = $cuRaw.IndexOf('function Get-ConnectVersionParts')
    if ($idx -lt 0) { throw 'Get-ConnectVersionParts missing' }
    $cuRaw = $cuRaw.Substring(0, $idx) + $helper + $cuRaw.Substring($idx)

    # Instrument main flow
    $cuRaw = $cuRaw.Replace(
        'if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { exit 0 }',
        "Write-UpdateFileLog ('start script_dir={0} local_ver={1}' -f `$ScriptDir, (Get-LocalVersion))`n" +
        'if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { Write-UpdateFileLog ''ssh missing - skip'' ''WARN''; exit 0 }')
    # Fix: Get-LocalVersion called twice before defined use - reorder
    # Actually Get-LocalVersion is defined before main. But we call it before localVer assign.
    # Better insert after $localVer =
}

# Re-read and do cleaner instrumentation of main section only
$cuRaw = [IO.File]::ReadAllText($cu)
if ($cuRaw -notmatch 'Write-UpdateFileLog') {
    $helper = @'

function Get-UpdateLogPath {
    $dir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
    try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch { }
    $day = Get-Date -Format 'yyyyMMdd'
    return (Join-Path $dir ("connect-{0}.log" -f $day))
}

function Write-UpdateFileLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        Add-Content -LiteralPath (Get-UpdateLogPath) -Value "[$ts] [$Level] UPDATE: $Message" -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

'@
    $idx = $cuRaw.IndexOf('function Get-ConnectVersionParts')
    $cuRaw = $cuRaw.Substring(0, $idx) + $helper + $cuRaw.Substring($idx)
}

# Patch main: after localVer assigned
$oldMainStart = @'
$localVer = Get-LocalVersion
if (-not $localVer) { exit 0 }
'@
$newMainStart = @'
$localVer = Get-LocalVersion
Write-UpdateFileLog ("bat_launch script_dir=$ScriptDir local_ver=$localVer")
if (-not $localVer) { Write-UpdateFileLog 'no local connect-version.txt - skip' 'WARN'; exit 0 }
'@
if ($cuRaw.IndexOf($oldMainStart) -lt 0) { throw 'localVer block missing' }
$cuRaw = $cuRaw.Replace($oldMainStart, $newMainStart)

# After Resolve-UpdateEndpoint / unreachable
if ($cuRaw -match 'Resolve-UpdateEndpoint') {
    $cuRaw = $cuRaw.Replace(
        'Write-UpdateMsg ("Client update check skipped (unreachable: {0})" -f $ep.Display) ''DarkYellow''',
        "Write-UpdateMsg (\"Client update check skipped (unreachable: {0})\" -f `$ep.Display) 'DarkYellow'`n    Write-UpdateFileLog (\"unreachable ep=`$(`$ep.Display)\") 'WARN'")
} else {
    # older pattern
    $cuRaw = $cuRaw.Replace(
        'Write-UpdateMsg ("Client update check skipped (unreachable: {0})" -f $ep.Display) ''DarkYellow''',
        "Write-UpdateMsg (\"Client update check skipped (unreachable: {0})\" -f `$ep.Display) 'DarkYellow'`n    Write-UpdateFileLog (\"unreachable ep=`$(`$ep.Display)\") 'WARN'")
}

# success paths
$cuRaw = $cuRaw.Replace(
    'Write-UpdateMsg "Client up to date (v$localVer)" ''DarkGray''',
    "Write-UpdateMsg \"Client up to date (v`$localVer)\" 'DarkGray'`n    Write-UpdateFileLog \"up_to_date v`$localVer\"`n")
$cuRaw = $cuRaw.Replace(
    'Write-UpdateMsg "Client update available: v$localVer -> v$remoteVer" ''Cyan''',
    "Write-UpdateMsg \"Client update available: v`$localVer -> v`$remoteVer\" 'Cyan'`nWrite-UpdateFileLog \"available v`$localVer -> v`$remoteVer\"")

[IO.File]::WriteAllText($cu, $cuRaw)
# parse check
$errs=$null
$null=[System.Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($cu),[ref]$null,[ref]$errs)
if($errs -and $errs.Count){ $errs|%{$_.ToString()}; throw 'connect-update parse fail' }
Write-Host 'connect-update.ps1 OK'

# ========== connect.bat bootstrap log ==========
$bat = Join-Path $root 'scripts\client\windows\connect.bat'
$batRaw = [IO.File]::ReadAllText($bat)
if ($batRaw -notmatch 'BOOTSTRAP') {
    $boot = @'
REM Log double-click immediately (before update) — durable local day log
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $d=Join-Path $env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path $d|Out-Null; $f=Join-Path $d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; Add-Content -LiteralPath $f -Value \"[$ts] [INFO] BOOTSTRAP: connect.bat start here=$env:HERE pid=$PID\" -Encoding UTF8 } catch {}" 2>nul

'@
    # HERE not set in env for powershell - use %HERE%
    $boot = @"
REM Log double-click immediately (before update) — durable local day log
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { `$d=Join-Path `$env:USERPROFILE '.config\claude-connect\logs'; New-Item -ItemType Directory -Force -Path `$d|Out-Null; `$f=Join-Path `$d ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd')); `$ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'; Add-Content -LiteralPath `$f -Value ('[{0}] [INFO] BOOTSTRAP: connect.bat start here={1}' -f `$ts, '%HERE%') -Encoding UTF8 } catch {}" 2>nul

"@
    $batRaw = $batRaw.Replace("title Claude Connect`r`n`r`n", "title Claude Connect`r`n`r`n$boot")
    if ($batRaw -notmatch 'BOOTSTRAP') {
        $batRaw = $batRaw.Replace("title Claude Connect`n`n", "title Claude Connect`n`n$boot")
    }
    if ($batRaw -notmatch 'BOOTSTRAP') { throw 'bat bootstrap insert failed' }
    [IO.File]::WriteAllText($bat, $batRaw)
    Write-Host 'connect.bat OK'
} else { Write-Host 'connect.bat already has bootstrap' }

Write-Host 'WIN PATCHES DONE'
