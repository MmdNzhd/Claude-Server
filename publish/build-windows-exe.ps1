#Requires -Version 5.1
# build-windows-exe.ps1 - pack windows\ client into a single self-extracting .exe (IExpress).
# Folder/ZIP handoff is PRIMARY for users (see docs/client-connect.md + publish/README.txt).
# This unsigned IExpress EXE is an OPTIONAL fallback and may trip SmartScreen/Defender FP.
# Never disable Defender in this script. EXE installs to Desktop\Claude-Connect + connect.bat.
# FP guidance: Unblock/MOTW, scoped exclusion Desktop\Claude-Connect only, WDSI submission,
# future Authenticode OV+timestamp â€” docs/client-connect.md "SmartScreen / Defender".

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
    $bodyPath = Join-Path $PSScriptRoot '_setup-launch-body.ps1'
    if (-not (Test-Path -LiteralPath $bodyPath)) { Write-ExeErr "_setup-launch-body.ps1 missing: $bodyPath" }
    $launchPs = Get-Content -LiteralPath $bodyPath -Raw -Encoding UTF8
    $launchPath = Join-Path $stage 'setup-launch.ps1'
    [System.IO.File]::WriteAllText($launchPath, ($launchPs -replace "`n", "`r`n"), [System.Text.UTF8Encoding]::new($false))

    # Detached worker: setup-launch.ps1 copies this to Desktop\Claude-Connect and spawns it, then
    # exits fast so the IExpress wextract single-instance mutex is released immediately (fixes the
    # "Setup is currently running" dialog + the lingering extractor cmd window).
    $workerBodyPath = Join-Path $PSScriptRoot '_setup-worker-body.ps1'
    if (-not (Test-Path -LiteralPath $workerBodyPath)) { Write-ExeErr "_setup-worker-body.ps1 missing: $workerBodyPath" }
    $workerPs = Get-Content -LiteralPath $workerBodyPath -Raw -Encoding UTF8
    $workerPath = Join-Path $stage 'setup-worker.ps1'
    [System.IO.File]::WriteAllText($workerPath, ($workerPs -replace "`n", "`r`n"), [System.Text.UTF8Encoding]::new($false))

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
echo   Claude Connect - installing / starting...
echo   A progress window appears if an update is downloading.
echo.
powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0setup-launch.ps1"
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
    [void]$sb.AppendLine('AppLaunched=powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File setup-launch.ps1')
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
