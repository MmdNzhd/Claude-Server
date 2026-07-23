#Requires -Version 5.1
# publish.ps1 - Client-only distributable packages (windows/ + mac/ + README).
# Run: double-click publish.bat  (or: powershell -File publish\publish.ps1)
# Output is ALWAYS Desktop\claude-publish\claude-code-client (and claude-code-sepidz) —
# replace-in-place; no dated folder per run. Server scripts stay in the repo Ã¢â‚¬â€ NOT shipped in ZIPs.

param(
    [switch]$NoZip,
    [switch]$NoExe,
    [switch]$SkipVersionBump,
    [switch]$SkipServerDeploy,
    [switch]$SmartOnly,
    [switch]$SepidzOnly,
    [switch]$ForceUnfreeze
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($SmartOnly -and $SepidzOnly) { Write-Err 'Use only one of -SmartOnly or -SepidzOnly' }

$SepidzFrozenMarker = Join-Path $PSScriptRoot 'SEPIDZ_PUBLISH_FROZEN'
$SepidzPublishFrozen = (Test-Path -LiteralPath $SepidzFrozenMarker) -and (-not $ForceUnfreeze)
if ($SepidzPublishFrozen -and $SepidzOnly) {
    Write-Host ''
    Write-Host 'Sepidz publish/deploy is FROZEN (SEPIDZ_PUBLISH_FROZEN).' -ForegroundColor Red
    Write-Host 'To unfreeze: delete publish\SEPIDZ_PUBLISH_FROZEN and pass -ForceUnfreeze' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

$ProjectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'bump-connect-version.ps1')
if (-not $SkipVersionBump) {
    $ConnectVersion = Invoke-BumpConnectVersion -ProjectRoot $ProjectRoot
    Write-Host "  Client version: v$ConnectVersion" -ForegroundColor DarkGray
} else {
    $ConnectVersion = Get-RepoConnectVersion -ProjectRoot $ProjectRoot
    Write-Host "  Client version: v$ConnectVersion (no bump)" -ForegroundColor DarkGray
}
# Stable output dirs: always replace the same folder (no dated copies that go stale).
$Version     = Get-Date -Format 'yyyyMMdd'   # retained for log/display only
$PackageName = 'claude-code-client'
$OutBase     = Join-Path $env:USERPROFILE 'Desktop\claude-publish'
$OutDir      = Join-Path $OutBase $PackageName

$SmartIp = '192.168.210.240'
$SepidIp = '192.168.250.70'

$ClientFiles = @(
    @{ Src = "scripts\client\windows\connect.bat";       Dst = "windows\connect.bat";       PatchIp = $false }
    @{ Src = "scripts\client\windows\connect-boot.ps1";  Dst = "windows\connect-boot.ps1";  PatchIp = $false }
    @{ Src = "scripts\client\windows\connect-preflight.ps1"; Dst = "windows\connect-preflight.ps1"; PatchIp = $false }
    @{ Src = "scripts\client\windows\connect-heal.ps1";  Dst = "windows\connect-heal.ps1";  PatchIp = $false }
    @{ Src = "scripts\client\windows\connect-bootstrap.ps1"; Dst = "windows\connect-bootstrap.ps1"; PatchIp = $false }
    @{ Src = "scripts\client\windows\connect-version.txt"; Dst = "windows\connect-version.txt"; PatchIp = $false }
    @{ Src = "scripts\client\windows\connect-update.ps1"; Dst = "windows\connect-update.ps1"; PatchIp = $false }
    @{ Src = "scripts\client\windows\cursor-proxy-sidecar.ps1"; Dst = "windows\cursor-proxy-sidecar.ps1"; PatchIp = $false }
    @{ Src = "scripts\client\windows\connect.ps1";       Dst = "windows\connect.ps1";       PatchIp = $true  }
    @{ Src = "scripts\client\windows\connect-rider.bat"; Dst = "windows\connect-rider.bat"; PatchIp = $false }
    @{ Src = "scripts\client\editor-launch.ps1";         Dst = "windows\editor-launch.ps1"; PatchIp = $false }
    @{ Src = "scripts\client\git-mode.ps1";              Dst = "windows\git-mode.ps1";      PatchIp = $false }
    @{ Src = "scripts\client\cursor-auth-laptop.ps1";    Dst = "windows\cursor-auth-laptop.ps1"; PatchIp = $false }
    @{ Src = "scripts\client\windows\windows-mcp-laptop.ps1"; Dst = "windows\windows-mcp-laptop.ps1"; PatchIp = $false }
    @{ Src = "scripts\client\connect-ui.ps1";            Dst = "windows\connect-ui.ps1";            PatchIp = $false }
    # connect-diagnostic.ps1: dot-sourced by connect.ps1; verdict lines go to server ~/.claude/logs/
    @{ Src = "scripts\client\connect-diagnostic.ps1";    Dst = "windows\connect-diagnostic.ps1";  PatchIp = $false }
    @{ Src = "scripts\client\mac\connect.sh";            Dst = "mac\connect.sh";            PatchIp = $true  }
    @{ Src = "scripts\client\mac\connect-update.sh";     Dst = "mac\connect-update.sh";     PatchIp = $false }
    @{ Src = "scripts\client\windows\connect-version.txt"; Dst = "mac\connect-version.txt"; PatchIp = $false }
    @{ Src = "scripts\client\git-mode.sh";               Dst = "mac\git-mode.sh";           PatchIp = $false }
    @{ Src = "scripts\client\connect-ui.sh";             Dst = "mac\connect-ui.sh";         PatchIp = $false }
    @{ Src = "scripts\client\editor-launch.sh";          Dst = "mac\editor-launch.sh";      PatchIp = $false }
    @{ Src = "scripts\client\mac\cursor-proxy-sidecar.sh"; Dst = "mac\cursor-proxy-sidecar.sh"; PatchIp = $false }
    @{ Src = "scripts\server\claude-mount.sh";           Dst = "mac\claude-mount.sh";       PatchIp = $false }

    @{ Src = "scripts\server\claude-self-heal.sh";       Dst = "mac\claude-self-heal.sh";   PatchIp = $false }

    @{ Src = "scripts\server\claude-automount.sh";       Dst = "mac\claude-automount.sh";   PatchIp = $false }

    @{ Src = "scripts\server\claude-self-heal.sh";       Dst = "windows\claude-self-heal.sh"; PatchIp = $false }

    @{ Src = "scripts\server\claude-automount.sh";       Dst = "windows\claude-automount.sh"; PatchIp = $false }
)

$DesignerFiles = @(
    @{ Src = "scripts\client\users\designer\connect.bat"; Dst = "windows\connect.bat"; PatchIp = $false }
    @{ Src = "scripts\client\users\designer\connect.ps1"; Dst = "windows\connect.ps1"; PatchIp = $true  }
    @{ Src = "scripts\client\git-mode.ps1";               Dst = "windows\git-mode.ps1"; PatchIp = $false }
    @{ Src = "scripts\client\users\designer\connect.sh";  Dst = "mac\connect.sh";     PatchIp = $true  }
    @{ Src = "scripts\client\git-mode.sh";                Dst = "mac\git-mode.sh";    PatchIp = $false }
)

$SepidName = 'claude-code-sepidz'
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
        if ($ToIp -eq $SepidIp) {
            $aliasBytes = [System.IO.File]::ReadAllBytes($DstAbs)
            $aliasText = [System.Text.Encoding]::UTF8.GetString($aliasBytes)
            if ($aliasText.Length -gt 0 -and [int][char]$aliasText[0] -eq 0xFEFF) { $aliasText = $aliasText.Substring(1) }
            $aliasText2 = $aliasText.Replace('$Alias    = "claude-server"', '$Alias    = "claude-server-sepidz"')
            $aliasText2 = $aliasText2.Replace('$Alias = "claude-server"', '$Alias = "claude-server-sepidz"')
            $aliasText2 = $aliasText2.Replace('ALIAS="claude-server"', 'ALIAS="claude-server-sepidz"')
            if ($aliasText2 -ne $aliasText) {
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllBytes($DstAbs, $utf8NoBom.GetBytes($aliasText2))
                Write-Ok "$(Split-Path $DstAbs -Leaf)  [Alias -> claude-server-sepidz]"
            }
        }
    } else {
        $bytes = [System.IO.File]::ReadAllBytes($src)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $bytes = $bytes[3..($bytes.Length - 1)]
        }
        [System.IO.File]::WriteAllBytes($DstAbs, $bytes)
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

function Test-PublishLogArtifact {
    param([string]$Name)
    return ($Name -match '^connect\.log(\.\d+)?$')
}

function Remove-PublishLogArtifacts {
    param([string]$Root)
    Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { Test-PublishLogArtifact $_.Name } |
        ForEach-Object {
            $logFile = $_
            try {
                Remove-Item -LiteralPath $logFile.FullName -Force -ErrorAction Stop
            } catch {
                Write-Host "  warn: could not remove $($logFile.FullName) (in use - will skip in ZIP)" -ForegroundColor DarkYellow
            }
        }
}

function Clear-PublishedWindowsToExeOnly {
    param(
        [Parameter(Mandatory)][string]$ClientRoot,
        [string]$ExePath = ''
    )
    $win = Join-Path $ClientRoot 'windows'
    if (-not (Test-Path -LiteralPath $win)) { return }
    if (-not $ExePath -or -not (Test-Path -LiteralPath $ExePath)) {
        $ExePath = Join-Path $win 'Claude-Connect.exe'
    }
    if (-not (Test-Path -LiteralPath $ExePath)) {
        Write-Host '  warn: skip windows EXE-only strip (Claude-Connect.exe missing)' -ForegroundColor DarkYellow
        return
    }
    Get-ChildItem -LiteralPath $win -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -in @('Claude-Connect.exe', 'READ-ME.txt')) { return }
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -LiteralPath $ExePath -Destination (Join-Path $win 'Claude-Connect.exe') -Force
    $readme = @"
Claude Connect - do not run from this folder
===========================================
This publish folder is not for end users.

Give users:
  Desktop\Claude-Connect.exe

Live install after first run:
  Desktop\Claude-Connect\
"@
    [IO.File]::WriteAllText(
        (Join-Path $win 'READ-ME.txt'),
        ($readme -replace "`n", "`r`n"),
        [Text.UTF8Encoding]::new($false)
    )
    Write-Ok 'windows\ reduced to Claude-Connect.exe only (ZIP/deploy already used full tree)'
}

function New-ClientZipFromDirectory {
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$ZipPath
    )
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        Get-ChildItem -Path $SourceDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            if (Test-PublishLogArtifact $_.Name) { return }
            $rel = $_.FullName.Substring($SourceDir.Length).TrimStart('\')
            $entry = $zip.CreateEntry($rel.Replace('\', '/'))
            $stream = $entry.Open()
            try {
                $fileStream = [System.IO.File]::Open($_.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                try {
                    $fileStream.CopyTo($stream)
                } finally {
                    $fileStream.Dispose()
                }
            } finally {
                $stream.Dispose()
            }
        }
    } finally {
        $zip.Dispose()
    }
}
Write-Host ""
$readmeSrc = Join-Path $PSScriptRoot "README.txt"
if (-not $SepidzOnly) {
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
if (-not (Test-Path $readmeSrc)) { Write-Err "README.txt not found next to publish.ps1" }
Copy-Item $readmeSrc (Join-Path $OutDir "README.txt") -Force
Write-Ok "README.txt"

Assert-ClientPackage -Root $OutDir -Label 'Main package'
Remove-PublishLogArtifacts -Root $OutDir

Add-Type -AssemblyName System.IO.Compression.FileSystem

# Build EXE BEFORE server deploy so auto-update bundle includes it for existing bat users.
if (-not $NoExe) {
    Write-Step "Creating Claude-Connect.exe (single-file SFX)..."
    $exePath = Join-Path $OutBase 'Claude-Connect.exe'
    $exeScript = Join-Path $PSScriptRoot 'build-windows-exe.ps1'
    if (-not (Test-Path -LiteralPath $exeScript)) {
        Write-Err "build-windows-exe.ps1 missing next to publish.ps1"
    }
    & $exeScript `
        -WindowsDir (Join-Path $OutDir 'windows') `
        -OutExe $exePath `
        -FriendlyName 'Claude Connect'
    if (-not (Test-Path -LiteralPath $exePath)) {
        Write-Err "Windows EXE build failed (use -NoExe to skip)"
    }
    # Ship inside windows\ so server bundle + bat auto-update drops EXE beside connect.bat
    Copy-Item -LiteralPath $exePath -Destination (Join-Path $OutDir 'windows\Claude-Connect.exe') -Force
    Write-Ok ("claude-publish\Claude-Connect.exe + windows\Claude-Connect.exe ({0:N0} bytes)" -f (Get-Item -LiteralPath $exePath).Length)
    try {
        $deskExe = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect.exe'
        $deskSetup = Join-Path $env:USERPROFILE 'Desktop\Claude-Connect-Setup.exe'
        Copy-Item -LiteralPath $exePath -Destination $deskExe -Force
        Copy-Item -LiteralPath $exePath -Destination $deskSetup -Force
        Write-Ok 'Desktop\Claude-Connect.exe (+ Setup copy)'
    } catch {
        Write-Host ("  warn: could not copy EXE to Desktop: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    }
}

if (-not $NoZip) {
    Write-Step "Creating main ZIP..."
    $ZipPath = Join-Path $OutBase "$PackageName.zip"
    New-ClientZipFromDirectory -SourceDir $OutDir -ZipPath $ZipPath
    Write-Ok "$PackageName.zip"

    if (-not $SkipServerDeploy) {
        Write-Host ""
        Write-Host "Deploying Smart server bundle..." -ForegroundColor White
        Write-Host ""
        & (Join-Path $PSScriptRoot 'deploy-smart-bundle.ps1') -ProjectRoot $ProjectRoot -SmartClientRoot $OutDir
        if ($LASTEXITCODE -ne 0) { Write-Err "Smart server deploy failed (use -SkipServerDeploy to skip)" }
    }

    # Keep full windows\ script tree for Smart folder handoff (Desktop\Claude-Connect primary).
    # Outer Desktop\Claude-Connect.exe remains sibling fallback. Do not EXE-only-strip OutDir.
    if ($env:CLAUDE_PUBLISH_STRIP_WINDOWS_EXE_ONLY -eq '1') {
        if (-not $NoExe) {
            Clear-PublishedWindowsToExeOnly -ClientRoot $OutDir -ExePath (Join-Path $OutBase 'Claude-Connect.exe')
        }
    } else {
        Write-Host '  Smart windows\ keeps full script tree (EXE-only strip skipped; set CLAUDE_PUBLISH_STRIP_WINDOWS_EXE_ONLY=1 to enable)' -ForegroundColor DarkGray
    }
}


}

if (-not $SmartOnly) {
if ($SepidzPublishFrozen) {
Write-Host ""
Write-Host "SKIP Sepidz package rebuild and server deploy (FROZEN)." -ForegroundColor Yellow
Write-Host "  Marker: publish\SEPIDZ_PUBLISH_FROZEN" -ForegroundColor DarkYellow
Write-Host "  To unfreeze: delete marker and pass -ForceUnfreeze" -ForegroundColor DarkYellow
} else {
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


Write-Step "Copying README-sepidz.txt to claude-code\README.md..."
$sepidReadmeSrc = Join-Path $PSScriptRoot "README-sepidz.txt"
if (-not (Test-Path $sepidReadmeSrc)) { Write-Err "README-sepidz.txt not found next to publish.ps1" }
$claudeReadme = Join-Path $SepidDir "claude-code\README.md"
$claudeReadmeDir = Split-Path $claudeReadme -Parent
if (-not (Test-Path $claudeReadmeDir)) { $null = New-Item $claudeReadmeDir -ItemType Directory -Force }
Copy-Item $sepidReadmeSrc $claudeReadme -Force
Write-Ok "claude-code\README.md  [Sepidz]"
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
Remove-PublishLogArtifacts -Root $SepidDir

if (-not $NoExe) {
    Write-Step "Creating Sepidz Claude-Connect.exe..."
    $sepidWin = Join-Path $SepidDir 'claude-code\windows'
    $sepidExe = Join-Path $OutBase 'Claude-Connect-Sepidz.exe'
    & (Join-Path $PSScriptRoot 'build-windows-exe.ps1') `
        -WindowsDir $sepidWin `
        -OutExe $sepidExe `
        -FriendlyName 'Claude Connect (Sepidz)'
    if (Test-Path -LiteralPath $sepidExe) {
        Copy-Item -LiteralPath $sepidExe -Destination (Join-Path $sepidWin 'Claude-Connect.exe') -Force
        Write-Ok 'claude-publish\Claude-Connect-Sepidz.exe (+ in sepidz windows\)'
    } else {
        Write-Host '  warn: Sepidz EXE build failed - bundle without EXE' -ForegroundColor DarkYellow
    }
}

if (-not $NoZip) {
    Write-Step "Creating Sepidz ZIP..."
    $SepidZip = Join-Path $OutBase "$SepidName.zip"
    New-ClientZipFromDirectory -SourceDir $SepidDir -ZipPath $SepidZip
    Write-Ok "$SepidName.zip"

    if (-not $SkipServerDeploy) {
        Write-Host ""
        Write-Host "Deploying Sepidz server bundle..." -ForegroundColor White
        Write-Host ""
        & (Join-Path $PSScriptRoot 'deploy-client-bundles.ps1') `
            -ProjectRoot $ProjectRoot `
            -SepidClientRoot (Join-Path $SepidDir 'claude-code') `
            -DeploySmart:$false `
            -DeploySepidz:$true `
            -ForceUnfreeze:$ForceUnfreeze
        if ($LASTEXITCODE -ne 0) { Write-Err "Sepidz server deploy failed (use -SkipServerDeploy to skip)" }
    }
}
}
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
if (-not $SepidzOnly) {
    Write-Host "  Main (Smart IP)  : Desktop\claude-publish\$PackageName" -ForegroundColor Green
    if (-not $NoZip) { Write-Host "  Main ZIP         : Desktop\claude-publish\$PackageName.zip" -ForegroundColor Green }
    if (-not $NoExe) { Write-Host "  Main EXE         : Desktop\claude-publish\Claude-Connect.exe" -ForegroundColor Green }
}
if ((-not $SmartOnly) -and (-not $SepidzPublishFrozen)) {
    Write-Host "  Sepidz (IP patch): Desktop\claude-publish\$SepidName" -ForegroundColor Green
    if (-not $NoZip) { Write-Host "  Sepidz ZIP       : Desktop\claude-publish\$SepidName.zip" -ForegroundColor Green }
} elseif ($SepidzPublishFrozen -and (-not $SepidzOnly)) {
    Write-Host "  Sepidz           : SKIPPED (FROZEN)" -ForegroundColor DarkYellow
}

# Remove legacy dated publish folders/zips so only the stable replace-in-place dirs remain.
try {
    $patterns = @()
    if (-not $SepidzOnly) { $patterns += '^claude-code-client-\d{8}(\.zip)?$' }
    if ((-not $SmartOnly) -and (-not $SepidzPublishFrozen)) { $patterns += '^claude-code-sepidz-\d{8}(\.zip)?$' }
    if ($patterns.Count -gt 0) {
        $re = ($patterns -join '|')
        Get-ChildItem -LiteralPath $OutBase -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match $re
        } | ForEach-Object {
            Write-Host "  Removing stale $($_.Name)..." -ForegroundColor DarkYellow
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} catch {}

Write-Host ""
