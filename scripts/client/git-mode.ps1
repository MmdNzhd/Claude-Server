# git-mode.ps1 - shared GIT_MODE helpers (dot-sourced by connect.ps1 forks)
# Requires: $CfgDir, functions SshX, Test-Tunnel, Warn; $LaptopUser, $Port, $CM at call time

function Get-GitMode {
    $gitConf = [System.IO.Path]::Combine($CfgDir, 'git.conf')
    if (-not (Test-Path $gitConf)) { return 'off' }
    $saved = (Get-Content $gitConf -Raw -ErrorAction SilentlyContinue).Trim().ToLower()
    if ($saved -match '^(server|on|yes|1|slow)$') { return 'server' }
    if ($saved -match '^(hide|fast)$') { return 'hide' }
    return 'off'
}

function Get-GitModeLabel {
    param([string]$Mode = (Get-GitMode))
    switch ($Mode) {
        'server' { return 'SLOW' }
        'hide'   { return 'HIDE' }
        default  { return 'OFF' }
    }
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

function Get-TunnelSessionDiagSuffix {
    $proj = if ($script:ActiveProjectId) { " project=$($script:ActiveProjectId)" } else { '' }
    return "${proj} soft_fail=$($script:TunnelSoftFailCount) sync_fail=$($script:TunnelSyncFailCount)"
}

function Write-TunnelDropLog {
    param(
        [Parameter(Mandatory)][string]$Reason,
        [int]$Pid = 0,
        [Nullable[bool]]$TcpOpen = $null,
        [Nullable[bool]]$TunnelUp = $null,
        [Nullable[bool]]$TunnelSyncOk = $null,
        [string]$Banner = $null,
        [string]$ProjectId = '',
        [bool]$EditorOpened = $false,
        [bool]$EditorSeen = $false,
        [int]$RecoveryGen = -1,
        [string]$DropCause = ''
    )
    if ($Reason -ne 'auto_reconnect') {
        $script:LastTunnelSyncDropReason = $Reason
    }
    if (-not $ProjectId -and $script:ActiveProjectId) { $ProjectId = [string]$script:ActiveProjectId }
    if (-not $ProjectId) { $ProjectId = '?' }
    if ($RecoveryGen -lt 0) { $RecoveryGen = [int]$script:RecoveryGeneration }
    if ($null -eq $TcpOpen) {
        try {
            if (Get-Command Test-TunnelPortTcpOpen -ErrorAction SilentlyContinue) {
                $TcpOpen = [bool](Test-TunnelPortTcpOpen)
            } else { $TcpOpen = $false }
        } catch { $TcpOpen = $false }
    }
    if ($null -eq $TunnelUp) {
        try {
            if (Get-Command Test-TunnelUp -ErrorAction SilentlyContinue) {
                $TunnelUp = [bool](Test-TunnelUp -Retries 1)
            } else { $TunnelUp = $false }
        } catch { $TunnelUp = $false }
    }
    if ($null -eq $TunnelSyncOk) { $TunnelSyncOk = $false }
    $cause = $DropCause
    if (-not $cause -and $Reason -eq 'auto_reconnect' -and $script:LastTunnelSyncDropReason) {
        $cause = [string]$script:LastTunnelSyncDropReason
    }
    $parts = @(
        'TUNNEL_DROP'
        "reason=$Reason"
        "soft_fail=$($script:TunnelSoftFailCount)"
        "sync_fail=$($script:TunnelSyncFailCount)"
        "tcp_open=$TcpOpen"
        "tunnel_up=$TunnelUp"
        "tunnel_sync_ok=$TunnelSyncOk"
        "project=$ProjectId"
        "editor_opened=$EditorOpened"
        "editor_seen=$EditorSeen"
        "gen=$RecoveryGen"
    )
    if ($Port) { $parts += "port=$Port" }
    if ($Pid -gt 0) { $parts += "bg_pid=$Pid" }
    if ($cause) { $parts += "drop_cause=$cause" }
    if ($null -ne $Banner) {
        $parts += "banner=$(if ($Banner) { $Banner } else { '(empty)' })"
    }
    $msg = $parts -join ' '
    if (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
        Write-ConnectLog $msg 'WARN'
    } else {
        Write-GitModeLog $msg 'WARN'
    }
}

$script:TunnelBannerCacheAt = $null
$script:TunnelBannerCacheBanner = ''
$script:TunnelBannerCacheUp = $false
$script:TunnelBannerCacheInvalidate = $false
$script:LastForwardProbeAt = $null
$script:TunnelMissCount = 0
$script:TunnelSyncFailCount = 0
$script:TunnelSoftFailCount = 0
$script:LastTunnelSpawnSuccessAt = $null
$script:LastTunnelSpawnSuccessPort = $null
$script:LastTunnelSpawnPid = $null
$script:LastTunnelExitLoggedPid = $null

function Clear-TunnelBannerCache {
    $script:TunnelBannerCacheAt = $null
    $script:TunnelBannerCacheBanner = ''
    $script:TunnelBannerCacheUp = $false
    $script:TunnelBannerCacheInvalidate = $true
    # Bug 51 companion: drop throttled ssh.exe CIM cache when tunnel state changes.
    $script:TunnelSshCimCache = $null
    $script:TunnelSshCimCacheAt = $null
    $script:TunnelSshCimCachePort = $null
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
            $kcRaw = $ki.KeyChar.ToString()
            $code = if ($kcRaw.Length -eq 1) { [int][char]$kcRaw[0] } else { 0 }
            $ascii = ($code -ge 32 -and $code -le 126)
            $kc = if ($ascii) { $kcRaw.ToLowerInvariant() } else { '' }
            $useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
            if ($kc -eq 'm' -or ($useVk -and $ki.Key -eq [ConsoleKey]::M)) { return 'm' }
            if ($kc -eq 'c' -or ($useVk -and $ki.Key -eq [ConsoleKey]::C)) { return 'c' }
            if ($kc -eq 'x' -or ($useVk -and $ki.Key -eq [ConsoleKey]::X)) { return 'x' }
        }
        Start-Sleep -Milliseconds 200
    }
    Write-Host ''
    Write-Host "    Default $DefaultChar" -ForegroundColor DarkGray
    return $DefaultChar.ToString().ToLower()
}

function Get-TunnelBanner {
    if (-not $Port) { return '' }
    # Positive cache only A<"�<"�,<"�<"�?? never cache empty/false for 3s (poisoned DROP1 recovery).
    if (-not $script:TunnelBannerCacheInvalidate -and $script:TunnelBannerCacheAt -and $script:TunnelBannerCacheUp) {
        $ageMs = [int]((Get-Date) - $script:TunnelBannerCacheAt).TotalMilliseconds
        if ($ageMs -lt 3000) {
            Write-GitModeLog "TUNNEL_BANNER cache hit age_ms=$ageMs banner=$($script:TunnelBannerCacheBanner)" 'TRACE'
            return $script:TunnelBannerCacheBanner
        }
    }
    $script:TunnelBannerCacheInvalidate = $false
    Write-GitModeLog "TUNNEL_BANNER_BEGIN port=$Port" 'TRACE'
    # Single TCP connection (read banner from same fd). Double /dev/tcp+nc burns 2 MaxStartups slots.
    $r = SshX "timeout 3 nc -w 2 127.0.0.1 $Port 2>/dev/null | head -1" 2>$null
    $banner = (($r -join '') -replace "`r",'').Trim()
    if ($banner -match 'MaxStartups') {
        Write-GitModeLog "TUNNEL_BANNER soft_fail port=$Port reason=maxstartups" 'WARN'
        $banner = ''
    }
    $up = (Test-TunnelBannerIsWindows -Banner $banner)
    if ($up) {
        $script:TunnelBannerCacheAt = Get-Date
        $script:TunnelBannerCacheBanner = $banner
        $script:TunnelBannerCacheUp = $true
        $script:TunnelMissCount = 0
    } else {
        $script:TunnelBannerCacheAt = $null
        $script:TunnelBannerCacheBanner = ''
        $script:TunnelBannerCacheUp = $false
        $script:TunnelMissCount = [int]$script:TunnelMissCount + 1
        Write-GitModeLog "TUNNEL_BANNER miss=$($script:TunnelMissCount) port=$Port banner=$banner" 'DEBUG'
    }
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

function Test-TunnelPortTcpOpen {
    if (-not $Port) { return $false }
    $r = SshX "timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$Port 2>/dev/null' && echo open || echo closed" 2>$null
    $out = (($r -join '') -replace "`r",'').Trim()
    return ($out -eq 'open')
}

function Clear-ServerStaleTunnelForward {
    param([int]$TargetPort = $Port)
    if (-not $TargetPort) { return }
    Write-GitModeLog "STALE_FORWARD: clearing server port=$TargetPort" 'DEBUG'
    SshX "fuser -k ${TargetPort}/tcp 2>/dev/null || true; pkill -u `$USER -f '127\\.0\\.0\\.1:${TargetPort}' 2>/dev/null || true; pkill -u `$USER -f ' -p ${TargetPort} ' 2>/dev/null || true" 2>$null | Out-Null
    Clear-TunnelBannerCache
    # Keep short: long waits were a major "still slow" cost when ports were sticky.
    for ($i = 1; $i -le 4; $i++) {
        Start-Sleep -Milliseconds 250
        Clear-TunnelBannerCache
        $savedPort = $Port
        $Port = $TargetPort
        try {
            if (-not (Test-TunnelPortTcpOpen)) {
                Write-GitModeLog "STALE_FORWARD: port released port=$TargetPort wait=$i" 'DEBUG'
                return
            }
        } finally {
            $Port = $savedPort
        }
    }
    Write-GitModeLog "STALE_FORWARD: port still busy port=$TargetPort after wait" 'WARN'
}

function Release-StaleTunnelPort {
    if (-not $Port) { return }
    Clear-TunnelBannerCache
    $banner = Get-TunnelBanner
    if ($banner -and (Test-TunnelBannerIsThisLaptop -Banner $banner)) { return }
    if ($banner -and -not (Test-TunnelBannerIsThisLaptop -Banner $banner)) {
        Write-GitModeLog "STALE_FORWARD: foreign banner port=$Port banner=$banner" 'DEBUG'
        Clear-ServerStaleTunnelForward -TargetPort $Port
        return
    }
    if (Test-TunnelPortTcpOpen) {
        Write-GitModeLog "STALE_FORWARD: zombie port=$Port tcp=open banner=(empty)" 'WARN'
        Clear-ServerStaleTunnelForward -TargetPort $Port
    }
}

function Get-TunnelProcessExitCode {
    param([System.Diagnostics.Process]$Process)
    if (-not $Process) { return 'unavailable' }
    try {
        $Process.Refresh()
        if ($Process.HasExited) { return [string]$Process.ExitCode }
    } catch { }
    return 'unavailable'
}

function Stop-TunnelProcessWithExitLog {
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string]$Reason
    )
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $proc) {
        Write-GitModeLog "TUNNEL_EXIT pid=$ProcessId port=$Port exit_code=unavailable reason=$Reason state=not_found" 'DEBUG'
        return
    }
    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        try { $null = $proc.WaitForExit(1000) } catch { }
        $exitCode = Get-TunnelProcessExitCode -Process $proc
        Write-GitModeLog "TUNNEL_EXIT pid=$ProcessId port=$Port exit_code=$exitCode reason=$Reason" 'DEBUG'
    } catch {
        Write-GitModeLog "TUNNEL_EXIT pid=$ProcessId port=$Port exit_code=unavailable reason=$Reason stop_error=$($_.Exception.Message)" 'WARN'
    }
}

function Remove-LocalOrphanTunnel {
    param(
        [Parameter(Mandatory)][int]$TargetPort,
        [System.Diagnostics.Process]$CurrentBgTunnel = $null,
        [int[]]$ProtectedProcessIds = @()
    )
    $protected = @($ProtectedProcessIds)
    if ($CurrentBgTunnel -and -not $CurrentBgTunnel.HasExited) {
        $protected += [int]$CurrentBgTunnel.Id
    }
    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) {
        $protected += [int]$script:SessionBgTunnel.Id
    }
    $killed = $false
    Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "-R\s+${TargetPort}:localhost:22" } |
        ForEach-Object {
            $processId = [int]$_.ProcessId
            if ($protected -contains $processId) {
                Write-GitModeLog "ORPHAN_TUNNEL: skip_current pid=$processId port=$TargetPort" 'DEBUG'
                return
            }
            Write-GitModeLog "ORPHAN_TUNNEL: killing local pid=$processId port=$TargetPort" 'WARN'
            Stop-TunnelProcessWithExitLog -ProcessId $processId -Reason 'orphan_cleanup'
            $killed = $true
        }
    Clear-TunnelBannerCache
    if ($killed) { Clear-ServerStaleTunnelForward -TargetPort $TargetPort }
}

function Acquire-TunnelPort {
    param(
        [string]$UidStr,
        [System.Diagnostics.Process]$CurrentBgTunnel = $null,
        [int[]]$ProtectedProcessIds = @()
    )
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
        Remove-LocalOrphanTunnel -TargetPort ($portBase + [int]$UidStr + $preferredInt) -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds
    }
    $trySlots = @()
    if ($null -ne $preferredInt -and $preferredInt -le 9) { $trySlots += $preferredInt }
    0..9 | ForEach-Object { if ($_ -ne $preferredInt) { $trySlots += $_ } }
    foreach ($slot in $trySlots) {
        $port = $portBase + [int]$UidStr + $slot
        if ($port -gt 65535) { continue }
        $script:Port = $port
        Clear-TunnelBannerCache
        $banner = Get-TunnelBanner
        if ($banner -and -not (Test-TunnelBannerIsThisLaptop -Banner $banner)) { continue }
        if (-not $banner -and (Test-TunnelPortTcpOpen)) {
            Clear-ServerStaleTunnelForward -TargetPort $port
            Clear-TunnelBannerCache
            $banner = Get-TunnelBanner
            if ($banner -and -not (Test-TunnelBannerIsThisLaptop -Banner $banner)) { continue }
            if (-not $banner -and (Test-TunnelPortTcpOpen)) { continue }
        }
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
    param([int]$Retries = 0)
    if (-not $Port) { return $false }
    if (-not $script:TunnelBannerCacheInvalidate -and $script:TunnelBannerCacheAt -and $script:TunnelBannerCacheUp) {
        $ageMs = [int]((Get-Date) - $script:TunnelBannerCacheAt).TotalMilliseconds
        if ($ageMs -lt 3000) {
            $script:TunnelSoftFailCount = 0
            Write-GitModeLog "TUNNEL_UP port=$Port up=True banner=$($script:TunnelBannerCacheBanner) cache=1" 'TRACE'
            return $true
        }
    }
    $attempts = 1 + [Math]::Max(0, $Retries)
    $banner = ''
    for ($a = 1; $a -le $attempts; $a++) {
        if ($a -gt 1) {
            Start-Sleep -Milliseconds 250
        }
        $banner = Get-TunnelBanner
        if (Test-TunnelBannerIsWindows -Banner $banner) {
            $script:TunnelSoftFailCount = 0
            Write-GitModeLog "TUNNEL_UP port=$Port up=True banner=$banner attempt=$a" 'TRACE'
            return $true
        }
    }
    Write-GitModeLog "TUNNEL_UP port=$Port up=False banner=$banner attempts=$attempts" 'TRACE'
    return $false
}

function Test-Tunnel {
    return (Test-TunnelUp)
}

function Get-TunnelSshProcess {
    # Bug 51: soft-fail path used to CIM-scan all ssh.exe ~every 800ms - cache briefly.
    if (-not $Port) { return $null }
    $ttlMs = 2000
    if ($script:TunnelSshCimCachePort -eq $Port -and $script:TunnelSshCimCacheAt) {
        $age = [int]((Get-Date) - $script:TunnelSshCimCacheAt).TotalMilliseconds
        if ($age -ge 0 -and $age -lt $ttlMs) {
            return $script:TunnelSshCimCache
        }
    }
    $portPat = [regex]::Escape("$Port")
    $hit = Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "-R\s+${portPat}:localhost:22" } |
        Select-Object -First 1
    $script:TunnelSshCimCache = $hit
    $script:TunnelSshCimCacheAt = Get-Date
    $script:TunnelSshCimCachePort = $Port
    return $hit
}

function Try-ReattachSessionTunnelProcess {
    param([ref]$BgTunnel)
    $cim = Get-TunnelSshProcess
    if (-not $cim) { return $false }
    try {
        $proc = Get-Process -Id $cim.ProcessId -ErrorAction Stop
        if (-not $proc.HasExited) {
            $BgTunnel.Value = $proc
            $script:SessionBgTunnel = $proc
            $script:TunnelSyncFailCount = 0
            $script:TunnelSoftFailCount = 0
            Write-GitModeLog "TUNNEL_SYNC ok=1 reason=reattached pid=$($proc.Id) port=$Port" 'DEBUG'
            return $true
        }
    } catch {
        Write-GitModeLog "TUNNEL_SYNC reattach_fail pid=$($cim.ProcessId) err=$($_.Exception.Message)" 'DEBUG'
    }
    return $false
}

function Sync-SessionTunnelProcess {
    param([ref]$BgTunnel)
    if ($BgTunnel.Value -and $BgTunnel.Value.HasExited -and $script:LastTunnelExitLoggedPid -ne $BgTunnel.Value.Id) {
        $exitCode = Get-TunnelProcessExitCode -Process $BgTunnel.Value
        Write-GitModeLog "TUNNEL_EXIT pid=$($BgTunnel.Value.Id) port=$Port exit_code=$exitCode reason=sync_observed_exit" 'WARN'
        $script:LastTunnelExitLoggedPid = $BgTunnel.Value.Id
    }

    # Reattach before health checks: an empty banner must not hide a live ssh -R.
    if (-not $BgTunnel.Value -or $BgTunnel.Value.HasExited) {
        $null = Try-ReattachSessionTunnelProcess -BgTunnel $BgTunnel
    }
    if (-not $BgTunnel.Value -or $BgTunnel.Value.HasExited) {
        $tcpOpen = $false
        try { $tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen = $false }
        if ($tcpOpen) {
            $script:TunnelSoftFailCount++
            Write-GitModeLog ("TUNNEL_SYNC soft_fail count=$script:TunnelSoftFailCount/6 port=$Port reason=no_proc_tcp_open$(Get-TunnelSessionDiagSuffix)") 'WARN'
            $null = Try-ReattachSessionTunnelProcess -BgTunnel $BgTunnel
            if ($script:TunnelSoftFailCount -ge 6) {
                $dropPid = 0
                if ($BgTunnel.Value) { $dropPid = $BgTunnel.Value.Id }
                elseif ($script:LastTunnelExitLoggedPid) { $dropPid = $script:LastTunnelExitLoggedPid }
                Write-TunnelDropLog -Reason 'no_proc_tcp_open_budget' -Pid $dropPid -TcpOpen $true `
                    -Banner $script:TunnelBannerCacheBanner
                Release-StaleTunnelPort
                $script:TunnelSoftFailCount = 0
                $script:TunnelSyncFailCount = 0
                return $false
            }
            $script:TunnelSyncFailCount = 0
            if (-not $BgTunnel.Value -or $BgTunnel.Value.HasExited) {
                return $true
            }
            # Reattached under budget: continue into bg-alive probe path.
        }
    }

    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        $now = Get-Date
        if (-not $script:LastForwardProbeAt) {
            $script:LastForwardProbeAt = $now
        } elseif (($now - $script:LastForwardProbeAt).TotalSeconds -ge 30) {
            $script:LastForwardProbeAt = $now
            $probeUp = $false
            for ($i = 1; $i -le 3; $i++) {
                if ($i -gt 1) { Start-Sleep -Milliseconds 300 }
                if (Test-TunnelUp) { $probeUp = $true; break }
            }
            if (-not $probeUp) {
                $tcpOpen = $false
                try { $tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen = $false }
                if ($tcpOpen) {
                    $script:TunnelSoftFailCount++
                    Write-GitModeLog ("TUNNEL_SYNC soft_fail count=$script:TunnelSoftFailCount/6 pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open$(Get-TunnelSessionDiagSuffix)") 'WARN'
                    $script:TunnelSyncFailCount = 0
                    if ($script:TunnelSoftFailCount -ge 6) {
                        Write-TunnelDropLog -Reason 'banner_miss_tcp_open_budget' -Pid $BgTunnel.Value.Id `
                            -TcpOpen $true -Banner $script:TunnelBannerCacheBanner
                        Release-StaleTunnelPort
                        $script:TunnelSoftFailCount = 0
                        return $false
                    }
                    return $true
                } else {
                    $script:TunnelSyncFailCount++
                    $probeBanner = $script:TunnelBannerCacheBanner
                    if ($script:TunnelSyncFailCount -lt 3) {
                        $script:LastForwardProbeAt = (Get-Date).AddSeconds(-30)
                        Write-GitModeLog "TUNNEL_SYNC miss=$script:TunnelSyncFailCount/3 pid=$($BgTunnel.Value.Id) port=$Port reason=bg_alive_forward_dead" 'DEBUG'
                        return $true
                    }
                    Write-TunnelDropLog -Reason 'bg_alive_forward_dead' -Pid $BgTunnel.Value.Id `
                        -TcpOpen $false -Banner $probeBanner
                    Release-StaleTunnelPort
                    $script:TunnelSoftFailCount = 0
                    return $false
                }
            } else {
                $script:TunnelSyncFailCount = 0
                $script:TunnelSoftFailCount = 0
            }
        }
        # Throttle TRACE: the session loop runs far more often than this is useful.
        $nowTs = Get-Date
        if (-not $script:LastTunnelSyncTraceAt -or ($nowTs - $script:LastTunnelSyncTraceAt).TotalSeconds -ge 30) {
            Write-GitModeLog "TUNNEL_SYNC: bg_alive pid=$($BgTunnel.Value.Id) port=$Port" 'TRACE'
            $script:LastTunnelSyncTraceAt = $nowTs
        }
        # Do not reset TunnelSoftFailCount here - only a healthy banner probe may.
        return $true
    }

    if (Test-TunnelUp -Retries 2) {
        $script:TunnelSyncFailCount = 0
        Write-GitModeLog "TUNNEL_SYNC ok=1 reason=tunnel_up_no_ssh_proc port=$Port" 'TRACE'
        return $true
    }
    $script:TunnelSyncFailCount++
    if ($script:TunnelSyncFailCount -lt 3) {
        Write-GitModeLog "TUNNEL_SYNC miss=$script:TunnelSyncFailCount/3 port=$Port reason=tunnel_down_debounce" 'DEBUG'
        return $true
    }
    Write-GitModeLog ("TUNNEL_SYNC ok=0 reason=tunnel_down port=$Port misses=$script:TunnelSyncFailCount$(Get-TunnelSessionDiagSuffix)") 'DEBUG'
    $script:LastTunnelSyncDropReason = 'tunnel_down'
    $script:TunnelSoftFailCount = 0
    return $false
}

function Wait-ForTunnelUp {
    param(
        [System.Diagnostics.Process]$TunnelProc,
        [switch]$Quiet
    )
    for ($i = 1; $i -le 12; $i++) {
        if ($TunnelProc -and $TunnelProc.HasExited) {
            $exitCode = Get-TunnelProcessExitCode -Process $TunnelProc
            Write-GitModeLog "TUNNEL_WAIT fail=1 attempt=$i reason=ssh_died pid=$($TunnelProc.Id) exit_code=$exitCode" 'WARN'
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
    Release-StaleTunnelPort
    return $false
}

function Stop-SessionTunnelCleanup {
    param(
        [ref]$BgTunnel,
        [switch]$ClearServerForward
    )
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        Write-GitModeLog "TUNNEL_STOP: killing bg pid=$($BgTunnel.Value.Id) port=$Port" 'DEBUG'
        Stop-TunnelProcessWithExitLog -ProcessId $BgTunnel.Value.Id -Reason 'session_cleanup'
    }
    if ($Port) {
        Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match "-R\s+${Port}:localhost:22" } |
            ForEach-Object {
                Write-GitModeLog "TUNNEL_STOP: killing orphan ssh pid=$($_.ProcessId) port=$Port" 'DEBUG'
                Stop-TunnelProcessWithExitLog -ProcessId $_.ProcessId -Reason 'session_orphan_cleanup'
            }
    }
    if ($ClearServerForward -and $Port) { Clear-ServerStaleTunnelForward -TargetPort $Port }
    $BgTunnel.Value = $null
    $script:SessionBgTunnel = $null
    Clear-TunnelBannerCache
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
    $scpProc = $null
    $scpBegin = $null
    $needScp = $false
    if ($MountSrc -and (Test-Path $MountSrc)) {
        $uploadSrc = Get-LfNormalizedShCopy -Src $MountSrc
        $localHash = (Get-FileHash -Algorithm SHA256 -Path $uploadSrc).Hash
        $remoteHash = ((SshX "sha256sum ~/.local/bin/claude-mount 2>/dev/null | awk '{print `$1}'") -join '').Trim()
        $needScp = -not ($localHash -and $remoteHash -and ($localHash.ToLower() -eq $remoteHash.ToLower()))
        if ($needScp) {
            Write-GitModeLog "SCP: begin project=$ProjectId alias=$Alias" 'DEBUG'
            # Bug 50: Start-Job + Stop-Job can orphan native scp - Start-Process + tree kill.
            $scpArgs = @('-o','BatchMode=yes','-o','ConnectTimeout=20','-q', $uploadSrc, "${Alias}:~/.local/bin/claude-mount")
            $scpProc = Start-Process -FilePath 'scp' -ArgumentList $scpArgs -NoNewWindow -PassThru
            $scpBegin = Get-Date
        }
    }
    Push-ServerConnectConf -ActiveMount $ProjectId
    if ($scpProc) {
        if (-not $scpProc.WaitForExit(30000)) {
            $scpMs = [int]((Get-Date) - $scpBegin).TotalMilliseconds
            Write-GitModeLog "SCP: timeout ERROR project=$ProjectId ms=$scpMs" 'ERROR'
            $scpPid = 0
            try { $scpPid = [int]$scpProc.Id } catch { }
            if ($scpPid -gt 0) {
                try {
                    Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID', "$scpPid", '/T', '/F') `
                        -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null
                } catch { }
            }
            try { if (-not $scpProc.HasExited) { $scpProc.Kill() } } catch { }
            try { $null = $scpProc.WaitForExit(3000) } catch { }
        } else {
            $scpExit = 1
            try { if ($null -ne $scpProc.ExitCode) { $scpExit = [int]$scpProc.ExitCode } } catch { }
            $scpMs = [int]((Get-Date) - $scpBegin).TotalMilliseconds
            Write-GitModeLog "SCP: end project=$ProjectId exit=$scpExit ms=$scpMs" 'DEBUG'
            if ($scpExit -eq 0) {
                SshX 'sed -i "s/\r$//" ~/.local/bin/claude-mount 2>/dev/null; chmod +x ~/.local/bin/claude-mount' 2>$null | Out-Null
            }
        }
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
    if (-not $FreshTunnel -and (Test-ProjectMountHealthy -ProjectId $ProjectId)) {
        if ((Get-GitMode) -eq 'off') {
            Write-GitModeLog "RECOVER: off_mode_apply project=$ProjectId reason=mount_ok" 'DEBUG'
            SshX "timeout 15 $CM recover-if-needed '$ProjectId' 2>/dev/null || true" 2>$null | Out-Null
        }
        return
    }
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
    if ((-not $BgTunnel.Value -or $BgTunnel.Value.HasExited) -and
        $script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) {
        $BgTunnel.Value = $script:SessionBgTunnel
    }
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        if (Test-TunnelUp) {
            $TunnelReused.Value = $true
            $script:TunnelSyncFailCount = 0
            Write-GitModeLog "ENSURE_TUNNEL reused=1 pid=$($BgTunnel.Value.Id) port=$Port reason=tunnel_up" 'DEBUG'
            return $true
        }
        $tcpOpen = $false
        try { $tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen = $false }
        if ($tcpOpen) {
            # Banner miss + TCP open: zombie forward. Do not return success / TUNNEL_REUSED.
            $script:TunnelSoftFailCount++
            Write-GitModeLog ("ENSURE_TUNNEL soft_fail count=$script:TunnelSoftFailCount/6 pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open action=reseed$(Get-TunnelSessionDiagSuffix)") 'WARN'
            if ($script:TunnelSoftFailCount -ge 6) {
                Write-TunnelDropLog -Reason 'banner_miss_tcp_open_budget' -Pid $BgTunnel.Value.Id `
                    -TcpOpen $true -Banner $script:TunnelBannerCacheBanner
                Release-StaleTunnelPort
                $script:TunnelSoftFailCount = 0
                return $false
            }
            # Fall through to kill stale bg + reseed below.
        } elseif ($script:LastTunnelSpawnSuccessAt -and $script:LastTunnelSpawnSuccessPort -eq $Port -and
            $script:LastTunnelSpawnPid -eq $BgTunnel.Value.Id -and
            ((Get-Date) - $script:LastTunnelSpawnSuccessAt).TotalSeconds -lt 5) {
            $TunnelReused.Value = $true
            Write-GitModeLog "ENSURE_TUNNEL reused=1 pid=$($BgTunnel.Value.Id) port=$Port reason=recent_success" 'DEBUG'
            return $true
        }
    }

    Write-GitModeLog "ENSURE_TUNNEL start port=$Port alias=$Alias had_bg=$([bool]$BgTunnel.Value)" 'DEBUG'
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        Write-GitModeLog "ENSURE_TUNNEL killing stale bg pid=$($BgTunnel.Value.Id)" 'DEBUG'
        Clear-TunnelBannerCache
        Stop-TunnelProcessWithExitLog -ProcessId $BgTunnel.Value.Id -Reason 'ensure_stale_bg'
        if ($Port) { Clear-ServerStaleTunnelForward -TargetPort $Port }
    }

    $protectedPids = @()
    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) {
        $protectedPids += [int]$script:SessionBgTunnel.Id
    }
    Remove-LocalOrphanTunnel -TargetPort $Port -CurrentBgTunnel $BgTunnel.Value -ProtectedProcessIds $protectedPids

    $uidStr = ((SshX 'id -u' 2>$null) -join '').Trim() -replace '\D', ''
    if ($uidStr) { $null = Acquire-TunnelPort -UidStr $uidStr -CurrentBgTunnel $BgTunnel.Value -ProtectedProcessIds $protectedPids }
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
        $script:LastTunnelSpawnSuccessAt = Get-Date
        $script:LastTunnelSpawnSuccessPort = $Port
        $script:LastTunnelSpawnPid = $BgTunnel.Value.Id
        $script:TunnelSyncFailCount = 0
        $script:TunnelSoftFailCount = 0
        $script:SessionBgTunnel = $BgTunnel.Value
        Write-GitModeLog "ENSURE_TUNNEL ok=1 pid=$($BgTunnel.Value.Id)" 'INFO'
        return $true
    }
    Write-GitModeLog "ENSURE_TUNNEL ok=0 reason=wait_timeout pid=$($BgTunnel.Value.Id)" 'WARN'
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        Clear-TunnelBannerCache
        Stop-TunnelProcessWithExitLog -ProcessId $BgTunnel.Value.Id -Reason 'ensure_wait_timeout'
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

function Warn-ForeignServerSession {
    # Return $true to continue, $false when user aborts a likely wrong-account takeover.
    # Self-heal: stale conf + no listening reverse tunnel -> clear and continue.
    # Speed (stable): one SSH reads conf (+ live port check when foreign), instead of 3-4 greps.
    $probeCmd = 'set +e; CONF="$HOME/.claude-connect.conf"; LU=""; OS=""; PORT=""; if [ -f "$CONF" ]; then LU=$(grep -E "^LAPTOP_USER=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); OS=$(grep -E "^LAPTOP_OS=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); PORT=$(grep -E "^TUNNEL_PORT=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2-); fi; printf "LU=%s\nOS=%s\nPORT=%s\n" "$LU" "$OS" "$PORT"'
    $probe = @((SshX $probeCmd) -join "`n")
    $existingLu = ''; $existingOs = ''; $existingPort = ''
    foreach ($ln in ($probe -split "`r?`n")) {
        if ($ln -match '^LU=(.*)$') { $existingLu = $Matches[1].Trim() }
        elseif ($ln -match '^OS=(.*)$') { $existingOs = $Matches[1].Trim() }
        elseif ($ln -match '^PORT=(.*)$') { $existingPort = $Matches[1].Trim() }
    }
    if (-not $existingLu) { return $true }
    $mine = if ($script:LaptopUser) { $script:LaptopUser } elseif ($env:USERNAME) { $env:USERNAME } else { $env:USER }
    if ($existingLu -eq $mine) { return $true }

    $portDigits = -join (($existingPort.ToCharArray() | Where-Object { $_ -match '[0-9]' }))
    $live = 0
    $ssOk = $false
    if ($portDigits) {
        $liveCmd = "ss -ltn 2>/dev/null | grep -cE ':{0}[[:space:]]' || echo SS_UNKNOWN" -f $portDigits
        $liveRaw = ((SshX $liveCmd) -join '').Trim()
        if ($liveRaw -match '^[0-9]+$') { $live = [int]$liveRaw; $ssOk = $true }
        else {
            Write-GitModeLog "SS:UNKNOWN port=$portDigits raw=$liveRaw - not clearing connect conf" 'WARN'
        }
    }
    # Only auto-clear when ss positively reports zero listeners (or no port in conf).
    if (-not $portDigits -or ($ssOk -and $live -eq 0)) {
        Warn ("Cleared stale session from laptop '{0}' (no active tunnel)." -f $existingLu)
        [void](Invoke-SshXChecked -RemoteCmd 'rm -f ~/.claude-connect.conf' -Label 'CLEAR_CONNECT_CONF')
        return $true
    }
    if (-not $ssOk) {
        # Ambiguous: treat as possibly live and prompt below.
        Write-GitModeLog "FOREIGN_SESSION ss_ambiguous port=$portDigits - prompting" 'WARN'
    }

    $who = if ($RemoteUser) { $RemoteUser } else { '?' }
    $osTag = if ($existingOs) { " ($existingOs)" } else { '' }
    Warn ("Server account '{0}' is already used by laptop '{1}'{2} (tunnel active)." -f $who, $existingLu, $osTag)
    Warn ("Your laptop user is '{0}'. Taking over will disconnect them." -f $mine)

    $thisOs = 'windows'
    if ($existingOs -and $existingOs -ne $thisOs) {
        Warn ("OS mismatch ({0} vs {1}) - confirm this is your server account." -f $existingOs, $thisOs)
    }
    $choice = if (Get-Command Read-ConnectPrompt -ErrorAction SilentlyContinue) {
        (Read-ConnectPrompt '    Continue and take over that session? [y/N]' -Tag 'FOREIGN_SESSION').Trim().ToLowerInvariant()
    } else { (Read-Host '    Continue and take over that session? [y/N]').Trim().ToLowerInvariant() }
    Write-GitModeLog "DECISION: foreign_session_takeover=$choice" 'WARN'

    if ($choice -ne 'y' -and $choice -ne 'yes') {
        Warn 'Aborted. Fix username with: connect.bat -Setup'
        return $false
    }
    return $true
}


function Invoke-SshXChecked {
    param(
        [Parameter(Mandatory)][string]$RemoteCmd,
        [string]$Label = 'SSHX'
    )
    $null = SshX $RemoteCmd 2>$null
    $ec = 0
    if ($null -ne $global:LASTEXITCODE) { $ec = [int]$global:LASTEXITCODE }
    if ($ec -ne 0) {
        if (Get-Command Write-GitModeLog -ErrorAction SilentlyContinue) {
            Write-GitModeLog ("{0} fail exit={1}" -f $Label, $ec) 'WARN'
        } elseif (Get-Command Write-ConnectLog -ErrorAction SilentlyContinue) {
            Write-ConnectLog ("{0} fail exit={1}" -f $Label, $ec) 'WARN'
        } else {
            Write-Host ("  [!] {0} fail exit={1}" -f $Label, $ec) -ForegroundColor DarkYellow
        }
    }
    return $ec
}

function Push-ServerConnectConf {
    param(
        [string]$GitMode = (Get-GitMode),
        [string]$ActiveMount = '',
        [switch]$ClearActiveMount
    )
    $mode = $GitMode
    # Preserve existing server ACTIVE_MOUNT unless caller clears or sets explicitly.
    # Keep self-heal out of this frequently called configuration push hot path.
    $preferAm = ''
    if (-not $ClearActiveMount) {
        if (-not [string]::IsNullOrWhiteSpace($ActiveMount)) {
            $preferAm = [string]$ActiveMount
        } elseif ($script:ActiveProjectId) {
            $preferAm = [string]$script:ActiveProjectId
        }
    }
    $clearFlag = if ($ClearActiveMount) { '1' } else { '0' }
    # Dedupe identical pushes within a few seconds (startup called this twice).
    $dedupeKey = "{0}|{1}|{2}|{3}|{4}" -f $LaptopUser, $Port, $mode, $preferAm, $clearFlag
    if ($script:LastPushConfKey -eq $dedupeKey -and $script:LastPushConfAt -and
        ((Get-Date) - $script:LastPushConfAt).TotalSeconds -le 8) {
        Write-GitModeLog "PUSH_CONF skip_duplicate key=$dedupeKey" 'INFO'
        return
    }
    # Escape for embedding inside a single-quoted bash assignment (avoid double quotes).
    $lu = ($LaptopUser -replace "'", "'\''")
    $modeEsc = ($mode -replace "'", "'\''")
    $preferEsc = ($preferAm -replace "'", "'\''")
    $portEsc = ("$Port" -replace "'", "'\''")
    Write-GitModeLog "PUSH_CONF begin laptop_user=$LaptopUser port=$Port git_mode=$mode prefer_mount=$preferAm clear=$ClearActiveMount" 'INFO'
    # Windows OpenSSH eats nested double quotes in remote payloads (AM="" -> AM="; elif syntax error).
    # Ship remote body as base64 so ACTIVE_MOUNT always lands correctly and stays trackable.
    $remoteBody = @"
set +e
CLEAR='$clearFlag'
PREFER='$preferEsc'
LU='$lu'
PORT='$portEsc'
MODE='$modeEsc'
if [ "`$CLEAR" = "1" ]; then
  AM=
elif [ -n "`$PREFER" ]; then
  AM=`$PREFER
else
  AM=`$(grep -E '^ACTIVE_MOUNT=' "`$HOME/.claude-connect.conf" 2>/dev/null | tail -1 | cut -d= -f2-)
fi
mkdir -p "`$HOME/.local/bin"
printf 'LAPTOP_USER=%s\nTUNNEL_PORT=%s\nGIT_MODE=%s\nLAPTOP_OS=windows\nACTIVE_MOUNT=%s\n' "`$LU" "`$PORT" "`$MODE" "`$AM" > "`$HOME/.claude-connect.conf"
chmod 600 "`$HOME/.claude-connect.conf" 2>/dev/null || true
printf 'PUSH_CONF_RESULT clear=%s prefer=%s active=%s\n' "`$CLEAR" "`$PREFER" "`$AM"
"@
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteBody))
    $remote = "echo $b64 | base64 -d | bash"
    $pushOut = @(SshX $remote 2>$null)
    $pushExit = $global:LASTEXITCODE
    $pushLine = (($pushOut | Where-Object { $_ -match 'PUSH_CONF_RESULT' } | Select-Object -Last 1) -replace '\s+', ' ').Trim()
    $hasResult = [bool]($pushLine -and $pushLine -match 'PUSH_CONF_RESULT')
    if (-not $pushLine) { $pushLine = '(no result line)' }
    # Exit 0 without PUSH_CONF_RESULT must NOT dedupe as success (silent false-ok).
    if ($pushExit -ne 0 -or -not $hasResult) {
        # Do not record dedupe on failure - allow immediate retry of the same prefer/clear key.
        Write-GitModeLog "PUSH_CONF fail exit=$pushExit out=$pushLine" 'ERROR'
    } else {
        $script:LastPushConfKey = $dedupeKey
        $script:LastPushConfAt = Get-Date
        Write-GitModeLog "PUSH_CONF ok exit=$pushExit $pushLine" 'INFO'
    }
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
            $kc2 = $ki2.KeyChar.ToString()
            $code2 = if ($kc2.Length -eq 1) { [int][char]$kc2[0] } else { 0 }
            $ascii2 = ($code2 -ge 32 -and $code2 -le 126)
            $letter2 = if ($ascii2) { $kc2.ToLowerInvariant() } else { '' }
            # VK fallback ONLY for null/control KeyChar - never Persian printable non-ASCII.
            $useVk2 = ($code2 -eq 0 -or ($code2 -gt 0 -and $code2 -lt 32))
            if ($letter2 -eq 'r' -or ($useVk2 -and $ki2.Key -eq [ConsoleKey]::R)) { $rk = 'r' }
            elseif ($letter2 -eq 'q' -or ($useVk2 -and $ki2.Key -eq [ConsoleKey]::Q)) { $rk = 'q' }
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
    [void](Invoke-SshXChecked -RemoteCmd "$CM down-others '$KeepProjectId'" -Label 'MOUNT_DOWN_OTHERS')
}

function Clear-SessionMount {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [string]$EditorCmd = '',
        [string]$Alias = '',
        [string]$RemotePath = '',
        [switch]$SkipEditorStop,
        [string]$Reason = ''
    )
    $reasonPart = if ($Reason) { " reason=$Reason" } else { '' }
    Write-GitModeLog "CLEAR_MOUNT project=$ProjectId skip_editor=$SkipEditorStop editor=$EditorCmd path=$RemotePath$reasonPart" 'INFO'
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
        Write-GitModeLog "CLEAR_MOUNT: down begin project=$ProjectId" 'INFO'
        [void](Invoke-SshXChecked -RemoteCmd "timeout 8 $CM down '$pidEsc' 2>/dev/null" -Label 'MOUNT_DOWN')
        $downMs = [int]((Get-Date) - $downBegin).TotalMilliseconds
        Write-GitModeLog "CLEAR_MOUNT: down end ms=$downMs project=$ProjectId" 'INFO'
    }
    if ($Port) { Push-ServerConnectConf -ClearActiveMount }
}

function Resolve-ServerScriptDir {
    param([Parameter(Mandatory)][string]$ConnectScriptDir)
    # Prefer package mac/ (published fresh claude-mount) over nested windows/server stale copies.
    foreach ($rel in @('..\mac', 'mac', '..\..\mac')) {
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
            $parent = Split-Path $d -Parent
            if (-not $parent -or $parent -eq $d) { break }
            $d = $parent
        }
    } catch { }
    foreach ($rel in @('server', '..\server', '..\..\server')) {
        try {
            $d = [System.IO.Path]::GetFullPath((Join-Path $ConnectScriptDir $rel))
            if (Test-Path ([System.IO.Path]::Combine($d, 'claude-mount.sh'))) { return $d }
        } catch { }
    }
    return $null
}


function Push-RemoteUserFileIfChanged {
    param(
        [Parameter(Mandatory)][string]$LocalSrc,
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$Alias,
        [switch]$Executable
    )
    if (-not (Test-Path $LocalSrc)) { return }
    $localHash = (Get-FileHash -Algorithm SHA256 -Path $LocalSrc).Hash
    # Quoted '~' does not expand on remote - use $HOME for ssh cmds; keep ~/ for scp.
    $rpath = $RemotePath
    if ($RemotePath.StartsWith('~/')) { $rpath = '$HOME/' + $RemotePath.Substring(2) }
    elseif ($RemotePath -eq '~') { $rpath = '$HOME' }
    $remoteHash = ((SshX "sha256sum $rpath 2>/dev/null | awk '{print `$1}'") -join '').Trim()
    if ($localHash -and $remoteHash -and ($localHash.ToLower() -eq $remoteHash.ToLower())) { return }
    [void](Invoke-SshXChecked -RemoteCmd ('mkdir -p "$(dirname ' + $rpath + ')"') -Label 'PUSH_MKDIR')
    scp -o BatchMode=yes -o ConnectTimeout=20 -q $LocalSrc "${Alias}:$RemotePath" 2>$null
    if ($Executable -and $LASTEXITCODE -eq 0) {
        [void](Invoke-SshXChecked -RemoteCmd ("chmod +x $rpath") -Label 'PUSH_CHMOD')
    }
}

function Push-LaptopExecBundleIfChanged {
    param(
        [Parameter(Mandatory)][string]$ServerDir,
        [Parameter(Mandatory)][string]$Alias
    )
    $pairs = @(
        @{ Local = 'laptop-exec.sh'; Remote = '~/.local/bin/laptop-exec'; Exec = $true },
        @{ Local = 'laptop-exec-setup.sh'; Remote = '~/.local/bin/laptop-exec-setup'; Exec = $true },
        @{ Local = 'claude-self-heal.sh'; Remote = '~/.local/bin/claude-self-heal'; Exec = $true },
        @{ Local = 'claude-automount.sh'; Remote = '~/.local/bin/claude-automount'; Exec = $true },
        @{ Local = 'cursor-rules/laptop-exec.mdc'; Remote = '~/.cursor/rules/laptop-exec.mdc'; Exec = $false },
        @{ Local = 'skills/laptop-exec/SKILL.md'; Remote = '~/.cursor/skills/laptop-exec/SKILL.md'; Exec = $false },
        @{ Local = 'cursor-hooks/laptop-exec-guard.sh'; Remote = '~/.cursor/hooks/laptop-exec-guard.sh'; Exec = $true },
        @{ Local = 'cursor-hooks/laptop-exec-guard-wrap.sh'; Remote = '~/.cursor/hooks/laptop-exec-guard-wrap.sh'; Exec = $true },
        @{ Local = 'cursor-hooks/laptop-exec-shell-scan.py'; Remote = '~/.cursor/hooks/laptop-exec-shell-scan.py'; Exec = $true },
        @{ Local = 'cursor-hooks/laptop-exec-session.sh'; Remote = '~/.cursor/hooks/laptop-exec-session.sh'; Exec = $true }
    )
    foreach ($p in $pairs) {
        $src = [System.IO.Path]::Combine($ServerDir, $p.Local)
        Push-RemoteUserFileIfChanged -LocalSrc $src -RemotePath $p.Remote -Alias $Alias -Executable:$p.Exec
    }
    # Windows scp can leave CRLF - strip on server for Win+Mac users alike
    SshX "sed -i 's/\r$//' ~/.local/bin/laptop-exec ~/.local/bin/laptop-exec-setup ~/.local/bin/claude-self-heal ~/.local/bin/claude-automount ~/.local/bin/claude-mount 2>/dev/null; chmod +x ~/.local/bin/laptop-exec ~/.local/bin/laptop-exec-setup ~/.local/bin/claude-self-heal ~/.local/bin/claude-automount 2>/dev/null; true" 2>$null | Out-Null
    if (Test-Path ([System.IO.Path]::Combine($ServerDir, 'laptop-exec-setup.sh'))) {
        SshX '$HOME/.local/bin/laptop-exec-setup --user 2>/dev/null; /usr/local/bin/laptop-exec-setup --user 2>/dev/null; true' 2>$null | Out-Null
    }
    # Self-heal for both Windows and Mac laptop sessions (runs on Linux server)
    SshX '$HOME/.local/bin/claude-self-heal --quiet 2>/dev/null; /usr/local/bin/claude-self-heal --quiet 2>/dev/null; true' 2>$null | Out-Null
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
    if ($chmodCmd.Count -gt 0) { [void](Invoke-SshXChecked -RemoteCmd ($chmodCmd -join '; ') -Label 'PUSH_CHMOD_MOUNT') }
    Push-LaptopExecBundleIfChanged -ServerDir $dir -Alias $Alias
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
    if ((Get-GitMode) -ne 'off' -and (Test-ProjectMountHealthy -ProjectId $ProjectId)) {
        Write-GitModeLog "MOUNT_UP skip project=$ProjectId reason=check_ok" 'DEBUG'
        if (Get-Command Write-ConnectPerfLog -ErrorAction SilentlyContinue) {
            Write-ConnectPerfLog -Mark 'mount_total' -Ms 0 -Extra 'path=skip_check_ok'
        }
        return @{ Ok = $true; Out = 'already mounted (check ok)' }
    }
    if ((Get-GitMode) -eq 'off' -and (Test-ProjectMountHealthy -ProjectId $ProjectId)) {
        Write-GitModeLog "MOUNT_UP off_mode_apply project=$ProjectId reason=check_ok_still_up" 'DEBUG'
    }
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
    [void](Invoke-SshXChecked -RemoteCmd "$CM down '$ProjectId'" -Label 'MOUNT_DOWN')
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
    $curDesc = switch ($cur) {
        'server' { 'full git over SSHFS' }
        'hide'   { '.git hidden on laptop' }
        default  { 'no .git rename (use laptop-exec git)' }
    }
    Write-Host "    Current: $curLabel ($curDesc)" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '    1  OFF  - no .git rename [default]' -ForegroundColor DarkGray
    Write-Host '    2  HIDE - hide .git on laptop (faster SSHFS)' -ForegroundColor DarkGray
    Write-Host '    3  SLOW - full .git visible on SSHFS mount' -ForegroundColor DarkGray
    Write-Host ''
    $choice = if (Get-Command Read-ConnectPrompt -ErrorAction SilentlyContinue) {
        (Read-ConnectPrompt '    >' -Tag 'GIT_MODE').Trim().ToLower()
    } else { (Read-Host '    >').Trim().ToLower() }
    Write-GitModeLog "INTERACTIVE: git_mode_choice=$choice" 'INFO'
    switch ($choice) {
        { $_ -in '1', 'off', '' } {
            Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'git.conf')) -Value 'off' -Encoding ASCII | Out-Null
            Write-GitModeLog 'DECISION: git_mode=off' 'INFO'
        }
        { $_ -in '2', 'hide', 'fast' } {
            Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'git.conf')) -Value 'hide' -Encoding ASCII | Out-Null
            Write-GitModeLog 'DECISION: git_mode=hide' 'INFO'
        }
        { $_ -in '3', 'on', 'server', 'slow' } {
            Set-Content -Path ([System.IO.Path]::Combine($CfgDir, 'git.conf')) -Value 'server' -Encoding ASCII | Out-Null
            Write-GitModeLog 'DECISION: git_mode=server' 'INFO'
        }
        default { Write-GitModeLog "DECISION: git_mode_invalid=$choice" 'WARN'; Warn 'Invalid choice.'; return }
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
