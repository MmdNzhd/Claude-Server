# connect-update.ps1 - check server client bundle version; download if newer
# Called from connect.bat before connect.ps1. Exit codes:
#   0 = no update needed (or server unreachable - continue with local copy)
#   2 = files updated - caller should relaunch connect.bat

param(
    [string]$ScriptDir = '',
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

if (-not $ScriptDir) {
    $ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
}

$RemoteBundle = if ($env:CLAUDE_CLIENT_BUNDLE) { $env:CLAUDE_CLIENT_BUNDLE.TrimEnd('/') } else { '/usr/local/share/claude-client' }
$StagingDir = Join-Path $ScriptDir '.client-update-staging'

function Write-UpdateMsg {
    param([string]$Msg, [string]$Color = 'DarkGray')
    if (-not $Quiet) {
        Write-Host "  $Msg" -ForegroundColor $Color
        [Console]::Out.Flush()
    }
}

function Get-ConnectVersionParts {
    param([string]$Version)
    if ($Version -match '^(\d{8})\.(\d+)$') {
        return @{ Date = [int]$Matches[1]; Build = [int]$Matches[2] }
    }
    return $null
}

function Test-RemoteVersionNewer {
    param([string]$Remote, [string]$Local)
    if (-not $Remote -or -not $Local) { return $false }
    if ($Remote -eq $Local) { return $false }
    $r = Get-ConnectVersionParts $Remote
    $l = Get-ConnectVersionParts $Local
    if ($r -and $l) {
        if ($r.Date -ne $l.Date) { return $r.Date -gt $l.Date }
        return $r.Build -gt $l.Build
    }
    return ($Remote -gt $Local)
}

function Get-LocalVersion {
    $verFile = Join-Path $ScriptDir 'connect-version.txt'
    if (-not (Test-Path $verFile)) { return '' }
    return (Get-Content $verFile -Raw).Trim()
}

function Get-ServerEndpoint {
    $alias = 'claude-server'
    return @{ Target = $alias; Display = $alias }
}

function Invoke-SshCat {
    param([string]$Target, [string]$RemotePath)
    $out = & ssh -n -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new `
        $Target "cat '$RemotePath'" 2>$null
    if ($null -ne $global:LASTEXITCODE -and [int]$global:LASTEXITCODE -ne 0) { return $null }
    if ($out -is [array]) { return ($out -join "`n").Trim() }
    return [string]$out
}

function Invoke-BundleDownload {
    param(
        [string]$Target,
        [string]$RemoteBundlePath,
        [string]$LocalStagingRoot
    )
    if (Test-Path $LocalStagingRoot) {
        Remove-Item $LocalStagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Force -Path $LocalStagingRoot

    # One SSH session via recursive scp (much faster than per-file handshakes on Windows).
    & scp -r -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new -q `
        "${Target}:${RemoteBundlePath}/." $LocalStagingRoot 2>$null
    return ($null -ne $global:LASTEXITCODE -and [int]$global:LASTEXITCODE -eq 0)
}

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { exit 0 }
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) { exit 0 }

$localVer = Get-LocalVersion
if (-not $localVer) { exit 0 }

$ep = Get-ServerEndpoint
$remoteVer = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/connect-version.txt"
if (-not $remoteVer) { exit 0 }

if (-not (Test-RemoteVersionNewer -Remote $remoteVer -Local $localVer)) { exit 0 }

Write-UpdateMsg "Client update available: v$localVer -> v$remoteVer" 'Cyan'

$manifestRaw = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/manifest.txt"
if (-not $manifestRaw) { exit 0 }

$files = @($manifestRaw -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($files.Count -eq 0) { exit 0 }

Write-UpdateMsg '  downloading client bundle...' 'DarkGray'
if (-not (Invoke-BundleDownload -Target $ep.Target -RemoteBundlePath $RemoteBundle -LocalStagingRoot $StagingDir)) {
    Write-UpdateMsg '[!] Update download failed - using local copy' 'DarkYellow'
    Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}

$failed = @()
foreach ($rel in $files) {
    $src = Join-Path $StagingDir $rel
    if (-not (Test-Path $src)) {
        $failed += $rel
        continue
    }
    $dst = Join-Path $ScriptDir $rel
    $dstParent = Split-Path $dst -Parent
    if ($dstParent -and -not (Test-Path $dstParent)) {
        $null = New-Item -ItemType Directory -Force -Path $dstParent
    }
    Copy-Item $src $dst -Force
}

Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue

if ($failed.Count -gt 0) {
    Write-UpdateMsg "[!] Update incomplete ($($failed.Count) files missing in bundle) - using local copy" 'DarkYellow'
    exit 0
}

Write-UpdateMsg "Updated to v$remoteVer" 'Green'
exit 2
