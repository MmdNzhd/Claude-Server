#Requires -Version 5.1
# build-windows-exe.ps1 - pack windows\ client into a single self-extracting .exe (IExpress).
# For END USERS: give them Claude-Connect.exe only (not the windows\ folder).
# EXE installs to Desktop\Claude-Connect and launches connect.bat (one PowerShell UI).

param(
    [Parameter(Mandatory)][string]$WindowsDir,
    [Parameter(Mandatory)][string]$OutExe,
    [string]$FriendlyName = 'Claude Connect'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-ExeStep([string]$Msg) { Write-Host "  $Msg" -ForegroundColor Cyan }
function Write-ExeOk([string]$Msg)   { Write-Host "  OK  $Msg" -ForegroundColor Green }
function Write-ExeErr([string]$Msg)  { Write-Host "  ERR $Msg" -ForegroundColor Red; exit 1 }

if (-not (Test-Path -LiteralPath $WindowsDir)) { Write-ExeErr "WindowsDir missing: $WindowsDir" }
$bat = Join-Path $WindowsDir 'connect.bat'
if (-not (Test-Path -LiteralPath $bat)) { Write-ExeErr "connect.bat missing in $WindowsDir" }

$iexpress = Join-Path $env:SystemRoot 'System32\iexpress.exe'
if (-not (Test-Path -LiteralPath $iexpress)) { Write-ExeErr "iexpress.exe not found (need Windows IExpress)" }

$stage = Join-Path $env:TEMP ("claude-connect-sfx-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $stage

try {
    Write-ExeStep "Staging client files for EXE..."
    Get-ChildItem -LiteralPath $WindowsDir -File -ErrorAction Stop | ForEach-Object {
        if ($_.Name -match '^connect\.log') { return }
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $stage $_.Name) -Force
    }

    # Reliable launcher (avoid fragile multi-line powershell inside .cmd)
    $launchPs = @'
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$Dest = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect'
$Src = $PSScriptRoot
$Log = Join-Path $env:TEMP 'claude-connect-setup.log'
function Log([string]$m) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
    Write-Host ("  {0}" -f $m)
}
try {
    Log ("setup begin src={0}" -f $Src)
    Log ("setup dest={0}" -f $Dest)
    if (-not (Test-Path -LiteralPath $Dest)) {
        New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    }
    $skip = @('setup-claude-connect.cmd', 'setup-launch.ps1', 'READ-ME-USERS.txt')
    Get-ChildItem -LiteralPath $Src -File | Where-Object { $skip -notcontains $_.Name } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Dest $_.Name) -Force
    }
    $bat = Join-Path $Dest 'connect.bat'
    if (-not (Test-Path -LiteralPath $bat)) { throw "connect.bat missing after copy: $bat" }

    if ($env:CLAUDE_CONNECT_SETUP_NO_LAUNCH -eq '1') {
        Log 'setup files-only (NO_LAUNCH=1) - skip connect.bat'
        exit 0
    }

    # NOTE: do NOT block a second run here. connect-boot.ps1 already owns the single
    # source of truth for "how many Connect windows may run" (Global\ClaudeConnect#0..9,
    # up to 10 per PC - see connect-boot.ps1). A hard pre-check here duplicated that gate
    # and rejected legitimate multi-project runs (2nd, 3rd exe launch) even when slots
    # were free. Let connect-boot.ps1 accept-or-reject via its own mutex pool instead.
    Log 'launching connect.bat (hidden console -> one PowerShell UI)'
    # Hidden cmd runs connect.bat; bat starts visible powershell and exits.
    Start-Process -FilePath 'cmd.exe' -WorkingDirectory $Dest -ArgumentList @('/c', 'connect.bat') -WindowStyle Minimized
    Log 'setup ok'
    exit 0
} catch {
    Log ("SETUP_FAIL $($_.Exception.Message)")
    Write-Host ''
    Write-Host ("  [X] Setup failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ("  Log: {0}" -f $Log) -ForegroundColor Yellow
    Write-Host ''
    try { pause } catch { Start-Sleep -Seconds 8 }
    exit 1
}
'@
    $launchPath = Join-Path $stage 'setup-launch.ps1'
    [System.IO.File]::WriteAllText($launchPath, ($launchPs -replace "`n", "`r`n"), [System.Text.UTF8Encoding]::new($false))

    $userReadme = @'
Claude Connect - for end users
==============================
Double-click Claude-Connect.exe (this package).

It installs into:
  Desktop\Claude-Connect

Do NOT run connect.bat from a publish\windows folder.
That folder is for the publisher/admin only.

First run: enter server username / project path when asked.
Later updates: automatic from the server when you connect again.
'@
    [System.IO.File]::WriteAllText(
        (Join-Path $stage 'READ-ME-USERS.txt'),
        ($userReadme -replace "`n", "`r`n"),
        [System.Text.UTF8Encoding]::new($false)
    )

    $setupCmd = @'
@echo off
setlocal EnableExtensions
cd /d "%~dp0"
echo.
echo   Claude Connect setup...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-launch.ps1"
set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" (
  echo.
  echo   [X] Setup failed. Log: %TEMP%\claude-connect-setup.log
  echo.
  pause
)
exit /b %EC%
'@
    $setupPath = Join-Path $stage 'setup-claude-connect.cmd'
    [System.IO.File]::WriteAllText($setupPath, ($setupCmd -replace "`n", "`r`n"), [System.Text.UTF8Encoding]::new($false))

    $files = @(Get-ChildItem -LiteralPath $stage -File | Sort-Object Name)
    if ($files.Count -lt 3) { Write-ExeErr "Too few staged files: $($files.Count)" }

    $outDir = Split-Path -Parent $OutExe
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Force -Path $outDir
    }
    if (Test-Path -LiteralPath $OutExe) {
        Remove-Item -LiteralPath $OutExe -Force -ErrorAction Stop
    }

    $sedPath = Join-Path $stage 'package.sed'
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('[Version]')
    [void]$sb.AppendLine('Class=IEXPRESS')
    [void]$sb.AppendLine('SEDVersion=3')
    [void]$sb.AppendLine('[Options]')
    [void]$sb.AppendLine('PackagePurpose=InstallApp')
    [void]$sb.AppendLine('ShowInstallProgramWindow=0')
    [void]$sb.AppendLine('HideExtractAnimation=1')
    [void]$sb.AppendLine('UseLongFileName=1')
    [void]$sb.AppendLine('InsideCompressed=0')
    [void]$sb.AppendLine('CAB_FixedSize=0')
    [void]$sb.AppendLine('CAB_ResvCodeSigning=0')
    [void]$sb.AppendLine('RebootMode=N')
    [void]$sb.AppendLine('InstallPrompt=')
    [void]$sb.AppendLine('DisplayLicense=')
    [void]$sb.AppendLine('FinishMessage=')
    [void]$sb.AppendLine(("TargetName={0}" -f $OutExe))
    [void]$sb.AppendLine(("FriendlyName={0}" -f $FriendlyName))
    [void]$sb.AppendLine('AppLaunched=cmd.exe /c setup-claude-connect.cmd')
    [void]$sb.AppendLine('PostInstallCmd=<None>')
    [void]$sb.AppendLine('AdminQuietInstCmd=')
    [void]$sb.AppendLine('UserQuietInstCmd=')
    [void]$sb.AppendLine('SourceFiles=SourceFiles')
    [void]$sb.AppendLine('[Strings]')
    for ($i = 0; $i -lt $files.Count; $i++) {
        [void]$sb.AppendLine(("FILE{0}={1}" -f $i, $files[$i].Name))
    }
    [void]$sb.AppendLine('[SourceFiles]')
    [void]$sb.AppendLine(("SourceFiles0={0}" -f $stage))
    [void]$sb.AppendLine('[SourceFiles0]')
    for ($i = 0; $i -lt $files.Count; $i++) {
        [void]$sb.AppendLine(("%FILE{0}%=" -f $i))
    }

    $sedBody = $sb.ToString() -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText($sedPath, $sedBody, [System.Text.Encoding]::ASCII)

    Write-ExeStep ("Building EXE via IExpress ({0} files)..." -f $files.Count)
    # /Q (quiet) is required alongside /N: /N alone still pops an interactive
    # "IExpress Wizard" window on this Windows build and waits indefinitely for
    # input - invisible (and therefore silently hanging forever) under
    # -WindowStyle Hidden. Confirmed by isolated repro: /N-only left a real,
    # Responding=True "IExpress Wizard" window sitting idle; adding /Q made it
    # return immediately without ever showing a window.
    $p = Start-Process -FilePath $iexpress -ArgumentList @('/N', '/Q', $sedPath) -Wait -PassThru -WindowStyle Hidden
    if (-not $p -or $p.ExitCode -ne 0) {
        Write-ExeErr ("iexpress failed exit={0}" -f $(if ($p) { $p.ExitCode } else { 'null' }))
    }
    if (-not (Test-Path -LiteralPath $OutExe)) {
        Write-ExeErr "EXE was not created: $OutExe"
    }
    $len = (Get-Item -LiteralPath $OutExe).Length
    if ($len -lt 10000) { Write-ExeErr "EXE too small ($len bytes) - likely failed" }
    Write-ExeOk ("{0} ({1:N0} bytes)" -f $OutExe, $len)
}
finally {
    try { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
