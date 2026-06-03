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
    @{ Src = "scripts\client\mac\connect.sh";      Dst = "mac\connect.sh"      }
)

function Write-Step([string]$Msg) { Write-Host "  $Msg" -ForegroundColor Cyan }
function Write-Ok([string]$Msg)   { Write-Host "  OK  $Msg" -ForegroundColor Green }
function Write-Err([string]$Msg)  { Write-Host "  ERR $Msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "Publishing $PackageName" -ForegroundColor White
Write-Host ""

Write-Step "Creating output folder..."
if (Test-Path $OutDir) {
    try { Remove-Item $OutDir -Recurse -Force -ErrorAction Stop }
    catch { Write-Err "Cannot delete old package folder - close Windows Explorer in dist\ and retry." }
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

if (-not $NoZip) {
    Write-Step "Creating ZIP..."
    $ZipPath = Join-Path $OutBase "$PackageName.zip"
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($OutDir, $ZipPath)
    Write-Ok "$PackageName.zip"
}

Write-Host ""
Write-Host "Done.  Package is at: Desktop\claude-publish\$PackageName" -ForegroundColor Green
if (-not $NoZip) {
    Write-Host "       ZIP ready at:  Desktop\claude-publish\$PackageName.zip" -ForegroundColor Green
}
Write-Host ""
