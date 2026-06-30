#Requires -Version 5.1
# publish.ps1 - Creates a distributable package of client connection scripts.
# Run: double-click publish.bat  (or: powershell -File publish\publish.ps1)
# Optionally pass -NoZip to skip ZIP creation.

param(
    [switch]$NoZip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$Version     = Get-Date -Format 'yyyyMMdd'
$PackageName = "claude-code-client-$Version"
$OutBase     = Join-Path $env:USERPROFILE "Desktop\claude-publish"
$OutDir      = Join-Path $OutBase $PackageName

$FilesToCopy = @(
    @{ Src = "scripts\client\windows\connect.bat"; Dst = "windows\connect.bat" }
    @{ Src = "scripts\client\windows\connect.ps1"; Dst = "windows\connect.ps1" }
    @{ Src = "scripts\client\editor-launch.ps1"; Dst = "windows\editor-launch.ps1" }
    @{ Src = "scripts\client\mac\connect.sh";      Dst = "mac\connect.sh"      }
)

$SepidFiles = @(
    @{ Src = "scripts\client\users\sepidz\connect.bat";    Dst = "claude-code\windows\connect.bat";  PatchIp = $false }
    @{ Src = "scripts\client\users\sepidz\connect.ps1";    Dst = "claude-code\windows\connect.ps1";  PatchIp = $false }
    @{ Src = "scripts\client\editor-launch.ps1";           Dst = "claude-code\windows\editor-launch.ps1"; PatchIp = $false }
    @{ Src = "scripts\client\users\sepidz\connect.sh";     Dst = "claude-code\mac\connect.sh";       PatchIp = $false }
    @{ Src = "scripts\client\users\designer\connect.bat";  Dst = "designer\windows\connect.bat";     PatchIp = $false }
    @{ Src = "scripts\client\users\designer\connect.ps1";  Dst = "designer\windows\connect.ps1";     PatchIp = $true  }
    @{ Src = "scripts\client\users\designer\connect.sh";   Dst = "designer\mac\connect.sh";          PatchIp = $true  }
)
$SepidName = "claude-code-sepidz-$Version"
$SepidDir  = Join-Path $OutBase $SepidName

function Write-Step([string]$Msg) { Write-Host "  $Msg" -ForegroundColor Cyan }
function Write-Ok([string]$Msg)   { Write-Host "  OK  $Msg" -ForegroundColor Green }
function Write-Err([string]$Msg)  { Write-Host "  ERR $Msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "Publishing $PackageName" -ForegroundColor White
Write-Host ""

Write-Step "Creating output folder..."
if (Test-Path $OutDir) {
    try { Remove-Item $OutDir -Recurse -Force -ErrorAction Stop }
    catch { Write-Host " (locked, will overwrite)" -ForegroundColor DarkYellow }
}
$null = New-Item $OutDir -ItemType Directory -Force
Write-Ok $OutDir

foreach ($entry in $FilesToCopy) {
    $src = Join-Path $ProjectRoot $entry.Src
    $dst = Join-Path $OutDir      $entry.Dst

    Write-Step "Copying $($entry.Src)..."
    if (-not (Test-Path $src)) { Write-Err "Source not found: $src" }

    $dstDir = Split-Path $dst -Parent
    $null = New-Item $dstDir -ItemType Directory -Force
    Copy-Item $src $dst -Force
    Write-Ok $entry.Dst
}

Write-Step "Copying README.txt..."
$readmeSrc = Join-Path $PSScriptRoot "README.txt"
if (-not (Test-Path $readmeSrc)) { Write-Err "README.txt not found next to publish.ps1" }
Copy-Item $readmeSrc (Join-Path $OutDir "README.txt") -Force
Write-Ok "README.txt"

Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not $NoZip) {
    Write-Step "Creating main ZIP..."
    $ZipPath = Join-Path $OutBase "$PackageName.zip"
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($OutDir, $ZipPath)
    Write-Ok "$PackageName.zip"
}

Write-Host ""
Write-Host "Building Sepidz package..." -ForegroundColor White
Write-Host ""

Write-Step "Creating Sepidz output folder..."
if (Test-Path $SepidDir) {
    try { Remove-Item $SepidDir -Recurse -Force -ErrorAction Stop }
    catch { Write-Host " (locked, will overwrite)" -ForegroundColor DarkYellow }
}
$null = New-Item $SepidDir -ItemType Directory -Force
Write-Ok $SepidDir

$SmartIp = "192.168.210.240"
$SepidIp = "192.168.250.70"

foreach ($entry in $SepidFiles) {
    $src = Join-Path $ProjectRoot $entry.Src
    $dst = Join-Path $SepidDir   $entry.Dst
    Write-Step "Copying $($entry.Src)..."
    if (-not (Test-Path $src)) { Write-Err "Source not found: $src" }
    $dstDir = Split-Path $dst -Parent
    $null = New-Item $dstDir -ItemType Directory -Force
    if ($entry.PatchIp) {
        (Get-Content $src -Raw) -replace [regex]::Escape($SmartIp), $SepidIp | Set-Content $dst -Encoding UTF8 -NoNewline
        Write-Ok "$($entry.Dst)  [IP patched: $SmartIp -> $SepidIp]"
    } else {
        Copy-Item $src $dst -Force
        Write-Ok $entry.Dst
    }
}

Write-Step "Copying quick-start.md to claude-code\README.md..."
$sepidReadme = Join-Path $ProjectRoot "scripts\client\users\sepidz\quick-start.md"
$claudeCodeDir = Join-Path $SepidDir "claude-code"
$null = New-Item $claudeCodeDir -ItemType Directory -Force
if (Test-Path $sepidReadme) {
    Copy-Item $sepidReadme (Join-Path $claudeCodeDir "README.md") -Force
} else {
    Copy-Item $readmeSrc (Join-Path $claudeCodeDir "README.md") -Force
}
Write-Ok "claude-code\README.md"

Write-Step "Copying designer README.md..."
$designerReadme = Join-Path $ProjectRoot "scripts\client\users\designer\README.md"
$designerDir = Join-Path $SepidDir "designer"
$null = New-Item $designerDir -ItemType Directory -Force
if (Test-Path $designerReadme) {
    Copy-Item $designerReadme (Join-Path $designerDir "README.md") -Force
    Write-Ok "designer\README.md"
} else {
    Write-Host "  SKIP designer\README.md (not found)" -ForegroundColor DarkYellow
}

if (-not $NoZip) {
    Write-Step "Creating Sepidz ZIP..."
    $SepidZip = Join-Path $OutBase "$SepidName.zip"
    if (Test-Path $SepidZip) { Remove-Item $SepidZip -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($SepidDir, $SepidZip)
    Write-Ok "$SepidName.zip"
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  Main        : Desktop\claude-publish\$PackageName" -ForegroundColor Green
Write-Host "  Sepidz      : Desktop\claude-publish\$SepidName  (includes designer\ folder)" -ForegroundColor Green
if (-not $NoZip) {
    Write-Host "  Main ZIP    : Desktop\claude-publish\$PackageName.zip" -ForegroundColor Green
    Write-Host "  Sepidz ZIP  : Desktop\claude-publish\$SepidName.zip" -ForegroundColor Green
}
Write-Host ""
