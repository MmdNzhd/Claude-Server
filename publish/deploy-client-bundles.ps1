#Requires -Version 5.1
# deploy-client-bundles.ps1 - push auto-update bundle to Smart + Sepidz servers after publish.
# Called from publish.ps1 (or standalone after a publish folder exists).

param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [string]$SmartClientRoot = '',
    [string]$SepidClientRoot = '',
    [string]$SmartServer = 'smart@192.168.210.240',
    [string]$SepidServer = 'sepidz@192.168.250.70',
    [switch]$ContinueOnDeployError,
    [switch]$DeploySmart = $true,
    [switch]$DeploySepidz = $true,
    [switch]$ForceUnfreeze,
    # Passes FORCE_UNFREEZE=1 through to the remote install-client-bundle.sh invocation for the
    # Smart target only, overriding the server-side /usr/local/share/claude-client.FROZEN guard
    # (a separate, server-local marker from -ForceUnfreeze above, which only controls the local
    # publish\SEPIDZ_PUBLISH_FROZEN check). Never applied to Sepidz regardless of this switch -
    # see the Smart-only gate at the Invoke-RemoteBundleInstall call site below.
    [switch]$ForceServerUnfreezeSmart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Get-DeployCredentials.ps1')
if (-not $PSBoundParameters.ContainsKey('SepidServer')) { $SepidServer = Get-SepidzServerTarget }

# Block Sepidz while publish/SEPIDZ_PUBLISH_FROZEN exists (unless -ForceUnfreeze).
$sepidzFreezeMarker = Join-Path $PSScriptRoot 'SEPIDZ_PUBLISH_FROZEN'
if ($DeploySepidz -and (Test-Path -LiteralPath $sepidzFreezeMarker) -and -not $ForceUnfreeze) {
    if (-not $DeploySmart) {
        Write-Host ''
        Write-Host 'Sepidz server deploy is FROZEN (SEPIDZ_PUBLISH_FROZEN).' -ForegroundColor Red
        Write-Host 'To unfreeze: delete publish\SEPIDZ_PUBLISH_FROZEN and pass -ForceUnfreeze' -ForegroundColor Yellow
        Write-Host ''
        exit 1
    }
    Write-Host 'WARN: Sepidz deploy skipped (FROZEN / SEPIDZ_PUBLISH_FROZEN). Smart deploy continues. Pass -ForceUnfreeze to override.' -ForegroundColor Yellow
    $DeploySepidz = $false
}

if ($DeploySmart -and -not $SmartClientRoot) { throw 'SmartClientRoot is required when -DeploySmart is set' }
if ($DeploySepidz -and -not $SepidClientRoot) { throw 'SepidClientRoot is required when -DeploySepidz is set' }



$RemoteDeployDir = 'claude-client-bundle-deploy'
$InstallScriptRel = 'scripts\server\commands\install-client-bundle.sh'

$WinBundleFiles = @(
    'connect.bat',
    'connect-boot.ps1',
    'connect-heal.ps1',
    'connect-bootstrap.ps1',
    'connect-version.txt',
    'connect.ps1',
    'connect-rider.bat',
    'connect-update.ps1',
    'cursor-proxy-sidecar.ps1',
    'connect-ui.ps1',
    'connect-diagnostic.ps1',
    'editor-launch.ps1',
    'git-mode.ps1',
    'cursor-auth-laptop.ps1',
    'windows-mcp-laptop.ps1',
    'Claude-Connect.exe'
)

$MacBundleFiles = @(
    'connect.sh',
    'connect-update.sh',
    'connect-version.txt',
    'cursor-proxy-sidecar.sh',
    'git-mode.sh',
    'connect-ui.sh',
    'editor-launch.sh',
    'claude-mount.sh'
)

$ServerBundleFiles = @(
    'laptop-exec.sh',
    'laptop-exec-setup.sh',
    'claude-mount.sh',
    'claude-git-setup.sh',
    'cursor-rules/laptop-exec.mdc',
    'skills/laptop-exec/SKILL.md',
    'cursor-hooks/laptop-exec-guard.sh',
    'cursor-hooks/hooks-user.json'
)

function Write-DeployStep([string]$Msg) { Write-Host "  $Msg" -ForegroundColor Cyan }
function Write-DeployOk([string]$Msg)   { Write-Host "  OK  $Msg" -ForegroundColor Green }
function Write-DeployWarn([string]$Msg)  { Write-Host "  WARN $Msg" -ForegroundColor Yellow }
function Write-DeployErr([string]$Msg)  { Write-Host "  ERR $Msg" -ForegroundColor Red }

function Test-CommandAvailable([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function New-BundleZipFromDirectory {
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

function Copy-PublishedFile {
    param(
        [Parameter(Mandatory)][string]$Src,
        [Parameter(Mandatory)][string]$Dst
    )
    $dstParent = Split-Path $Dst -Parent
    if ($dstParent -and -not (Test-Path $dstParent)) {
        $null = New-Item -ItemType Directory -Force -Path $dstParent
    }
    Copy-Item -LiteralPath $Src -Destination $Dst -Force
}

function Build-AutoUpdateBundleStage {
    param(
        [Parameter(Mandatory)][string]$ClientRoot,
        [Parameter(Mandatory)][string]$StageDir
    )

    if (-not (Test-Path $ClientRoot)) {
        throw "Client root not found: $ClientRoot"
    }

    if (Test-Path $StageDir) {
        Remove-Item $StageDir -Recurse -Force
    }
    $null = New-Item -ItemType Directory -Force -Path $StageDir
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $StageDir 'mac')
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $StageDir 'server')

    foreach ($name in $WinBundleFiles) {
        $src = Join-Path $ClientRoot "windows\$name"
        if (-not (Test-Path $src)) {
            if ($name -eq 'Claude-Connect.exe') {
                Write-DeployWarn "Missing $name in publish windows\ - bat users will not auto-receive EXE this deploy"
                continue
            }
            throw "Missing published file: $src"
        }
        Copy-PublishedFile -Src $src -Dst (Join-Path $StageDir $name)
    }
    $policySrc = Join-Path $ProjectRoot 'scripts\server\client-update-policy.json'
    if (Test-Path -LiteralPath $policySrc) {
        Copy-PublishedFile -Src $policySrc -Dst (Join-Path $StageDir 'client-update-policy.json')
    }

    foreach ($name in $MacBundleFiles) {
        $src = Join-Path $ClientRoot "mac\$name"
        if (-not (Test-Path $src)) { throw "Missing published file: $src" }
        Copy-PublishedFile -Src $src -Dst (Join-Path $StageDir "mac\$name")
    }

    foreach ($rel in $ServerBundleFiles) {
        $src = Join-Path $ProjectRoot ("scripts\server\" + ($rel -replace '/', '\'))
        if (-not (Test-Path $src)) { throw "Missing server file: $src" }
        Copy-PublishedFile -Src $src -Dst (Join-Path $StageDir ("server\" + ($rel -replace '/', '\')))
    }

    $manifestLines = New-Object System.Collections.Generic.List[string]
    foreach ($name in $WinBundleFiles) {
        if (Test-Path (Join-Path $StageDir $name)) { $manifestLines.Add($name) | Out-Null }
    }
    if (Test-Path (Join-Path $StageDir 'client-update-policy.json')) {
        $manifestLines.Add('client-update-policy.json') | Out-Null
    }
    foreach ($name in $MacBundleFiles) {
        if (Test-Path (Join-Path $StageDir "mac\$name")) { $manifestLines.Add("mac/$name") | Out-Null }
    }
    Get-ChildItem -Path (Join-Path $StageDir 'server') -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring((Join-Path $StageDir 'server').Length).TrimStart('\').Replace('\', '/')
        $manifestLines.Add("server/$rel") | Out-Null
    }
    # PS 5.1 -Encoding UTF8 writes a BOM that breaks the first manifest line on clients.
    $manifestPath = Join-Path $StageDir 'manifest.txt'
    $manifestBody = (($manifestLines | Sort-Object) -join "`n") + "`n"
    [System.IO.File]::WriteAllBytes($manifestPath, [System.Text.UTF8Encoding]::new($false).GetBytes($manifestBody))

    # SHA-256 checksums (GNU sha256sum style) for client post-scp verify.
    $sumLines = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -Path $StageDir -Recurse -File | ForEach-Object {
        if ($_.Name -eq 'checksums.txt') { return }
        $rel = $_.FullName.Substring($StageDir.Length).TrimStart('\').Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $sumLines.Add(('{0}  {1}' -f $hash, $rel)) | Out-Null
    }
    $sumPath = Join-Path $StageDir 'checksums.txt'
    $sumBody = (($sumLines | Sort-Object) -join "`n") + "`n"
    [System.IO.File]::WriteAllBytes($sumPath, [System.Text.UTF8Encoding]::new($false).GetBytes($sumBody))
}

function Test-RemoteVersionMatches {
    param(
        [string]$RemoteVer,
        [string]$ExpectedVersion
    )
    if (-not $RemoteVer) { return $false }
    if (-not $ExpectedVersion) { return $true }
    return ($RemoteVer -eq $ExpectedVersion)
}

function Invoke-SshTimed {
    param([string]$Target, [string]$RemoteCmd, [int]$TimeoutSec = 60)
    $out = [System.IO.Path]::GetTempFileName()
    $err = "$out.err"
    $p = Start-Process -FilePath ssh -ArgumentList @(
        '-o','BatchMode=yes','-o','ConnectTimeout=15','-o','ConnectionAttempts=1',
        '-o','ControlMaster=no','-o','IdentitiesOnly=yes','-o','IdentityAgent=none',
        '-o','ServerAliveInterval=5','-o','ServerAliveCountMax=6',
        $Target, $RemoteCmd
    ) -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    if (-not $p.WaitForExit([Math]::Max(1000, $TimeoutSec * 1000))) {
        try { $p.Kill() } catch {}
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
        return @{ Code = 124; Out = ''; Err = 'TIMEOUT' }
    }
    try { $p.Refresh() } catch {}
    $o = ((Get-Content $out -Raw -ErrorAction SilentlyContinue) + '')
    $e = ((Get-Content $err -Raw -ErrorAction SilentlyContinue) + '')
    # PS 5.1 quirk: ExitCode on Start-Process -PassThru can be $null even when HasExited
    $code = 0
    try {
        if ($null -ne $p.ExitCode) { $code = [int]$p.ExitCode }
        elseif ($e.Trim().Length -gt 0 -and $e -notmatch 'Warning:') { $code = 1 }
    } catch { $code = 1 }
    return @{ Code = $code; Out = $o; Err = $e }
}

function Invoke-ScpTimed {
    param([int]$TimeoutSec = 120, [Parameter(Mandatory)][string[]]$ArgumentList)
    $out = [System.IO.Path]::GetTempFileName()
    $err = "$out.err"
    $p = Start-Process -FilePath scp -ArgumentList $ArgumentList -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    if (-not $p.WaitForExit([Math]::Max(1000, $TimeoutSec * 1000))) {
        try { $p.Kill() } catch {}
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
        return @{ Code = 124; Out = ''; Err = 'TIMEOUT' }
    }
    try { $p.Refresh() } catch {}
    $o = ((Get-Content $out -Raw -ErrorAction SilentlyContinue) + '')
    $e = ((Get-Content $err -Raw -ErrorAction SilentlyContinue) + '')
    $code = 0
    try {
        if ($null -ne $p.ExitCode) { $code = [int]$p.ExitCode }
        elseif ($e.Trim().Length -gt 0 -and $e -notmatch 'Warning:') { $code = 1 }
    } catch { $code = 1 }
    return @{ Code = $code; Out = $o; Err = $e }
}

function Invoke-RemoteBundleInstall {
    param(
        [Parameter(Mandatory)][string]$ServerTarget,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$BundleZip,
        [Parameter(Mandatory)][string]$InstallScript,
        [string]$SudoPassword = '',
        [string]$ExpectedVersion = '',
        [switch]$ForceServerUnfreeze
    )

    Write-DeployStep "$Label : uploading bundle to $ServerTarget..."
    $mk = Invoke-SshTimed -Target $ServerTarget -RemoteCmd "mkdir -p ~/$RemoteDeployDir" -TimeoutSec 45
    if ([int]$mk.Code -ne 0) { throw "SSH mkdir failed for $Label ($ServerTarget) exit=$($mk.Code) err=$($mk.Err)" }

    $scpBundle = Invoke-ScpTimed -TimeoutSec 180 -ArgumentList @(
        '-o','BatchMode=yes','-o','ConnectTimeout=20','-o','ControlMaster=no','-o','IdentitiesOnly=yes','-o','IdentityAgent=none',
        '-o','ServerAliveInterval=5','-o','ServerAliveCountMax=6',
        '-q', $BundleZip, "${ServerTarget}:~/$RemoteDeployDir/bundle.zip"
    )
    if ([int]$scpBundle.Code -ne 0) { throw "SCP bundle failed for $Label ($ServerTarget) exit=$($scpBundle.Code) err=$($scpBundle.Err)" }

    $instTxt = [IO.File]::ReadAllText($InstallScript).Replace("`r`n", "`n").Replace("`r", "`n")
    $instTmp = Join-Path $env:TEMP ("install-client-bundle-{0}.sh" -f $Label)
    [IO.File]::WriteAllBytes($instTmp, [Text.Encoding]::UTF8.GetBytes($instTxt))
    $scpInst = Invoke-ScpTimed -TimeoutSec 60 -ArgumentList @(
        '-o','BatchMode=yes','-o','ConnectTimeout=20','-o','ControlMaster=no','-o','IdentitiesOnly=yes','-o','IdentityAgent=none',
        '-o','ServerAliveInterval=5','-o','ServerAliveCountMax=6',
        '-q', $instTmp, "${ServerTarget}:~/$RemoteDeployDir/install-client-bundle.sh"
    )
    if ([int]$scpInst.Code -ne 0) { throw "SCP install script failed for $Label ($ServerTarget) exit=$($scpInst.Code) err=$($scpInst.Err)" }

    Write-DeployStep "$Label : installing (non-interactive, timed; never prompts)..."
    if (-not $SudoPassword) {
        throw "$Label : no stored sudo password. Put it in publish/*-deploy.local.ps1. Interactive sudo is disabled."
    }

    $pwB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SudoPassword))
    $lines = @(
        '#!/bin/bash',
        'set -e',
        ('PW=$(echo {0} | base64 -d)' -f $pwB64),
        ('RD="$HOME/{0}"' -f $RemoteDeployDir),
        'python3 - <<"PY"',
        'from pathlib import Path',
        ('p = Path.home() / "{0}" / "install-client-bundle.sh"' -f $RemoteDeployDir),
        'b = p.read_bytes() if p.exists() else b""',
        'if b.startswith(b"\xef\xbb\xbf"): b = b[3:]',
        'p.write_bytes(b.replace(b"\r\n", b"\n").replace(b"\r", b"\n"))',
        'PY',
        'chmod +x "$RD/install-client-bundle.sh"',
        'printf ''%s\n'' "$PW" | sudo -S -p '''' mkdir -p /usr/local/lib/claude-server/commands',
        'printf ''%s\n'' "$PW" | sudo -S -p '''' cp -f "$RD/install-client-bundle.sh" /usr/local/lib/claude-server/commands/install-client-bundle.sh',
        'printf ''%s\n'' "$PW" | sudo -S -p '''' chmod 755 /usr/local/lib/claude-server/commands/install-client-bundle.sh',
        $(if ($ForceServerUnfreeze) {
            # sudoers on this server explicitly blocks `sudo VAR=val cmd` env-var pass-through
            # for FORCE_UNFREEZE (confirmed live: "sudo: sorry, you are not allowed to set the
            # following environment variables: FORCE_UNFREEZE") - that restriction is deliberate
            # and must not be routed around. Removing the marker FILE via an ordinary `sudo rm`
            # is a ordinary, unrestricted sudo action (not an env-var override) and is the
            # explicit, confirmed choice for the Smart target only.
            'printf ''%s\n'' "$PW" | sudo -S -p '''' rm -f /usr/local/share/claude-client.FROZEN'
        }),
        'printf ''%s\n'' "$PW" | sudo -S -p '''' /usr/bin/bash /usr/local/lib/claude-server/commands/install-client-bundle.sh "$RD/bundle.zip"',
        'ec=$?',
        'echo INSTALL_EC=$ec',
        'exit $ec'
    )
    $wrapPath = Join-Path $env:TEMP ("remote-install-{0}.sh" -f $Label)
    [IO.File]::WriteAllBytes($wrapPath, [Text.Encoding]::UTF8.GetBytes((($lines -join "`n") + "`n")))
    $scpWrap = Invoke-ScpTimed -TimeoutSec 60 -ArgumentList @(
        '-o','BatchMode=yes','-o','ConnectTimeout=20','-o','ControlMaster=no','-o','IdentitiesOnly=yes','-o','IdentityAgent=none',
        '-o','ServerAliveInterval=5','-o','ServerAliveCountMax=6',
        '-q', $wrapPath, "${ServerTarget}:/tmp/remote-install-$Label.sh"
    )
    if ([int]$scpWrap.Code -ne 0) { throw "SCP remote install wrap failed for $Label exit=$($scpWrap.Code) err=$($scpWrap.Err)" }

    $res = Invoke-SshTimed -Target $ServerTarget -RemoteCmd "bash /tmp/remote-install-$Label.sh" -TimeoutSec 300
    $sudoExit = [int]$res.Code
    if ($res.Out) { Write-Host $res.Out }
    if ($res.Err -and $res.Err.Trim()) { Write-Host $res.Err }

    $verRes = Invoke-SshTimed -Target $ServerTarget -RemoteCmd "tr -d '\r\n' < /usr/local/share/claude-client/connect-version.txt 2>/dev/null" -TimeoutSec 20
    $remoteVer = ($verRes.Out + '').Trim()
    if ($sudoExit -ne 0 -and -not (Test-RemoteVersionMatches -RemoteVer $remoteVer -ExpectedVersion $ExpectedVersion)) {
        throw "$Label : remote sudo install failed (exit=$sudoExit). Expected v$ExpectedVersion, got '$remoteVer'. Fix: publish/*.local.ps1 passwords. No interactive sudo."
    }
    if (-not $remoteVer) {
        throw "Remote install failed for $Label ($ServerTarget): connect-version.txt missing/empty"
    }
    if ($ExpectedVersion -and $remoteVer -ne $ExpectedVersion) {
        throw "Remote version mismatch for $Label ($ServerTarget): expected v$ExpectedVersion, got v$remoteVer"
    }
    Write-DeployOk "$Label deployed v$remoteVer on $ServerTarget"
}


if (-not (Test-CommandAvailable 'ssh')) { throw 'ssh not found on PATH' }
if (-not (Test-CommandAvailable 'scp')) { throw 'scp not found on PATH' }

$installScript = Join-Path $ProjectRoot ($InstallScriptRel -replace '\\', [System.IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path $installScript)) {
    throw "Install script not found: $installScript"
}

$targets = @()
if ($DeploySmart) {
    $targets += @{ Label = 'Smart'; Server = $SmartServer; ClientRoot = $SmartClientRoot }
}
if ($DeploySepidz) {
    $targets += @{ Label = 'Sepidz'; Server = $SepidServer; ClientRoot = $SepidClientRoot }
}
if ($targets.Count -eq 0) { throw 'Nothing to deploy (both -DeploySmart and -DeploySepidz are false)' }

$failed = @()
foreach ($target in $targets) {
    Write-Host ""
    Write-Host "Deploy auto-update bundle -> $($target.Label) ($($target.Server))" -ForegroundColor White
    try {
        $stageDir = Join-Path $env:TEMP ("claude-client-bundle-{0}" -f ($target.Label.ToLowerInvariant()))
        $zipPath = Join-Path $env:TEMP ("claude-client-bundle-{0}.zip" -f ($target.Label.ToLowerInvariant()))

        Build-AutoUpdateBundleStage -ClientRoot $target.ClientRoot -StageDir $stageDir
        New-BundleZipFromDirectory -SourceDir $stageDir -ZipPath $zipPath

                        $sudoPw = ''
        if ($target.Label -eq 'Sepidz') {
            # Fail loudly if publish/sepidz-deploy.local.ps1 (or env) is missing - no hardcoded fallback.
            $sudoPw = Get-SepidzSudoPassword
        }
        if ($target.Label -eq 'Smart') { $sudoPw = Get-SmartSudoPassword }
        $expectedVer = ''
        $verFile = Join-Path $target.ClientRoot 'windows\connect-version.txt'
        if (Test-Path $verFile) {
            $expectedVer = (Get-Content -LiteralPath $verFile -Raw).Trim()
        }
        if (-not $expectedVer) {
            throw "connect-version.txt missing/empty in $($target.ClientRoot)\windows"
        }
        Write-DeployStep "$($target.Label) : expected package version v$expectedVer"
        Invoke-RemoteBundleInstall -ServerTarget $target.Server -Label $target.Label `
            -BundleZip $zipPath -InstallScript $installScript -SudoPassword $sudoPw `
            -ExpectedVersion $expectedVer `
            -ForceServerUnfreeze:($target.Label -eq 'Smart' -and $ForceServerUnfreezeSmart)

        Remove-Item $stageDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    } catch {
        Write-DeployErr "$($target.Label): $($_.Exception.Message)"
        $failed += $target.Label
        if (-not $ContinueOnDeployError) {
            throw
        }
    }
}

Write-Host ""
if ($failed.Count -gt 0) {
    Write-DeployErr ("Deploy failed for: {0}" -f ($failed -join ', '))
    exit 1
}

$labels = @($targets | ForEach-Object { $_.Label })
Write-Host ("Server deploy complete ({0})." -f ($labels -join ' + ')) -ForegroundColor Green
exit 0










