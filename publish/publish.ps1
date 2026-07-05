#Requires -Version 5.1
# publish.ps1 - Client-only distributable packages (windows/ + mac/ + README).
# Run: double-click publish.bat  (or: powershell -File publish\publish.ps1)
# Server scripts and deploy tools stay in the repo — NOT shipped in ZIPs.

param(
    [switch]$NoZip,
    [switch]$SkipVersionBump
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'bump-connect-version.ps1')
if (-not $SkipVersionBump) {
    $ConnectVersion = Invoke-BumpConnectVersion -ProjectRoot $ProjectRoot
    Write-Host "  Client version: v$ConnectVersion" -ForegroundColor DarkGray
} else {
    $ConnectVersion = Get-RepoConnectVersion -ProjectRoot $ProjectRoot
    Write-Host "  Client version: v$ConnectVersion (no bump)" -ForegroundColor DarkGray
}
$Version     = Get-Date -Format 'yyyyMMdd'
$PackageName = "claude-code-client-$Version"
$OutBase     = Join-Path $env:USERPROFILE "Desktop\claude-publish"
$OutDir      = Join-Path $OutBase $PackageName

$SmartIp = '192.168.210.240'
$SepidIp = '192.168.250.70'

$ClientFiles = @(
    @{ Src = "scripts\client\windows\connect.bat";       Dst = "windows\connect.bat";       PatchIp = $false }
    @{ Src = "scripts\client\windows\connect-version.txt"; Dst = "windows\connect-version.txt"; PatchIp = $false }
    @{ Src = "scripts\client\windows\connect.ps1";       Dst = "windows\connect.ps1";       PatchIp = $true  }
    @{ Src = "scripts\client\windows\connect-rider.bat"; Dst = "windows\connect-rider.bat"; PatchIp = $false }
    @{ Src = "scripts\client\editor-launch.ps1";         Dst = "windows\editor-launch.ps1"; PatchIp = $false }
    @{ Src = "scripts\client\git-mode.ps1";              Dst = "windows\git-mode.ps1";      PatchIp = $false }
    @{ Src = "scripts\client\cursor-auth-laptop.ps1";    Dst = "windows\cursor-auth-laptop.ps1"; PatchIp = $false }
    @{ Src = "scripts\client\connect-ui.ps1";            Dst = "windows\connect-ui.ps1";            PatchIp = $false }
    @{ Src = "scripts\client\mac\connect.sh";            Dst = "mac\connect.sh";            PatchIp = $true  }
    @{ Src = "scripts\client\git-mode.sh";               Dst = "mac\git-mode.sh";           PatchIp = $false }
    @{ Src = "scripts\client\connect-ui.sh";             Dst = "mac\connect-ui.sh";         PatchIp = $false }
    @{ Src = "scripts\client\editor-launch.sh";          Dst = "mac\editor-launch.sh";      PatchIp = $false }
    @{ Src = "scripts\server\claude-mount.sh";           Dst = "mac\claude-mount.sh";       PatchIp = $false }
)

$DesignerFiles = @(
    @{ Src = "scripts\client\users\designer\connect.bat"; Dst = "windows\connect.bat"; PatchIp = $false }
    @{ Src = "scripts\client\users\designer\connect.ps1"; Dst = "windows\connect.ps1"; PatchIp = $true  }
    @{ Src = "scripts\client\git-mode.ps1";               Dst = "windows\git-mode.ps1"; PatchIp = $false }
    @{ Src = "scripts\client\users\designer\connect.sh";  Dst = "mac\connect.sh";     PatchIp = $true  }
    @{ Src = "scripts\client\git-mode.sh";                Dst = "mac\git-mode.sh";    PatchIp = $false }
)

$SepidName = "claude-code-sepidz-$Version"
$SepidDir  = Join-Path $OutBase $SepidName

function Write-Step([string]$Msg) { Write-Host "  $Msg" -ForegroundColor Cyan }
function Write-Ok([string]$Msg)   { Write-Host "  OK  $Msg" -ForegroundColor Green }
function Write-Err([string]$Msg)  { Write-Host "  ERR $Msg" -ForegroundColor Red; exit 1 }

function Install-PublishedFile {
    param(
        [string]$SrcRel,
        [string]$DstAbs,
        [bool]$PatchIp,
        [string]$FromIp = $SmartIp,
        [string]$ToIp = $SepidIp
    )
    $src = Join-Path $ProjectRoot $SrcRel
    if (-not (Test-Path $src)) { Write-Err "Source not found: $src" }
    $dstDir = Split-Path $DstAbs -Parent
    if ($dstDir -and -not (Test-Path $dstDir)) {
        $null = New-Item $dstDir -ItemType Directory -Force
    }
    if ($PatchIp) {
        $bytes = [System.IO.File]::ReadAllBytes($src)
        $fromBytes = [System.Text.Encoding]::UTF8.GetBytes($FromIp)
        $toBytes = [System.Text.Encoding]::UTF8.GetBytes($ToIp)
        if ($fromBytes.Length -eq $toBytes.Length) {
            $out = New-Object System.Collections.Generic.List[byte]
            for ($i = 0; $i -lt $bytes.Length; ) {
                $match = ($i + $fromBytes.Length -le $bytes.Length)
                if ($match) {
                    for ($j = 0; $j -lt $fromBytes.Length; $j++) {
                        if ($bytes[$i + $j] -ne $fromBytes[$j]) { $match = $false; break }
                    }
                }
                if ($match) {
                    $out.AddRange([byte[]]$toBytes)
                    $i += $fromBytes.Length
                } else {
                    $out.Add($bytes[$i])
                    $i++
                }
            }
            [System.IO.File]::WriteAllBytes($DstAbs, $out.ToArray())
        } else {
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
            if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF) { $text = $text.Substring(1) }
            $text = $text -replace [regex]::Escape($FromIp), $ToIp
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllBytes($DstAbs, $utf8NoBom.GetBytes($text))
        }
        Write-Ok "$(Split-Path $DstAbs -Leaf)  [IP: $FromIp -> $ToIp]"
    } else {
        Copy-Item $src $DstAbs -Force
        Write-Ok (Split-Path $DstAbs -Leaf)
    }
}

function Assert-ClientPackage {
    param([string]$Root, [string]$Label)
    if (-not (Test-Path $Root)) { Write-Err "$Label folder missing: $Root" }
    $serverDirs = @(Get-ChildItem -Path $Root -Recurse -Directory -Filter 'server' -ErrorAction SilentlyContinue)
    if ($serverDirs.Count -gt 0) {
        Write-Err "$Label contains forbidden server/ folder"
    }
    foreach ($name in @('deploy-server-mount-fix.ps1', 'deploy-server-mount-fix.bat', 'deploy-mount-fix.sh')) {
        $hits = @(Get-ChildItem -Path $Root -Recurse -File -Filter $name -ErrorAction SilentlyContinue)
        if ($hits.Count -gt 0) {
            Write-Err "$Label contains forbidden server deploy file: $name"
        }
    }
    if (-not (Test-Path (Join-Path $Root 'windows\connect.ps1')) -and
        -not (Test-Path (Join-Path $Root 'claude-code\windows\connect.ps1'))) {
        Write-Err "$Label missing windows\connect.ps1"
    }
}

Write-Host ""
Write-Host "Publishing $PackageName (client only)" -ForegroundColor White
Write-Host ""

Write-Step "Creating output folder..."
if (Test-Path $OutDir) {
    try { Remove-Item $OutDir -Recurse -Force -ErrorAction Stop }
    catch { Write-Host " (locked, will overwrite)" -ForegroundColor DarkYellow }
}
$null = New-Item $OutDir -ItemType Directory -Force
Write-Ok $OutDir

foreach ($entry in $ClientFiles) {
    Write-Step "Copying $($entry.Src)..."
    Install-PublishedFile -SrcRel $entry.Src -DstAbs (Join-Path $OutDir $entry.Dst) -PatchIp:$false
}

Write-Step "Copying README.txt..."
$readmeSrc = Join-Path $PSScriptRoot "README.txt"
if (-not (Test-Path $readmeSrc)) { Write-Err "README.txt not found next to publish.ps1" }
Copy-Item $readmeSrc (Join-Path $OutDir "README.txt") -Force
Write-Ok "README.txt"

Assert-ClientPackage -Root $OutDir -Label 'Main package'

Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not $NoZip) {
    Write-Step "Creating main ZIP..."
    $ZipPath = Join-Path $OutBase "$PackageName.zip"
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($OutDir, $ZipPath)
    Write-Ok "$PackageName.zip"
}

Write-Host ""
Write-Host "Building Sepidz package (client only, IP patched)..." -ForegroundColor White
Write-Host ""

Write-Step "Creating Sepidz output folder..."
if (Test-Path $SepidDir) {
    try { Remove-Item $SepidDir -Recurse -Force -ErrorAction Stop }
    catch { Write-Host " (locked, will overwrite)" -ForegroundColor DarkYellow }
}
$null = New-Item $SepidDir -ItemType Directory -Force
Write-Ok $SepidDir

foreach ($entry in $ClientFiles) {
    Write-Step "Copying $($entry.Src) to claude-code\$($entry.Dst)..."
    Install-PublishedFile -SrcRel $entry.Src `
        -DstAbs (Join-Path $SepidDir "claude-code\$($entry.Dst)") `
        -PatchIp:([bool]$entry.PatchIp)
}

foreach ($entry in $DesignerFiles) {
    Write-Step "Copying $($entry.Src) to designer\$($entry.Dst)..."
    Install-PublishedFile -SrcRel $entry.Src `
        -DstAbs (Join-Path $SepidDir "designer\$($entry.Dst)") `
        -PatchIp:([bool]$entry.PatchIp)
}

Write-Step "Copying README.txt to claude-code\README.md..."
$claudeReadme = Join-Path $SepidDir "claude-code\README.md"
$readmeBytes = [System.IO.File]::ReadAllBytes($readmeSrc)
$readmeText = [System.Text.Encoding]::UTF8.GetString($readmeBytes)
if ($readmeText.Length -gt 0 -and [int][char]$readmeText[0] -eq 0xFEFF) { $readmeText = $readmeText.Substring(1) }
$readmeText = $readmeText -replace [regex]::Escape($SmartIp), $SepidIp
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllBytes($claudeReadme, $utf8NoBom.GetBytes($readmeText))
Write-Ok "claude-code\README.md  [IP patched]"

Write-Step "Copying designer README.md..."
$designerReadme = Join-Path $ProjectRoot "scripts\client\users\designer\README.md"
$designerDir = Join-Path $SepidDir "designer"
if (Test-Path $designerReadme) {
    Copy-Item $designerReadme (Join-Path $designerDir "README.md") -Force
    Write-Ok "designer\README.md"
} else {
    Write-Host "  SKIP designer\README.md (not found)" -ForegroundColor DarkYellow
}

Assert-ClientPackage -Root $SepidDir -Label 'Sepidz package'

if (-not $NoZip) {
    Write-Step "Creating Sepidz ZIP..."
    $SepidZip = Join-Path $OutBase "$SepidName.zip"
    if (Test-Path $SepidZip) { Remove-Item $SepidZip -Force }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($SepidDir, $SepidZip)
    Write-Ok "$SepidName.zip"
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  Main (Smart IP)  : Desktop\claude-publish\$PackageName" -ForegroundColor Green
Write-Host "  Sepidz (IP patch): Desktop\claude-publish\$SepidName" -ForegroundColor Green
if (-not $NoZip) {
    Write-Host "  Main ZIP         : Desktop\claude-publish\$PackageName.zip" -ForegroundColor Green
    Write-Host "  Sepidz ZIP       : Desktop\claude-publish\$SepidName.zip" -ForegroundColor Green
}
Write-Host ""
