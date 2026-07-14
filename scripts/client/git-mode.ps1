# git-mode.ps1 - shared GIT_MODE helpers (dot-sourced by connect.ps1 forks)
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

function Write-GitModeLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'TRACE')][string]$Level = 'DEBUG'
    )
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog "GITMODE: $Message" $Level
    }
}

$script:TunnelBannerCacheAt = $null
$script:TunnelBannerCacheBanner = ''
$script:TunnelBannerCacheUp = $false
$script:TunnelBannerCacheInvalidate = $false
$script:LastForwardProbeAt = $null

function Clear-TunnelBannerCache {
    $script:TunnelBannerCacheAt = $null
    $script:TunnelBannerCacheBanner = ''
    $script:TunnelBannerCacheUp = $false
    $script:TunnelBannerCacheInvalidate = $true
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
    if (-not $script:TunnelBannerCacheInvalidate -and $script:TunnelBannerCacheAt) {
        $ageMs = [int]((Get-Date) - $script:TunnelBannerCacheAt).TotalMilliseconds
        if ($ageMs -lt 3000) {
            Write-GitModeLog "TUNNEL_BANNER cache hit age_ms=$ageMs banner=$($script:TunnelBannerCacheBanner)" 'TRACE'
            return $script:TunnelBannerCacheBanner
        }
    }
    $script:TunnelBannerCacheInvalidate = $false
    Write-GitModeLog "TUNNEL_BANNER_BEGIN port=$Port" 'TRACE'
    $r = SshX "timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$Port 2>/dev/null && timeout 2 nc 127.0.0.1 $Port 2>/dev/null | head -1' 2>/dev/null" 2>$null
    $banner = (($r -join '') -replace "`r",'').Trim()
    $script:TunnelBannerCacheAt = Get-Date
    $script:TunnelBannerCacheBanner = $banner
    $script:TunnelBannerCacheUp = (Test-TunnelBannerIsWindows -Banner $banner)
    Write-GitModeLog "TUNNEL_BANNER port=$Port banner=$banner" 'DEBUG'
    return $banner
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

function Remove-LocalOrphanTunnel {
    param([Parameter(Mandatory)][int]$TargetPort)
    Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "-R\s+${TargetPort}:localhost:22" } |
        ForEach-Object {
            Write-GitModeLog "ORPHAN_TUNNEL: killing local pid=$($_.ProcessId) port=$TargetPort" 'DEBUG'
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    Clear-TunnelBannerCache
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
    $preferredInt = $null
    if ($preferred -match '^\d+$') { $preferredInt = [int]$preferred }
    if ($null -ne $preferredInt) {
        Remove-LocalOrphanTunnel -TargetPort ($portBase + [int]$UidStr + $preferredInt)
    }
    $trySlots = @()
    if ($null -ne $preferredInt -and $preferredInt -le 9) { $trySlots += $preferredInt }
    0..9 | ForEach-Object { if ($_ -ne $preferredInt) { $trySlots += $_ } }
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
    if (-not $Port) { return $false }
    if (-not $script:TunnelBannerCacheInvalidate -and $script:TunnelBannerCacheAt) {
        $ageMs = [int]((Get-Date) - $script:TunnelBannerCacheAt).TotalMilliseconds
        if ($ageMs -lt 3000) {
            Write-GitModeLog "TUNNEL_UP port=$Port up=$($script:TunnelBannerCacheUp) banner=$($script:TunnelBannerCacheBanner) cache=1" 'TRACE'
            return $script:TunnelBannerCacheUp
        }
    }
    $banner = Get-TunnelBanner
    $up = $script:TunnelBannerCacheUp
    Write-GitModeLog "TUNNEL_UP port=$Port up=$up banner=$banner" 'TRACE'
    return $up
}

function Test-Tunnel {
    return (Test-TunnelUp)
}

function Get-TunnelSshProcess {
    if (-not $Port) { return $null }
    $portPat = [regex]::Escape("$Port")
    Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "-R\s+${portPat}:localhost:22" } |
        Select-Object -First 1
}

function Sync-SessionTunnelProcess {
    param([ref]$BgTunnel)
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        $now = Get-Date
        if (-not $script:LastForwardProbeAt) {
            $script:LastForwardProbeAt = $now
        } elseif (((Get-Date) - $script:LastForwardProbeAt).TotalSeconds -ge 30) {
            $script:LastForwardProbeAt = $now
            Clear-TunnelBannerCache
            $probeUp = Test-TunnelUp
            $probeBanner = $script:TunnelBannerCacheBanner
            if (-not $probeUp) {
                Write-GitModeLog "TUNNEL_DROP pid=$($BgTunnel.Value.Id) port=$Port banner=$probeBanner reason=bg_alive_forward_dead" 'WARN'
                return $false
            }
        }
        Write-GitModeLog "TUNNEL_SYNC: bg_alive pid=$($BgTunnel.Value.Id) port=$Port" 'TRACE'
        return $true
    }
    if (-not (Test-TunnelUp)) {
        Write-GitModeLog "TUNNEL_SYNC ok=0 reason=tunnel_down port=$Port" 'DEBUG'
        return $false
    }
    $cim = Get-TunnelSshProcess
    if (-not $cim) {
        Write-GitModeLog "TUNNEL_SYNC ok=1 reason=tunnel_up_no_ssh_proc port=$Port" 'TRACE'
        return $true
    }
    try {
        $proc = Get-Process -Id $cim.ProcessId -ErrorAction Stop
        if (-not $proc.HasExited) {
            $BgTunnel.Value = $proc
            $script:SessionBgTunnel = $proc
            Write-GitModeLog "TUNNEL_SYNC ok=1 reason=reattached pid=$($proc.Id) port=$Port" 'DEBUG'
            return $true
        }
    } catch {
        Write-GitModeLog "TUNNEL_SYNC ok=0 reason=proc_gone pid=$($cim.ProcessId) err=$($_.Exception.Message)" 'DEBUG'
    }
    return $false
}

function Wait-ForTunnelUp {
    param(
        [System.Diagnostics.Process]$TunnelProc,
        [switch]$Quiet
    )
    for ($i = 1; $i -le 12; $i++) {
        if ($TunnelProc -and $TunnelProc.HasExited) {
            Write-GitModeLog "TUNNEL_WAIT fail=1 attempt=$i reason=ssh_died pid=$($TunnelProc.Id)" 'WARN'
            if (-not $Quiet) { Write-Host '    Tunnel check... SSH process died' -ForegroundColor Red }
            Release-StaleTunnelPort
            return $false
        }
        $up = Test-TunnelUp
        if ($up) {
            Write-GitModeLog "TUNNEL_WAIT ok=1 attempt=$i port=$Port pid=$($TunnelProc.Id)" 'DEBUG'
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
        Write-GitModeLog "TUNNEL_WAIT ok=0 attempt=$i port=$Port" 'TRACE'
        Start-Sleep -Seconds $sleepSec
    }
    Write-GitModeLog "TUNNEL_WAIT fail=1 reason=timeout port=$Port" 'WARN'
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
            Write-GitModeLog "SCP: begin project=$ProjectId alias=$Alias" 'DEBUG'
            $scpJob = Start-Job -ScriptBlock {
                param($src, $alias)
                scp -o BatchMode=yes -o ConnectTimeout=20 -q $src "${alias}:~/.local/bin/claude-mount" 2>$null
                exit $LASTEXITCODE
            } -ArgumentList $uploadSrc, $Alias
        }
    }
    Push-ServerConnectConf -ActiveMount $ProjectId
    if ($scpJob) {
        $scpBegin = Get-Date
        $waited = Wait-Job $scpJob -Timeout 30
        if (-not $waited) {
            $scpMs = [int]((Get-Date) - $scpBegin).TotalMilliseconds
            Write-GitModeLog "SCP: timeout ERROR project=$ProjectId ms=$scpMs" 'ERROR'
            Stop-Job $scpJob -ErrorAction SilentlyContinue
        } else {
            $scpExit = ($scpJob | Receive-Job)
            $scpMs = [int]((Get-Date) - $scpBegin).TotalMilliseconds
            Write-GitModeLog "SCP: end project=$ProjectId exit=$scpExit ms=$scpMs" 'DEBUG'
            if ($scpExit -eq 0) {
                SshX 'sed -i "s/\r$//" ~/.local/bin/claude-mount 2>/dev/null; chmod +x ~/.local/bin/claude-mount' 2>$null | Out-Null
            }
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
    # Probe + claude-mount sshfs both use known_hosts_claude_mount; tunnel file is legacy.
    # Truncate dedicated files so a rotated laptop sshd host key cannot loop forever.
    SshX "ssh-keygen -f `$HOME/.ssh/known_hosts -R '[127.0.0.1]:${Port}' 2>/dev/null || true; ssh-keygen -f `$HOME/.ssh/known_hosts -R '127.0.0.1' 2>/dev/null || true; : > `$HOME/.ssh/known_hosts_claude_mount 2>/dev/null || true; : > `$HOME/.ssh/known_hosts_claude_tunnel 2>/dev/null || true; chmod 600 `$HOME/.ssh/known_hosts_claude_mount `$HOME/.ssh/known_hosts_claude_tunnel 2>/dev/null || true; true" 2>$null | Out-Null
}

function Invoke-LaptopReverseSshProbe {
    $probeBegin = Get-Date
    Write-GitModeLog "LAPTOP_SSH: probe begin port=$Port user=$LaptopUser" 'TRACE'
    $script:LastLaptopReverseSshError = ''
    if (-not $Port -or -not $LaptopUser) {
        $script:LastLaptopReverseSshError = 'missing TUNNEL_PORT or LAPTOP_USER'
        $probeMs = [int]((Get-Date) - $probeBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: probe end ok=0 ms=$probeMs err=$($script:LastLaptopReverseSshError)" 'DEBUG'
        return $false
    }
    if (-not (Test-TunnelUp)) {
        $script:LastLaptopReverseSshError = "tunnel port $Port not open on server"
        $probeMs = [int]((Get-Date) - $probeBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: probe end ok=0 ms=$probeMs err=$($script:LastLaptopReverseSshError)" 'DEBUG'
        return $false
    }
    $kh = '$HOME/.ssh/known_hosts_claude_mount'
    SshX "touch $kh 2>/dev/null; chmod 600 $kh 2>/dev/null" 2>$null | Out-Null
    # Windows OpenSSH has no `true` - use cmd exit 0 (connect.ps1 always runs on Windows laptops).
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $out = (SshX "timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$kh -i ~/.ssh/claude_laptop -p $Port ${LaptopUser}@127.0.0.1 cmd /c exit 0 2>&1") -join "`n"
        if ($LASTEXITCODE -eq 0) {
            $probeMs = [int]((Get-Date) - $probeBegin).TotalMilliseconds
            Write-GitModeLog "LAPTOP_SSH: probe end ok=1 ms=$probeMs attempt=$attempt" 'DEBUG'
            return $true
        }
        if ($attempt -eq 1 -and ($out -match 'Host key verification failed|HOST IDENTIFICATION HAS CHANGED|Offending|system administrator')) {
            Clear-ServerTunnelKnownHost
            continue
        }
        break
    }
    $detail = @($out -split "`n" | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -match 'Permission denied|Host key verification failed|Connection refused|Could not resolve|No route|authenticity of host|Please contact your system administrator|publickey|reset by peer'
    }) -join ' '
    if (-not $detail) {
        $detail = @($out -split "`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)[0]
    }
    if (-not $detail) { $detail = "server ssh exit $LASTEXITCODE" }
    $script:LastLaptopReverseSshError = $detail
    $probeMs = [int]((Get-Date) - $probeBegin).TotalMilliseconds
    Write-GitModeLog "LAPTOP_SSH: probe end ok=0 ms=$probeMs err=$detail" 'DEBUG'
    return $false
}

function Test-LaptopReverseSsh {
    return (Invoke-LaptopReverseSshProbe)
}

function Ensure-LaptopReverseSsh {
    param([string]$PubB = '')
    $ensureBegin = Get-Date
    Write-GitModeLog 'LAPTOP_SSH: ensure_begin' 'DEBUG'
    if (-not (Ensure-LaptopSshReady -PubB $PubB)) {
        $ensureMs = [int]((Get-Date) - $ensureBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: ensure_end rc=2 ms=$ensureMs reason=laptop_ssh_not_ready" 'DEBUG'
        return 2
    }
    Clear-ServerTunnelKnownHost
    if (Test-LaptopReverseSsh) {
        $ensureMs = [int]((Get-Date) - $ensureBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: ensure_end rc=0 ms=$ensureMs" 'DEBUG'
        return 0
    }
    $uidStr = ((SshX 'id -u' 2>$null) -join '').Trim() -replace '\D', ''
    if ($uidStr -and (Acquire-TunnelPort -UidStr $uidStr)) {
        Clear-ServerTunnelKnownHost
        if (Test-LaptopReverseSsh) {
            $ensureMs = [int]((Get-Date) - $ensureBegin).TotalMilliseconds
            Write-GitModeLog "LAPTOP_SSH: ensure_end rc=0 ms=$ensureMs reason=acquired_port" 'DEBUG'
            return 0
        }
    }
    Release-StaleTunnelPort
    Clear-ServerTunnelKnownHost
    $sshdSvc = Get-Service sshd -ErrorAction SilentlyContinue
    if ($sshdSvc -and $sshdSvc.Status -eq 'Running') {
        $restartBegin = Get-Date
        Write-GitModeLog 'LAPTOP_SSH: restart_sshd begin' 'DEBUG'
        Restart-Service sshd -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $restartMs = [int]((Get-Date) - $restartBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: restart_sshd end ms=$restartMs" 'DEBUG'
    }
    Clear-ServerTunnelKnownHost
    if (Test-LaptopReverseSsh) {
        $ensureMs = [int]((Get-Date) - $ensureBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: ensure_end rc=0 ms=$ensureMs reason=after_sshd_restart" 'DEBUG'
        return 0
    }
    $ensureMs = [int]((Get-Date) - $ensureBegin).TotalMilliseconds
    Write-GitModeLog "LAPTOP_SSH: ensure_end rc=1 ms=$ensureMs err=$($script:LastLaptopReverseSshError)" 'WARN'
    return 1
}

function Ensure-LaptopReverseSshCached {
    param([string]$PubB = '')
    $cachedBegin = Get-Date
    Write-GitModeLog "LAPTOP_SSH: ensure_cached begin verified=$($script:LaptopSshVerified)" 'TRACE'
    if ($script:LaptopSshVerified -and (Test-LaptopReverseSsh)) {
        $cachedMs = [int]((Get-Date) - $cachedBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: ensure_cached end rc=0 ms=$cachedMs reason=verified_cache" 'TRACE'
        return 0
    }
    if (Test-LaptopReverseSsh) {
        $script:LaptopSshVerified = $true
        $cachedMs = [int]((Get-Date) - $cachedBegin).TotalMilliseconds
        Write-GitModeLog "LAPTOP_SSH: ensure_cached end rc=0 ms=$cachedMs reason=probe_ok" 'TRACE'
        return 0
    }
    $rc = Ensure-LaptopReverseSsh -PubB $PubB
    if ($rc -eq 0) { $script:LaptopSshVerified = $true }
    else { $script:LaptopSshVerified = $false }
    $cachedMs = [int]((Get-Date) - $cachedBegin).TotalMilliseconds
    Write-GitModeLog "LAPTOP_SSH: ensure_cached end rc=$rc ms=$cachedMs" 'DEBUG'
    return $rc
}

function Invoke-RecoverIfNeeded {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [switch]$FreshTunnel
    )
    if (-not $FreshTunnel -and (Test-ProjectMountHealthy -ProjectId $ProjectId)) { return }
    $recoverBegin = Get-Date
    Write-GitModeLog "RECOVER: begin project=$ProjectId fresh_tunnel=$FreshTunnel" 'DEBUG'
    Write-Host '      -> recovering stale mounts...' -ForegroundColor DarkGray
    Clear-TunnelBannerCache
    SshX "timeout 30 $CM recover-one '$ProjectId' 2>/dev/null || timeout 30 $CM recover-if-needed '$ProjectId' 2>/dev/null || timeout 30 $CM recover 2>/dev/null || true" 2>$null | Out-Null
    $recoverMs = [int]((Get-Date) - $recoverBegin).TotalMilliseconds
    Write-GitModeLog "RECOVER: end project=$ProjectId ms=$recoverMs" 'DEBUG'
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
        Write-GitModeLog "ENSURE_TUNNEL reused=1 pid=$($BgTunnel.Value.Id) port=$Port" 'DEBUG'
        return $true
    }
    Write-GitModeLog "ENSURE_TUNNEL start port=$Port alias=$Alias had_bg=$([bool]$BgTunnel.Value)" 'DEBUG'
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        Write-GitModeLog "ENSURE_TUNNEL killing stale bg pid=$($BgTunnel.Value.Id)" 'DEBUG'
        Clear-TunnelBannerCache
        Stop-Process -Id $BgTunnel.Value.Id -Force -ErrorAction SilentlyContinue
    }
    Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "-R\s+${Port}:localhost:22" } |
        ForEach-Object {
            Write-GitModeLog "ENSURE_TUNNEL killing orphan ssh pid=$($_.ProcessId)" 'DEBUG'
            Clear-TunnelBannerCache
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
    $uidStr = ((SshX 'id -u' 2>$null) -join '').Trim() -replace '\D', ''
    if ($uidStr) { $null = Acquire-TunnelPort -UidStr $uidStr }
    Release-StaleTunnelPort
    if ($SshCfgPath) { Sanitize-SshAliasConfig -CfgPath $SshCfgPath -AliasName $Alias }
    Clear-TunnelBannerCache
    $script:LastForwardProbeAt = $null
    $BgTunnel.Value = Start-Process ssh -WindowStyle Hidden -PassThru -ArgumentList @(
        '-N', '-o', 'ExitOnForwardFailure=yes',
        '-o', 'ServerAliveInterval=20', '-o', 'ServerAliveCountMax=5',
        '-R', "$Port`:localhost:22", $Alias)
    Write-GitModeLog "ENSURE_TUNNEL spawned pid=$($BgTunnel.Value.Id) port=$Port slot=$($script:TunnelSlot)" 'INFO'
    if (Wait-ForTunnelUp -TunnelProc $BgTunnel.Value -Quiet:$WaitQuiet) {
        Write-GitModeLog "ENSURE_TUNNEL ok=1 pid=$($BgTunnel.Value.Id)" 'INFO'
        return $true
    }
    Write-GitModeLog "ENSURE_TUNNEL ok=0 reason=wait_timeout pid=$($BgTunnel.Value.Id)" 'WARN'
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        Clear-TunnelBannerCache
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
    $am = ($ActiveMount -replace "'", "'\''")
    Write-GitModeLog "PUSH_CONF laptop_user=$LaptopUser port=$Port git_mode=$mode active_mount=$ActiveMount" 'DEBUG'
    SshX "mkdir -p ~/.local/bin && printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\n' '$LaptopUser' '$Port' '$mode' '$am' > ~/.claude-connect.conf && chmod 600 ~/.claude-connect.conf || true" 2>$null | Out-Null
}

function Read-RetryQuitKey {
    param([int]$TimeoutSec = 30)
    $interactiveBegin = Get-Date
    Write-GitModeLog "INTERACTIVE: retry_quit begin timeout_sec=$TimeoutSec" 'DEBUG'
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
    $elapsedMs = [int]((Get-Date) - $interactiveBegin).TotalMilliseconds
    Write-GitModeLog "INTERACTIVE: retry_quit end key=$rk elapsed_ms=$elapsedMs" 'DEBUG'
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
    Write-GitModeLog "CLEAR_MOUNT project=$ProjectId skip_editor=$SkipEditorStop editor=$EditorCmd path=$RemotePath" 'INFO'
    if (-not $SkipEditorStop -and $EditorCmd -and $Alias -and $RemotePath) {
        if (Get-Command Stop-RemoteEditor -ErrorAction SilentlyContinue) {
            Write-GitModeLog 'CLEAR_MOUNT stopping editor' 'DEBUG'
            Stop-RemoteEditor -EditorCmd $EditorCmd -Alias $Alias -RemotePath $RemotePath
        }
    }
    Clear-TunnelBannerCache
    if ($ProjectId) {
        $pidEsc = $ProjectId -replace "'", "'\\''"
        $downBegin = Get-Date
        Write-GitModeLog "CLEAR_MOUNT: down begin project=$ProjectId" 'DEBUG'
        SshX "timeout 8 $CM down '$pidEsc' 2>/dev/null" 2>$null | Out-Null
        $downMs = [int]((Get-Date) - $downBegin).TotalMilliseconds
        Write-GitModeLog "CLEAR_MOUNT: down end ms=$downMs project=$ProjectId" 'DEBUG'
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
    if ($MountOut -match 'error:|No tunnel|not configured|unbound variable') { return $false }
    if ($MountOut -cmatch 'FAILED') { return $false }
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
    Write-GitModeLog "MOUNT_UP begin project=$ProjectId trusted=$TrustedTunnel" 'DEBUG'
    $swMount = [System.Diagnostics.Stopwatch]::StartNew()
    $mountOut = (SshX "${trusted}$CM up '$ProjectId' 2>&1") | Out-String
    $exitCode = $LASTEXITCODE
    $swMount.Stop()
    if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
        Write-ConnectPerfLog -Mark 'mount_ssh_up' -Ms $swMount.ElapsedMilliseconds -Extra "attempt=1 exit=$exitCode"
    }
    Write-GitModeLog "MOUNT_UP first exit=$exitCode out=$($mountOut.Trim() -replace '\s+',' ')" 'DEBUG'
    if (Test-MountSuccess -MountOut $mountOut -ExitCode $exitCode) {
        Write-GitModeLog "MOUNT_UP ok=1 project=$ProjectId" 'INFO'
        if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
            Write-ConnectPerfLog -Mark 'mount_total' -Ms $swMount.ElapsedMilliseconds -Extra 'path=ok attempt=1'
        }
        return @{ Ok = $true; Out = $mountOut }
    }
    if ($mountOut -match 'unbound variable|syntax error near unexpected') {
        Write-Host '      -> server mount script outdated, pushing update...' -ForegroundColor DarkGray
        if (Push-ClaudeServerScripts -ConnectScriptDir $ConnectScriptDir -Alias $Alias) {
            $swRetry = [System.Diagnostics.Stopwatch]::StartNew()
            $mountOut = (SshX "${trusted}$CM up '$ProjectId' 2>&1") | Out-String
            $exitCode = $LASTEXITCODE
            $swRetry.Stop()
            if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
                Write-ConnectPerfLog -Mark 'mount_ssh_up' -Ms $swRetry.ElapsedMilliseconds -Extra "attempt=2 exit=$exitCode"
            }
            if (Test-MountSuccess -MountOut $mountOut -ExitCode $exitCode) {
                if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
                    Write-ConnectPerfLog -Mark 'mount_total' -Ms ($swMount.ElapsedMilliseconds + $swRetry.ElapsedMilliseconds) -Extra 'path=ok attempt=2'
                }
                return @{ Ok = $true; Out = $mountOut }
            }
        }
    }
    if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
        Write-ConnectPerfLog -Mark 'mount_total' -Ms $swMount.ElapsedMilliseconds -Extra 'path=fail'
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
    $cleanOut = ($mountOut.Trim() -replace '^already mounted:\s*', '' -replace '^mounted:\s*', '')
    $cleanOut = (($cleanOut -split '\r?\n')[0]).Trim()
    if ($cleanOut -and $cleanOut -notmatch '^warn:') { Write-Host "      -> $cleanOut" -ForegroundColor DarkGray }
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
