#Requires -Version 5.1
# connect-preflight.ps1 - quiet bootstrap, heal, and update orchestration.
# Exit 0 = continue to connect-boot (AFTER_CLIENT_UPDATE)
# Exit 2 = heal/canonical relaunch (bat HEAL_RELAUNCH)
# Exit 3 = update applied; bat should relaunch connect.bat

param(
    [Parameter(Mandatory = $true)]
    [string]$Here
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $Here.TrimEnd('\', '/')
$PowerShellExe = Join-Path $PSHOME 'powershell.exe'
$PreflightHandoff = Join-Path $env:TEMP 'claude-connect-preflight.ok'

function ConvertTo-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ('"{0}"' -f ($Value -replace '"', '\"'))
}

function Read-PreflightHandoff {
    $result = @{}
    if (-not (Test-Path -LiteralPath $PreflightHandoff)) { return $result }
    try {
        foreach ($line in Get-Content -LiteralPath $PreflightHandoff -ErrorAction Stop) {
            if ($line -match '^([^=]+)=(.*)$') { $result[$Matches[1].Trim()] = $Matches[2].Trim() }
        }
    } catch {}
    return $result
}

function Test-HealthyDeploy {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir) -or -not (Test-Path -LiteralPath $Dir)) { return $false }
    foreach ($n in @('connect.bat', 'connect.ps1', 'connect-boot.ps1', 'connect-update.ps1', 'cursor-proxy-sidecar.ps1', 'connect-version.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Dir $n))) { return $false }
    }
    try {
        $verFile = Join-Path $Dir 'connect-version.txt'
        $verTxt = (Get-Content -LiteralPath $verFile -TotalCount 1 -ErrorAction Stop).Trim()
        if (-not $verTxt) { return $false }
        $ps1 = Join-Path $Dir 'connect.ps1'
        $raw = Get-Content -LiteralPath $ps1 -Raw -ErrorAction Stop
        if ($raw -notmatch [regex]::Escape("ConnectVersion = '$verTxt'")) { return $false }
        $upd = Join-Path $Dir 'connect-update.ps1'
        $updRaw = Get-Content -LiteralPath $upd -Raw -ErrorAction Stop
        if ($updRaw -match 'UpdateEndpointTarget') { return $false }
    } catch { return $false }
    return $true
}

function Invoke-PreflightScript {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Arguments = @(),
        [switch]$Sta
    )

    $processArgs = @('-NoProfile')
    if ($Sta) { $processArgs += '-STA' }
    $processArgs += @('-ExecutionPolicy', 'Bypass', '-File', (ConvertTo-ProcessArgument -Value $Path))
    $processArgs += $Arguments

    try {
        $process = Start-Process -FilePath $PowerShellExe -ArgumentList $processArgs `
            -Wait -PassThru -WindowStyle Hidden
        if ($process) { return [int]$process.ExitCode }
    } catch {}
    return 1
}

# Prefer RUN_ID from parent connect.bat (unique per UI). Only mint if missing.
if ($env:CLAUDE_CONNECT_RUN_ID -notmatch '^[0-9a-fA-F]{12}$') {
    $env:CLAUDE_CONNECT_RUN_ID = [guid]::NewGuid().ToString('N').Substring(0, 12)
}
try {
    # Per-PID handoff avoids multi-UI races on a single shared TEMP file.
    $pidHandoff = Join-Path $env:TEMP ("claude-connect-run-id.{0}.txt" -f $PID)
    Set-Content -LiteralPath $pidHandoff -Value $env:CLAUDE_CONNECT_RUN_ID -Encoding ASCII
    # Legacy shared path: write only when file absent so a concurrent UI cannot
    # overwrite another bat's already-minted id mid-handoff.
    $sharedHandoff = Join-Path $env:TEMP 'claude-connect-run-id.txt'
    if (-not (Test-Path -LiteralPath $sharedHandoff)) {
        Set-Content -LiteralPath $sharedHandoff -Value $env:CLAUDE_CONNECT_RUN_ID -Encoding ASCII
    }
} catch {}

try {
    $logDir = Join-Path $env:USERPROFILE '.config\claude-connect\logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $logFile = Join-Path $logDir ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = '[{0}] [INFO] [{1}] BOOTSTRAP: connect.bat start here={2}' -f `
        $timestamp, $env:CLAUDE_CONNECT_RUN_ID, $Here
    [IO.File]::AppendAllText(
        $logFile,
        $line + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
} catch {}

$handoff = @{}
$bootstrapPath = Join-Path $Here 'connect-bootstrap.ps1'
if ($env:CLAUDE_CONNECT_SKIP_BOOTSTRAP -ne '1' -and (Test-Path -LiteralPath $bootstrapPath)) {
    $bootstrapExit = Invoke-PreflightScript -Path $bootstrapPath -Arguments @(
        '-Here', (ConvertTo-ProcessArgument -Value $Here), '-Quiet'
    )
    if ($bootstrapExit -eq 2) { exit 2 }
    $handoff = Read-PreflightHandoff
}

$skipHealFromHandoff = ($handoff['SKIP_HEAL'] -eq '1') -and (Test-HealthyDeploy -Dir $Here)
$healPath = Join-Path $Here 'connect-heal.ps1'
if (-not $skipHealFromHandoff -and $env:CLAUDE_CONNECT_SKIP_HEAL -ne '1' -and (Test-Path -LiteralPath $healPath)) {
    $healExit = Invoke-PreflightScript -Path $healPath -Arguments @(
        '-Here', (ConvertTo-ProcessArgument -Value $Here)
    )
    if ($healExit -eq 2) { exit 2 }
    if ($healExit -eq 0) {
        $env:CLAUDE_CONNECT_SKIP_HEAL = '1'
    }
}

$isSepidz = $Here -match '(?i)claude-code-sepidz|Claude-Connect-Sepidz'
$skipUpdateFromHandoff = ($handoff['SKIP_UPDATE'] -eq '1') -and (Test-HealthyDeploy -Dir $Here)
$updatePath = Join-Path $Here 'connect-update.ps1'
if (-not $skipUpdateFromHandoff -and -not $isSepidz -and (Test-Path -LiteralPath $updatePath)) {
    $env:CLAUDE_CONNECT_UPDATE_UI = '1'
    $updateExit = Invoke-PreflightScript -Path $updatePath -Sta -Arguments @(
        '-ScriptDir', (ConvertTo-ProcessArgument -Value $Here), '-Quiet'
    )
    if ($updateExit -eq 2) { exit 3 }
}

exit 0
