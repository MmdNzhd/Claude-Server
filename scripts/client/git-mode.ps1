# git-mode.ps1 — shared GIT_MODE helpers (dot-sourced by connect.ps1 forks)
# Requires: $CfgDir, functions SshX, Test-Tunnel, Warn; $LaptopUser, $Port, $CM at call time

function Get-GitMode {
    $gitConf = [System.IO.Path]::Combine($CfgDir, 'git.conf')
    if (-not (Test-Path $gitConf)) { return 'hide' }
    $saved = (Get-Content $gitConf -Raw -ErrorAction SilentlyContinue).Trim().ToLower()
    if ($saved -match '^(server|on|yes|1|slow)$') { return 'server' }
    return 'hide'
}

function Get-GitModeLabel {
    param([string]$Mode = (Get-GitMode))
    if ($Mode -eq 'server') { return 'SLOW' }
    return 'FAST'
}


function Test-LaptopRpathCompatible {
    param(
        [string]$Rpath,
        [ValidateSet('mac','windows')][string]$Os = 'windows'
    )
    if (-not $Rpath) { return $false }
    $p = ($Rpath -replace '\','/').Trim()
    if ($Os -eq 'mac') {
        if ($p -match '^[A-Za-z]:') { return $false }
    } else {
        if ($p -match '^/Users/') { return $false }
    }
    return $true
}

function Test-LaptopRpathExists {
    param([string]$Rpath)
    if (-not $Rpath) { return $false }
    $p = ($Rpath -replace '\','/').Trim()
    if ($p -match '^[A-Za-z]:$') { $p = "$p/" }
    return (Test-Path -LiteralPath $p)
}

function Get-LaptopRpathOsHint {
    param(
        [string]$Rpath,
        [ValidateSet('mac','windows')][string]$Os = 'windows'
    )
    if (Test-LaptopRpathCompatible -Rpath $Rpath -Os $Os) { return '' }
    if ($Os -eq 'mac') { return 'Windows only' }
    return 'Mac only'
}

function Warn-InvalidProjectRpath {
    param(
        [string]$Rpath,
        [string]$Num = '',
        [ValidateSet('mac','windows')][string]$Os = 'windows'
    )
    $suffix = if ($Num) { " Press e to edit project #$Num." } else { '' }
    if (-not (Test-LaptopRpathCompatible -Rpath $Rpath -Os $Os)) {
        if ($Os -eq 'mac') { Warn "Windows path — not usable on Mac.$suffix" }
        else { Warn "Mac path — not usable on Windows.$suffix" }
        return $false
    }
    if (-not (Test-LaptopRpathExists -Rpath $Rpath)) {
        $suffix2 = if ($Num) { " — press e to edit project #$Num." } else { '' }
        Warn "Folder not found on this laptop: $Rpath$suffix2"
        return $false
    }
    return $true
}

function Get-MountsForLaptop {
    param(
        [ValidateSet('mac','windows')][string]$Os = 'windows',
        [array]$Mounts = @()
    )
    if ($Mounts.Count -eq 0) { $Mounts = @(Get-Mounts) }
    return @($Mounts | Where-Object { Test-LaptopRpathCompatible -Rpath $_.Rpath -Os $Os })
}

function Get-SkippedMountCountForLaptop {
    param(
        [ValidateSet('mac','windows')][string]$Os = 'windows',
        [array]$Mounts = @()
    )
    if ($Mounts.Count -eq 0) { $Mounts = @(Get-Mounts) }
    return @($Mounts | Where-Object { -not (Test-LaptopRpathCompatible -Rpath $_.Rpath -Os $Os) }).Count
}

function Get-MountListStepLabel {
    param(
        [ValidateSet('mac','windows')][string]$Os = 'windows',
        [array]$Mounts = @()
    )
    if ($Mounts.Count -eq 0) { $Mounts = @(Get-Mounts) }
    $visible = @(Get-MountsForLaptop -Os $Os -Mounts $Mounts).Count
    $hidden = Get-SkippedMountCountForLaptop -Os $Os -Mounts $Mounts
    if ($hidden -gt 0) {
        if ($Os -eq 'mac') { return "$visible for this Mac ($hidden Windows-only hidden)" }
        return "$visible for this PC ($hidden Mac-only hidden)"
    }
    return "$visible project(s)"
}

function Read-PostDisconnectKey {
    param(
        [char]$DefaultChar = 'M',
        [int]$TimeoutSec = 10
    )
    Write-Host ''
    Write-Host '    Disconnected. What would you like to do?' -ForegroundColor Cyan
    Write-Host '    M = project menu   C = connect again   X = exit' -ForegroundColor DarkGray
    Write-Host ''

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $left = [math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
        if ($left -le $TimeoutSec -and $left -gt 0) {
            Write-Host "`r    Default $DefaultChar in ${left}s...   " -NoNewline -ForegroundColor DarkGray
        }
        if ([Console]::KeyAvailable) {
            Write-Host ''
            $ki = [Console]::ReadKey($true)
            $kc = $ki.KeyChar.ToString().ToLower()
            if ($kc -eq 'm' -or $ki.Key -eq [ConsoleKey]::M) { return 'm' }
            if ($kc -eq 'c' -or $ki.Key -eq [ConsoleKey]::C) { return 'c' }
            if ($kc -eq 'x' -or $ki.Key -eq [ConsoleKey]::X) { return 'x' }
        }
        Start-Sleep -Milliseconds 200
    }
    Write-Host ''
    Write-Host "    Default $DefaultChar" -ForegroundColor DarkGray
    return $DefaultChar.ToString().ToLower()
}

function Push-ServerConnectConf {
    param(
        [string]$GitMode = (Get-GitMode),
        [string]$ActiveMount = ''
    )
    $mode = if ($GitMode -eq 'server') { 'server' } else { 'hide' }
    $am = ($ActiveMount -replace "'", "'\\''")
    SshX "mkdir -p ~/.local/bin && printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\n' '$LaptopUser' '$Port' '$mode' '$am' > ~/.claude-connect.conf && chmod 600 ~/.claude-connect.conf || true" 2>$null | Out-Null
}

function Read-RetryQuitKey {
    param([int]$TimeoutSec = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $rk = ''
    while ($rk -ne 'r' -and $rk -ne 'q') {
        if ([Console]::KeyAvailable) {
            $ki2 = [Console]::ReadKey($true)
            if ($ki2.KeyChar.ToString().ToLower() -eq 'r' -or $ki2.Key -eq [ConsoleKey]::R) { $rk = 'r' }
            elseif ($ki2.KeyChar.ToString().ToLower() -eq 'q' -or $ki2.Key -eq [ConsoleKey]::Q) { $rk = 'q' }
        } elseif ((Get-Date) -gt $deadline) {
            $rk = 'q'
            break
        } else {
            Start-Sleep -Milliseconds 200
        }
    }
    return $rk
}

function Show-MountGitWarn {
    param([string]$MountOut)
    if ($MountOut -match '(?m)^warn: git hide failed') {
        $gitWarn = ($MountOut -split "`n" | Where-Object { $_ -match '^warn: git hide failed' } | Select-Object -First 1)
        if ($gitWarn) { Warn $gitWarn.Trim() }
    }
    if ($MountOut -match '(?m)^warn: laptop tunnel down') {
        $tw = ($MountOut -split "`n" | Where-Object { $_ -match '^warn: laptop tunnel' } | Select-Object -First 1)
        if ($tw) { Warn $tw.Trim() }
    }
}

function Unmount-OtherProjects {
    param([Parameter(Mandatory)][string]$KeepProjectId)
    SshX "$CM down-others '$KeepProjectId'" 2>$null | Out-Null
}

function Clear-SessionMount {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [string]$EditorCmd = '',
        [string]$Alias = '',
        [string]$RemotePath = '',
        [switch]$SkipEditorStop
    )
    if (-not $SkipEditorStop -and $EditorCmd -and $Alias -and $RemotePath) {
        if (Get-Command Stop-RemoteEditor -ErrorAction SilentlyContinue) {
            Stop-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
        }
    }
    if ($ProjectId) {
        $pidEsc = $ProjectId -replace "'", "'\\''"
        ssh -n -o BatchMode=yes -o ConnectTimeout=5 $Alias "timeout 8 $CM down '$pidEsc' 2>/dev/null" 2>$null | Out-Null
    }
    if ($Port) { Push-ServerConnectConf -ActiveMount '' }
}

function Resolve-ServerScriptDir {
    param([Parameter(Mandatory)][string]$ConnectScriptDir)
    foreach ($rel in @('..\server', '..\..\server', '..\..\..\server')) {
        try {
            $d = [System.IO.Path]::GetFullPath((Join-Path $ConnectScriptDir $rel))
            if (Test-Path ([System.IO.Path]::Combine($d, 'claude-mount.sh'))) { return $d }
        } catch { }
    }
    try {
        $d = $ConnectScriptDir
        for ($i = 0; $i -lt 8; $i++) {
            $repoServer = [System.IO.Path]::Combine($d, 'scripts', 'server')
            if (Test-Path ([System.IO.Path]::Combine($repoServer, 'claude-mount.sh'))) { return $repoServer }
            $adjServer = [System.IO.Path]::Combine($d, 'server')
            if (Test-Path ([System.IO.Path]::Combine($adjServer, 'claude-mount.sh'))) { return $adjServer }
            $parent = Split-Path $d -Parent
            if (-not $parent -or $parent -eq $d) { break }
            $d = $parent
        }
    } catch { }
    return $null
}

function Push-ClaudeServerScripts {
    param(
        [Parameter(Mandatory)][string]$ConnectScriptDir,
        [Parameter(Mandatory)][string]$Alias
    )
    $dir = Resolve-ServerScriptDir -ConnectScriptDir $ConnectScriptDir
    if (-not $dir) { return $false }
    $src = [System.IO.Path]::Combine($dir, 'claude-mount.sh')
    $gitSrc = [System.IO.Path]::Combine($dir, 'claude-git-setup.sh')
    $pushOk = $true
    if (Test-Path $src) {
        scp -o BatchMode=yes -o ConnectTimeout=30 -q $src "${Alias}:~/.local/bin/claude-mount" 2>$null
        if ($LASTEXITCODE -ne 0) { $pushOk = $false; $script:pendingFixes += 'claude-mount push failed' }
    }
    if (Test-Path $gitSrc) {
        scp -o BatchMode=yes -o ConnectTimeout=30 -q $gitSrc "${Alias}:~/.local/bin/claude-git-setup" 2>$null
        if ($LASTEXITCODE -ne 0) { $pushOk = $false; $script:pendingFixes += 'claude-git-setup push failed' }
    }
    $chmodCmd = @()
    if (Test-Path $src) { $chmodCmd += "chmod +x ~/.local/bin/claude-mount; grep -q 'CLAUDE_LOCAL_BIN_PATH' ~/.bashrc || printf '\n# CLAUDE_LOCAL_BIN_PATH\nexport PATH=`$HOME/.local/bin:`$PATH\n' >> ~/.bashrc" }
    if (Test-Path $gitSrc) { $chmodCmd += 'chmod +x ~/.local/bin/claude-git-setup' }
    if ($chmodCmd.Count -gt 0) { SshX ($chmodCmd -join '; ') 2>$null | Out-Null }
    return $pushOk
}

function Test-MountSuccess {
    param(
        [string]$MountOut,
        [int]$ExitCode = 0
    )
    if ($MountOut -match 'error:|FAILED|No tunnel|not configured|unbound variable') { return $false }
    if ($ExitCode -eq 0) { return $true }
    if ($MountOut -match 'already mounted:') { return $true }
    return $false
}

function Invoke-MountProject {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$ConnectScriptDir,
        [Parameter(Mandatory)][string]$Alias
    )
    $mountOut = (SshX "$CM up '$ProjectId' 2>&1") | Out-String
    $exitCode = $LASTEXITCODE
    if (Test-MountSuccess -MountOut $mountOut -ExitCode $exitCode) {
        return @{ Ok = $true; Out = $mountOut }
    }
    if ($mountOut -match 'unbound variable|syntax error near unexpected') {
        Write-Host '      -> server mount script outdated, pushing update...' -ForegroundColor DarkGray
        if (Push-ClaudeServerScripts -ConnectScriptDir $ConnectScriptDir -Alias $Alias) {
            $mountOut = (SshX "$CM up '$ProjectId' 2>&1") | Out-String
            $exitCode = $LASTEXITCODE
            if (Test-MountSuccess -MountOut $mountOut -ExitCode $exitCode) {
                return @{ Ok = $true; Out = $mountOut }
            }
        }
    }
    return @{ Ok = $false; Out = $mountOut }
}

function Remount-ProjectGit {
    param([string]$ProjectId)
    if (-not $ProjectId) { return $false }
    Write-Host ''
    Write-Host '    Remounting with git mode...' -ForegroundColor Cyan
    SshX "$CM down '$ProjectId'" 2>$null | Out-Null
    Write-Host '      -> recovering stale mounts...' -ForegroundColor DarkGray
    SshX "$CM recover" 2>$null | Out-Null
    if (-not (Test-Tunnel)) {
        Warn 'Tunnel dropped during remount - press R to reconnect'
        return $false
    }
    $mountOut = (SshX "$CM up '$ProjectId' 2>&1") | Out-String
    Show-MountGitWarn $mountOut
    $mountOk = Test-MountSuccess -MountOut $mountOut -ExitCode $LASTEXITCODE
    if (-not $mountOk) {
        Warn ($mountOut.Trim())
        return $false
    }
    $cleanOut = ($mountOut.Trim() -replace '^already mounted:\s*', '')
    if ($cleanOut) { Write-Host "      -> $cleanOut" -ForegroundColor DarkGray }
    Write-Host "    Git mode: $(Get-GitMode) applied." -ForegroundColor Green
    Write-Host ''
    return $true
}

function Configure-GitMode {
    Write-Host ''
    Write-Host '    Git on server (SSHFS)' -ForegroundColor White
    Write-Host ''
    $cur = Get-GitMode
    $curLabel = Get-GitModeLabel -Mode $cur
    Write-Host "    Current: $curLabel ($(if ($cur -eq 'server') { 'full git over SSHFS' } else { '.git hidden on laptop' }))" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '    1  FAST - hide .git on laptop [default]' -ForegroundColor DarkGray
    Write-Host '    2  SLOW - keep .git on mount for git on server' -ForegroundColor DarkGray
    Write-Host ''
    $choice = (Read-Host '    >').Trim().ToLower()
    switch ($choice) {
        { $_ -in '1', 'off', 'hide', 'fast', '' } {
            Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'git.conf')) -Value 'hide' -Encoding ASCII | Out-Null
        }
        { $_ -in '2', 'on', 'server', 'slow' } {
            Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'git.conf')) -Value 'server' -Encoding ASCII | Out-Null
        }
        default { Warn 'Invalid choice.'; return }
    }
    if ($Port) {
        $am = if ($script:ActiveProjectId) { $script:ActiveProjectId } else { '' }
        Push-ServerConnectConf -ActiveMount $am
    }
    Write-Host ''
    $savedLabel = Get-GitModeLabel
    Write-Host "    Saved: git $savedLabel." -ForegroundColor Green
    if ($script:ActiveProjectId) {
        Push-ServerConnectConf -ActiveMount $script:ActiveProjectId
        Remount-ProjectGit -ProjectId $script:ActiveProjectId | Out-Null
    } else {
        Write-Host '    Reconnect to apply on first mount.' -ForegroundColor DarkGray
    }
    Write-Host ''
}
