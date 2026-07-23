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

function ConvertTo-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ('"{0}"' -f ($Value -replace '"', '\"'))
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

if ($env:CLAUDE_CONNECT_RUN_ID -notmatch '^[0-9a-fA-F]{12}$') {
    $env:CLAUDE_CONNECT_RUN_ID = [guid]::NewGuid().ToString('N').Substring(0, 12)
}
try {
    Set-Content -LiteralPath (Join-Path $env:TEMP 'claude-connect-run-id.txt') `
        -Value $env:CLAUDE_CONNECT_RUN_ID -Encoding ASCII
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

$bootstrapPath = Join-Path $Here 'connect-bootstrap.ps1'
if ($env:CLAUDE_CONNECT_SKIP_BOOTSTRAP -ne '1' -and (Test-Path -LiteralPath $bootstrapPath)) {
    $bootstrapExit = Invoke-PreflightScript -Path $bootstrapPath -Arguments @(
        '-Here', (ConvertTo-ProcessArgument -Value $Here), '-Quiet'
    )
    if ($bootstrapExit -eq 2) { exit 2 }
}

$healPath = Join-Path $Here 'connect-heal.ps1'
if ($env:CLAUDE_CONNECT_SKIP_HEAL -ne '1' -and (Test-Path -LiteralPath $healPath)) {
    $healExit = Invoke-PreflightScript -Path $healPath -Arguments @(
        '-Here', (ConvertTo-ProcessArgument -Value $Here)
    )
    if ($healExit -eq 2) { exit 2 }
}

$isSepidz = $Here -match '(?i)claude-code-sepidz|Claude-Connect-Sepidz'
$updatePath = Join-Path $Here 'connect-update.ps1'
if (-not $isSepidz -and (Test-Path -LiteralPath $updatePath)) {
    $env:CLAUDE_CONNECT_UPDATE_UI = '1'
    $updateExit = Invoke-PreflightScript -Path $updatePath -Sta -Arguments @(
        '-ScriptDir', (ConvertTo-ProcessArgument -Value $Here), '-Quiet'
    )
    if ($updateExit -eq 2) { exit 3 }
}

exit 0
