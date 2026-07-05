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
    $p = $Rpath.Replace('\', '/').Trim()
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
    $p = $Rpath.Replace('\', '/').Trim()
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
        if ($Os -eq 'mac') { Warn "Windows path - not usable on Mac.$suffix" }
        else { Warn "Mac path - not usable on Windows.$suffix" }
        return $false
    }
    if (-not (Test-LaptopRpathExists -Rpath $Rpath)) {
        $suffix2 = if ($Num) { " - press e to edit project #$Num." } else { '' }
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

function Get-TunnelBanner {
    if (-not $Port) { return '' }
    $r = SshX "timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$Port 2>/dev/null && timeout 2 nc 127.0.0.1 $Port 2>/dev/null | head -1'" 2>$null
    return (($r -join '') -replace "`r",'').Trim()
}

function Test-TunnelBannerIsWindows {
    param([string]$Banner)
    if (-not $Banner) { return $false }
    if ($Banner -notmatch '^SSH-2\.0-') { return $false }
    return ($Banner -match 'OpenSSH_for_Windows')
}

function Test-TunnelBannerIsThisLaptop {
    param([string]$Banner)
    if (-not $Banner) { $Banner = Get-TunnelBanner }
    return (Test-TunnelBannerIsWindows -Banner $Banner)
}

function Save-TunnelSlot {
    if (-not $Cfg) { return }
    $lines = @()
    if (Test-Path $Cfg) {
        $lines = @(Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch '^TUNNEL_SLOT=' })
    }
    $lines += "TUNNEL_SLOT=$($script:TunnelSlot)"
    Set-Content -Path $Cfg -Value $lines -Encoding ASCII
}

function Sanitize-SshAliasConfig {
    param(
        [Parameter(Mandatory)][string]$CfgPath,
        [string]$AliasName = 'claude-server'
    )
    if (-not (Test-Path $CfgPath)) { return }
    $out = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($ln in (Get-Content $CfgPath -ErrorAction SilentlyContinue)) {
        if ($ln -match '^\s*Host\s+(.+)$') {
            $hosts = $matches[1].Trim() -split '\s+'
            $skip = ($hosts -contains $AliasName)
        }
        if ($skip -and $ln -match '^\s*RemoteForward\b') { continue }
        $out.Add($ln)
    }
    Set-Content -Path $CfgPath -Value $out -Encoding ASCII
}

function Release-StaleTunnelPort {
    if (-not $Port) { return }
    $banner = Get-TunnelBanner
    if (-not $banner) { return }
    if (Test-TunnelBannerIsThisLaptop -Banner $banner) { return }
    SshX "pkill -u `$USER -f ' -p ${Port} ' 2>/dev/null || true" 2>$null | Out-Null
    Start-Sleep -Seconds 1
}

function Acquire-TunnelPort {
    param([string]$UidStr)
    $portBase = 20000
    if (-not $UidStr) { return $false }
    $preferred = ''
    if ($Cfg -and (Test-Path $Cfg)) {
        $slotLine = Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -match '^TUNNEL_SLOT=' } | Select-Object -Last 1
        if ($slotLine -match 'TUNNEL_SLOT=(\d+)') { $preferred = $matches[1] }
    }
    $trySlots = @()
    if ($preferred -match '^\d+$' -and [int]$preferred -le 9) { $trySlots += [int]$preferred }
    0..9 | ForEach-Object { if ($_ -ne [int]$preferred) { $trySlots += $_ } }
    foreach ($slot in $trySlots) {
        $port = $portBase + [int]$UidStr + $slot
        if ($port -gt 65535) { continue }
        $script:Port = $port
        $banner = Get-TunnelBanner
        if (-not $banner -or (Test-TunnelBannerIsThisLaptop -Banner $banner)) {
            $script:TunnelSlot = $slot
            Save-TunnelSlot
            Push-ServerConnectConf
            return $true
        }
    }
    $script:Port = $portBase + [int]$UidStr
    $script:TunnelSlot = 0
    return $false
}

function Test-TunnelUp {
    $banner = Get-TunnelBanner
    return (Test-TunnelBannerIsWindows -Banner $banner)
}

function Test-Tunnel {
    return (Test-TunnelUp)
}

function Wait-ForTunnelUp {
    param(
        [System.Diagnostics.Process]$TunnelProc,
        [switch]$Quiet
    )
    for ($i = 1; $i -le 12; $i++) {
        if ($TunnelProc -and $TunnelProc.HasExited) {
            if (-not $Quiet) { Write-Host '    Tunnel check... SSH process died' -ForegroundColor Red }
            Release-StaleTunnelPort
            return $false
        }
        if (Test-TunnelUp) {
            if (-not $Quiet) {
                $label = if ($i -eq 1) { '    Tunnel check...' } else { "    Tunnel check $i/12..." }
                Write-Host -NoNewline $label -ForegroundColor DarkGray
                Write-Host " port $Port is open" -ForegroundColor Green
            }
            return $true
        }
        if ($i -ge 12) { break }
        $sleepSec = [math]::Min(1.5, 0.25 + ($i - 1) * 0.2)
        if (-not $Quiet) {
            Write-Host "    Tunnel check $i/12... port $Port not open yet" -ForegroundColor DarkGray
        }
        Start-Sleep -Seconds $sleepSec
    }
    return $false
}

function Get-ClaudeMountSrc {
    param([Parameter(Mandatory)][string]$ConnectScriptDir)
    $direct = Join-Path $ConnectScriptDir 'claude-mount.sh'
    if (Test-Path $direct) { return $direct }
    foreach ($rel in @('mac\claude-mount.sh', '..\mac\claude-mount.sh')) {
        try {
            $p = [System.IO.Path]::GetFullPath((Join-Path $ConnectScriptDir $rel))
            if (Test-Path $p) { return $p }
        } catch { }
    }
    $dir = Resolve-ServerScriptDir -ConnectScriptDir $ConnectScriptDir
    if ($dir) {
        $src = Join-Path $dir 'claude-mount.sh'
        if (Test-Path $src) { return $src }
    }
    return $null
}

function Get-LfNormalizedShCopy {
    param([Parameter(Mandatory)][string]$Src)
    if (-not (Test-Path $Src)) { return $Src }
    $raw = [System.IO.File]::ReadAllText($Src)
    if ($raw -notmatch "`r") { return $Src }
    $tmp = Join-Path $env:TEMP ("claude-lf-" + [System.IO.Path]::GetFileName($Src))
    [System.IO.File]::WriteAllText($tmp, ($raw -replace "`r`n", "`n" -replace "`r", "`n"))
    return $tmp
}

function Push-ClaudeMountIfChanged {
    param(
        [Parameter(Mandatory)][string]$Src,
        [Parameter(Mandatory)][string]$Alias
    )
    if (-not (Test-Path $Src)) { return }
    $uploadSrc = Get-LfNormalizedShCopy -Src $Src
    $localHash = (Get-FileHash -Algorithm SHA256 -Path $uploadSrc).Hash
    $remoteHash = ((SshX "sha256sum ~/.local/bin/claude-mount 2>/dev/null | awk '{print `$1}'") -join '').Trim()
    if ($localHash -and $remoteHash -and ($localHash.ToLower() -eq $remoteHash.ToLower())) { return }
    scp -o BatchMode=yes -o ConnectTimeout=20 -q $uploadSrc "${Alias}:~/.local/bin/claude-mount" 2>$null
    if ($LASTEXITCODE -eq 0) {
        SshX 'sed -i "s/\r$//" ~/.local/bin/claude-mount 2>/dev/null; chmod +x ~/.local/bin/claude-mount' 2>$null | Out-Null
    }
}

function Prepare-ServerSessionParallel {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [string]$MountSrc = '',
        [Parameter(Mandatory)][string]$Alias
    )
    $script:ActiveProjectId = $ProjectId
    $scpJob = $null
    $needScp = $false
    if ($MountSrc -and (Test-Path $MountSrc)) {
        $uploadSrc = Get-LfNormalizedShCopy -Src $MountSrc
        $localHash = (Get-FileHash -Algorithm SHA256 -Path $uploadSrc).Hash
        $remoteHash = ((SshX "sha256sum ~/.local/bin/claude-mount 2>/dev/null | awk '{print `$1}'") -join '').Trim()
        $needScp = -not ($localHash -and $remoteHash -and ($localHash.ToLower() -eq $remoteHash.ToLower()))
        if ($needScp) {
            $scpJob = Start-Job -ScriptBlock {
                param($src, $alias)
                scp -o BatchMode=yes -o ConnectTimeout=20 -q $src "${alias}:~/.local/bin/claude-mount" 2>$null
                exit $LASTEXITCODE
            } -ArgumentList $uploadSrc, $Alias
        }
    }
    Push-ServerConnectConf -ActiveMount $ProjectId
    if ($scpJob) {
        Wait-Job $scpJob | Out-Null
        if (($scpJob | Receive-Job) -eq 0) {
            SshX 'sed -i "s/\r$//" ~/.local/bin/claude-mount 2>/dev/null; chmod +x ~/.local/bin/claude-mount' 2>$null | Out-Null
        }
        Remove-Job $scpJob -Force
    }
}

function Test-ProjectMountHealthy {
    param([Parameter(Mandatory)][string]$ProjectId)
    $out = ((SshX "$CM check '$ProjectId' 2>/dev/null") -join '').Trim()
    return ($out -eq 'ok')
}

function Clear-ServerTunnelKnownHost {
    if (-not $Port) { return }
    SshX "ssh-keygen -f `$HOME/.ssh/known_hosts -R '[127.0.0.1]:${Port}' 2>/dev/null; ssh-keygen -f `$HOME/.ssh/known_hosts -R '127.0.0.1' 2>/dev/null; rm -f `$HOME/.ssh/known_hosts_claude_tunnel 2>/dev/null; true" 2>$null | Out-Null
}

function Invoke-LaptopReverseSshProbe {
    $script:LastLaptopReverseSshError = ''
    if (-not $Port -or -not $LaptopUser) {
        $script:LastLaptopReverseSshError = 'missing TUNNEL_PORT or LAPTOP_USER'
        return $false
    }
    if (-not (Test-TunnelUp)) {
        $script:LastLaptopReverseSshError = "tunnel port $Port not open on server"
        return $false
    }
    $kh = '$HOME/.ssh/known_hosts_claude_mount'
    SshX "touch $kh 2>/dev/null; chmod 600 $kh 2>/dev/null" 2>$null | Out-Null
    # Windows OpenSSH has no `true` — use cmd exit 0 (connect.ps1 always runs on Windows laptops).
    $out = (SshX "timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$kh -i ~/.ssh/claude_laptop -p $Port ${LaptopUser}@127.0.0.1 cmd /c exit 0 2>&1") -join "`n"
    if ($LASTEXITCODE -eq 0) { return $true }
    $detail = @($out -split "`n" | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -match 'Permission denied|Host key verification failed|Connection refused|Could not resolve|No route|authenticity of host|Please contact your system administrator|publickey|reset by peer'
    }) -join ' '
    if (-not $detail) {
        $detail = @($out -split "`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)[0]
    }
    if (-not $detail) { $detail = "server ssh exit $LASTEXITCODE" }
    $script:LastLaptopReverseSshError = $detail
    return $false
}

function Test-LaptopReverseSsh {
    return (Invoke-LaptopReverseSshProbe)
}

function Ensure-LaptopReverseSsh {
    param([string]$PubB = '')
    if (-not (Ensure-LaptopSshReady -PubB $PubB)) { return 2 }
    Clear-ServerTunnelKnownHost
    if (Test-LaptopReverseSsh) { return 0 }
    $uidStr = ((SshX 'id -u' 2>$null) -join '').Trim() -replace '\D', ''
    if ($uidStr -and (Acquire-TunnelPort -UidStr $uidStr)) {
        Clear-ServerTunnelKnownHost
        if (Test-LaptopReverseSsh) { return 0 }
    }
    Release-StaleTunnelPort
    Clear-ServerTunnelKnownHost
    $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
    if ($sshdSvc -and $sshdSvc.Status -eq 'Running') {
        Restart-Service sshd -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    Clear-ServerTunnelKnownHost
    if (Test-LaptopReverseSsh) { return 0 }
    return 1
}

function Ensure-LaptopReverseSshCached {
    param([string]$PubB = '')
    if ($script:LaptopSshVerified -and (Test-LaptopReverseSsh)) { return 0 }
    if (Test-LaptopReverseSsh) {
        $script:LaptopSshVerified = $true
        return 0
    }
    $rc = Ensure-LaptopReverseSsh -PubB $PubB
    if ($rc -eq 0) { $script:LaptopSshVerified = $true }
    else { $script:LaptopSshVerified = $false }
    return $rc
}

function Invoke-RecoverIfNeeded {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [switch]$FreshTunnel
    )
    if (-not $FreshTunnel -and (Test-ProjectMountHealthy -ProjectId $ProjectId)) { return }
    Write-Host '      -> recovering stale mounts...' -ForegroundColor DarkGray
    SshX "timeout 30 $CM recover-if-needed '$ProjectId' 2>/dev/null || timeout 30 $CM recover 2>/dev/null || true" 2>$null | Out-Null
}

function Ensure-SessionTunnel {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [string]$SshCfgPath = '',
        [ref]$BgTunnel,
        [ref]$TunnelReused,
        [switch]$WaitQuiet
    )
    $TunnelReused.Value = $false
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited -and (Test-TunnelUp)) {
        $TunnelReused.Value = $true
        return $true
    }
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        Stop-Process -Id $BgTunnel.Value.Id -Force -ErrorAction SilentlyContinue
    }
    Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "-R\s+${Port}:localhost:22" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    $uidStr = ((SshX 'id -u' 2>$null) -join '').Trim() -replace '\D', ''
    if ($uidStr) { $null = Acquire-TunnelPort -UidStr $uidStr }
    Release-StaleTunnelPort
    if ($SshCfgPath) { Sanitize-SshAliasConfig -CfgPath $SshCfgPath -AliasName $Alias }
    $BgTunnel.Value = Start-Process ssh -WindowStyle Hidden -PassThru -ArgumentList @(
        '-N', '-o', 'ExitOnForwardFailure=yes',
        '-o', 'ServerAliveInterval=20', '-o', 'ServerAliveCountMax=5',
        '-R', "$Port`:localhost:22", $Alias)
    if (Wait-ForTunnelUp -TunnelProc $BgTunnel.Value -Quiet:$WaitQuiet) { return $true }
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        Stop-Process -Id $BgTunnel.Value.Id -Force -ErrorAction SilentlyContinue
    }
    $BgTunnel.Value = $null
    return $false
}

function Initialize-SessionBgTunnel {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [string]$SshCfgPath = '',
        [switch]$Quiet
    )
    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited -and (Test-TunnelUp)) {
        return $true
    }
    $reused = $false
    $tunnel = $null
    if (Ensure-SessionTunnel -Alias $Alias -SshCfgPath $SshCfgPath -BgTunnel ([ref]$tunnel) -TunnelReused ([ref]$reused) -WaitQuiet:$Quiet) {
        $script:SessionBgTunnel = $tunnel
        return $true
    }
    $script:SessionBgTunnel = $null
    return $false
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
        Push-ClaudeMountIfChanged -Src $src -Alias $Alias
    }
    if (Test-Path $gitSrc) {
        $localGit = (Get-FileHash -Algorithm SHA256 -Path $gitSrc).Hash
        $remoteGit = ((SshX "sha256sum ~/.local/bin/claude-git-setup 2>/dev/null | awk '{print `$1}'") -join '').Trim()
        if (-not ($localGit -and $remoteGit -and ($localGit.ToLower() -eq $remoteGit.ToLower()))) {
            scp -o BatchMode=yes -o ConnectTimeout=30 -q $gitSrc "${Alias}:~/.local/bin/claude-git-setup" 2>$null
            if ($LASTEXITCODE -ne 0) { $pushOk = $false; $script:pendingFixes += 'claude-git-setup push failed' }
        }
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
        [Parameter(Mandatory)][string]$Alias,
        [switch]$TrustedTunnel
    )
    $trusted = if ($TrustedTunnel) { 'CLAUDE_TRUSTED_TUNNEL=1 ' } else { '' }
    $mountOut = (SshX "${trusted}$CM up '$ProjectId' 2>&1") | Out-String
    $exitCode = $LASTEXITCODE
    if (Test-MountSuccess -MountOut $mountOut -ExitCode $exitCode) {
        return @{ Ok = $true; Out = $mountOut }
    }
    if ($mountOut -match 'unbound variable|syntax error near unexpected') {
        Write-Host '      -> server mount script outdated, pushing update...' -ForegroundColor DarkGray
        if (Push-ClaudeServerScripts -ConnectScriptDir $ConnectScriptDir -Alias $Alias) {
            $mountOut = (SshX "${trusted}$CM up '$ProjectId' 2>&1") | Out-String
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
    $mountOut = (SshX "CLAUDE_TRUSTED_TUNNEL=1 $CM up '$ProjectId' 2>&1") | Out-String
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
