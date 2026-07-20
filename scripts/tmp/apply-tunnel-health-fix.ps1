$ErrorActionPreference = 'Stop'
$root = (Resolve-Path '.').Path

function Replace-Exact {
    param([string]$Path, [string]$Old, [string]$New, [string]$Label)
    $raw = [IO.File]::ReadAllText($Path)
    $nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $c = $raw -replace "`r`n", "`n" -replace "`r", "`n"
    $oldN = $Old -replace "`r`n", "`n" -replace "`r", "`n"
    $newN = $New -replace "`r`n", "`n" -replace "`r", "`n"
    if ($c.IndexOf($oldN) -lt 0) { throw "pattern missing: $Label in $Path" }
    $n = 0; $i = 0
    while (($i = $c.IndexOf($oldN, $i)) -ge 0) { $n++; $i += $oldN.Length }
    if ($n -ne 1) { throw "expected 1 occurrence of $Label, found $n" }
    $c2 = $c.Replace($oldN, $newN)
    if ($nl -eq "`r`n") { $c2 = $c2 -replace "`n", "`r`n" }
    [IO.File]::WriteAllText($Path, $c2)
    Write-Host "OK $Label"
}

$gm = Join-Path $root 'scripts\client\git-mode.ps1'

Replace-Exact -Path $gm -Label 'cache-vars' -Old @'
$script:TunnelBannerCacheAt = $null
$script:TunnelBannerCacheBanner = ''
$script:TunnelBannerCacheUp = $false
$script:TunnelBannerCacheInvalidate = $false
$script:LastForwardProbeAt = $null
'@ -New @'
$script:TunnelBannerCacheAt = $null
$script:TunnelBannerCacheBanner = ''
$script:TunnelBannerCacheUp = $false
$script:TunnelBannerCacheInvalidate = $false
$script:LastForwardProbeAt = $null
$script:TunnelMissCount = 0
'@

Replace-Exact -Path $gm -Label 'Get-TunnelBanner' -Old @'
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
'@ -New @'
function Get-TunnelBanner {
    if (-not $Port) { return '' }
    # Positive cache only — never cache empty/false for 3s (poisoned DROP1 recovery).
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
    $r = SshX "timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$Port 2>/dev/null || exit 1; IFS= read -r -t 2 line <&3 || true; printf %s \"\$line\"' 2>/dev/null" 2>$null
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
'@

Replace-Exact -Path $gm -Label 'Test-TunnelUp' -Old @'
function Test-TunnelUp {
    if (-not $Port) { return $false }
    if (-not $script:TunnelBannerCacheInvalidate -and $script:TunnelBannerCacheAt) {
        $ageMs = [int]((Get-Date) - $script:TunnelBannerCacheAt).TotalMilliseconds
        if ($ageMs -lt 3000) {
            $up = (Test-TunnelBannerIsWindows -Banner $script:TunnelBannerCacheBanner)
            $script:TunnelBannerCacheUp = $up
            Write-GitModeLog "TUNNEL_UP port=$Port up=$up banner=$($script:TunnelBannerCacheBanner) cache=1" 'TRACE'
            return $up
        }
    }
    $banner = Get-TunnelBanner
    $up = (Test-TunnelBannerIsWindows -Banner $banner)
    $script:TunnelBannerCacheUp = $up
    Write-GitModeLog "TUNNEL_UP port=$Port up=$up banner=$banner" 'TRACE'
    return $up
}
'@ -New @'
function Test-TunnelUp {
    param([int]$Retries = 0)
    if (-not $Port) { return $false }
    if (-not $script:TunnelBannerCacheInvalidate -and $script:TunnelBannerCacheAt -and $script:TunnelBannerCacheUp) {
        $ageMs = [int]((Get-Date) - $script:TunnelBannerCacheAt).TotalMilliseconds
        if ($ageMs -lt 3000) {
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
            Write-GitModeLog "TUNNEL_UP port=$Port up=True banner=$banner attempt=$a" 'TRACE'
            return $true
        }
    }
    Write-GitModeLog "TUNNEL_UP port=$Port up=False banner=$banner attempts=$attempts" 'TRACE'
    return $false
}
'@

Replace-Exact -Path $gm -Label 'Sync-SessionTunnelProcess' -Old @'
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
                Release-StaleTunnelPort
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
'@ -New @'
function Sync-SessionTunnelProcess {
    param([ref]$BgTunnel)
    # Reattach BEFORE banner check — empty banner must not block finding a live ssh -R.
    if (-not $BgTunnel.Value -or $BgTunnel.Value.HasExited) {
        $cim = Get-TunnelSshProcess
        if ($cim) {
            try {
                $proc = Get-Process -Id $cim.ProcessId -ErrorAction Stop
                if (-not $proc.HasExited) {
                    $BgTunnel.Value = $proc
                    $script:SessionBgTunnel = $proc
                    Write-GitModeLog "TUNNEL_SYNC ok=1 reason=reattached pid=$($proc.Id) port=$Port" 'DEBUG'
                }
            } catch {
                Write-GitModeLog "TUNNEL_SYNC reattach_fail pid=$($cim.ProcessId) err=$($_.Exception.Message)" 'DEBUG'
            }
        }
    }
    if ($BgTunnel.Value -and -not $BgTunnel.Value.HasExited) {
        $now = Get-Date
        if (-not $script:LastForwardProbeAt) {
            $script:LastForwardProbeAt = $now
        } elseif (((Get-Date) - $script:LastForwardProbeAt).TotalSeconds -ge 30) {
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
                    Write-GitModeLog "TUNNEL_SYNC soft_fail pid=$($BgTunnel.Value.Id) port=$Port reason=banner_miss_tcp_open" 'WARN'
                } else {
                    $probeBanner = $script:TunnelBannerCacheBanner
                    Write-GitModeLog "TUNNEL_DROP pid=$($BgTunnel.Value.Id) port=$Port banner=$probeBanner reason=bg_alive_forward_dead" 'WARN'
                    Release-StaleTunnelPort
                    return $false
                }
            }
        }
        Write-GitModeLog "TUNNEL_SYNC: bg_alive pid=$($BgTunnel.Value.Id) port=$Port" 'TRACE'
        return $true
    }
    if (Test-TunnelUp -Retries 2) {
        Write-GitModeLog "TUNNEL_SYNC ok=1 reason=tunnel_up_no_ssh_proc port=$Port" 'TRACE'
        return $true
    }
    Write-GitModeLog "TUNNEL_SYNC ok=0 reason=tunnel_down port=$Port" 'DEBUG'
    return $false
}
'@

Write-Host 'git-mode.ps1 done'

$cp = Join-Path $root 'scripts\client\windows\connect.ps1'
Replace-Exact -Path $cp -Label 'session-loop-sync' -Old @'
            while ($true) {
                $null = Sync-SessionTunnelProcess -BgTunnel ([ref]$bgTunnel)
                if (-not (Test-TunnelUp)) { break }
                if ($EditorCmd -eq 'cursor') {
                    $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $editorOpened = $onFolderNow
                    $editorLabel = if ($onFolderNow) { $EditorName } elseif ($windowOpen) { 'agent' } else { 'closed' }
                } else {
                    $onFolderNow = $editorOpened
                    $editorLabel = ''
                }
                if ((Get-Date) - $lastStatusAt -gt [TimeSpan]::FromSeconds(30)) {
                    Update-SessionStatusLine -ProjectLabel $go.Id -GitLabel (Get-GitModeLabel) -TunnelOk (Test-TunnelUp) `
                        -EditorOpen $onFolderNow -EditorName $EditorName -EditorLabel $editorLabel `
                        -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $lastStatusAt = Get-Date
                }
                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    if ($ki.KeyChar.ToString().ToLower() -eq 'r' -or $ki.Key -eq [ConsoleKey]::R) { $action = 'r' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'g' -or $ki.Key -eq [ConsoleKey]::G) { $action = 'g' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'o' -or $ki.Key -eq [ConsoleKey]::O) { $action = 'o' }
                    elseif ($ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }

                    $gotKey = $true
                    break
                }
                Start-Sleep -Milliseconds 200
            }
            if (-not $gotKey -and -not (Test-TunnelUp)) {
'@ -New @'
            $tunnelSyncOk = $true
            while ($true) {
                # Sync is authoritative (reattach + 30s probe with retries). Do NOT call
                # Test-TunnelUp every 200ms — that defeated the probe throttle (false DROP2/3).
                $tunnelSyncOk = [bool](Sync-SessionTunnelProcess -BgTunnel ([ref]$bgTunnel))
                if (-not $tunnelSyncOk) { break }
                if ($EditorCmd -eq 'cursor') {
                    $onFolderNow = Test-RemoteEditorOnCorrectFolder -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $windowOpen = Test-RemoteEditorWindowOpen -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $editorOpened = $onFolderNow
                    $editorLabel = if ($onFolderNow) { $EditorName } elseif ($windowOpen) { 'agent' } else { 'closed' }
                } else {
                    $onFolderNow = $editorOpened
                    $editorLabel = ''
                }
                if ((Get-Date) - $lastStatusAt -gt [TimeSpan]::FromSeconds(30)) {
                    Update-SessionStatusLine -ProjectLabel $go.Id -GitLabel (Get-GitModeLabel) -TunnelOk $tunnelSyncOk `
                        -EditorOpen $onFolderNow -EditorName $EditorName -EditorLabel $editorLabel `
                        -EditorCmd $EditorCmd -Alias $Alias -RemotePath $go.Path
                    $lastStatusAt = Get-Date
                }
                if ([Console]::KeyAvailable) {
                    $ki = [Console]::ReadKey($true)
                    if ($ki.KeyChar.ToString().ToLower() -eq 'r' -or $ki.Key -eq [ConsoleKey]::R) { $action = 'r' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'g' -or $ki.Key -eq [ConsoleKey]::G) { $action = 'g' }
                    elseif ($ki.KeyChar.ToString().ToLower() -eq 'o' -or $ki.Key -eq [ConsoleKey]::O) { $action = 'o' }
                    elseif ($ki.Key -eq [ConsoleKey]::Enter) { $action = 'q' }

                    $gotKey = $true
                    break
                }
                Start-Sleep -Milliseconds 200
            }
            if (-not $gotKey -and -not $tunnelSyncOk) {
'@

$diag = Join-Path $root 'scripts\client\connect-diagnostic.ps1'
Replace-Exact -Path $diag -Label 'verdict-tunnel-down' -Old @'
    if (-not $Ctx.TunnelUp) {
        return @{
            Code = 'TUNNEL_DOWN'; Severity = 'ERROR'
            Summary = "Reverse SSH tunnel not up on port $($Ctx.Port)."
            Cause = 'Laptop OpenSSH stopped, firewall, or tunnel died.'
            Fix = 'Press R. Ensure sshd running and firewall allows inbound TCP 22.'
            NextAction = 'R'
        }
    }
'@ -New @'
    # Banner probe can false-negative (MaxStartups / empty). If other signals say the
    # reverse forward works, do not emit TUNNEL_DOWN (DROP1: ssh -p worked + mount OK).
    $tunnelEffectivelyUp = [bool]$Ctx.TunnelUp
    if (-not $tunnelEffectivelyUp) {
        if ($Ctx.LocalPortOpen -eq $true) { $tunnelEffectivelyUp = $true }
        if ($Ctx.BgAlive -eq $true) { $tunnelEffectivelyUp = $true }
        if ($Ctx.MountOk -eq $true -and $Ctx.OnFolder -eq $true) { $tunnelEffectivelyUp = $true }
    }
    if (-not $tunnelEffectivelyUp) {
        return @{
            Code = 'TUNNEL_DOWN'; Severity = 'ERROR'
            Summary = "Reverse SSH tunnel not up on port $($Ctx.Port)."
            Cause = 'Laptop OpenSSH stopped, firewall, or tunnel died.'
            Fix = 'Press R. Ensure sshd running and firewall allows inbound TCP 22.'
            NextAction = 'R'
        }
    }
'@

Replace-Exact -Path $diag -Label 'diag-ctx-tunnel' -Old @'
    $verdict = Get-ConnectProblemVerdict -Ctx @{
        EditorCmd = $EditorCmd; Port = $Port; ServerIP = $ServerIP
        TunnelUp = $TunnelUp; MountOk = $MountOk; MountOut = $MountOut
        OnFolder = $OnFolder; AgentHome = $AgentHome; WindowOpen = $WindowOpen
        DidLaunch = $DidLaunch; AuthOk = $AuthOk; CursorExeFound = $cursorFound
        ServerReachable = $serverReachable; RemotePath = $RemotePath
        MountPoint = $mountPoint; PathExists = $pathExists
        LaunchHistory = $LaunchHistory
    }
'@ -New @'
    $bgAlive = $false
    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) { $bgAlive = $true }
    if (-not $bgAlive -and (Get-Command Get-TunnelSshProcess -ErrorAction SilentlyContinue)) {
        try { if (Get-TunnelSshProcess) { $bgAlive = $true } } catch { }
    }
    # One fresh probe before verdict (positive-cache-only Get-TunnelBanner).
    $tunnelUpNow = $TunnelUp
    if (-not $tunnelUpNow -and (Get-Command Test-TunnelUp -ErrorAction SilentlyContinue)) {
        try { $tunnelUpNow = [bool](Test-TunnelUp -Retries 1) } catch { }
    }
    $verdict = Get-ConnectProblemVerdict -Ctx @{
        EditorCmd = $EditorCmd; Port = $Port; ServerIP = $ServerIP
        TunnelUp = $tunnelUpNow; MountOk = $MountOk; MountOut = $MountOut
        OnFolder = $OnFolder; AgentHome = $AgentHome; WindowOpen = $WindowOpen
        DidLaunch = $DidLaunch; AuthOk = $AuthOk; CursorExeFound = $cursorFound
        ServerReachable = $serverReachable; RemotePath = $RemotePath
        MountPoint = $mountPoint; PathExists = $pathExists
        LaunchHistory = $LaunchHistory
        LocalPortOpen = $localPortOpen; BgAlive = $bgAlive
    }
'@

Replace-Exact -Path $diag -Label 'diag-tunnel-line' -Old @'
    $lines += "TUNNEL up=$TunnelUp local_port_open=$localPortOpen server_reachable=$serverReachable banner=$(if (Get-Command Get-TunnelBanner -ErrorAction SilentlyContinue) { Get-TunnelBanner } else { '?' })"
'@ -New @'
    $lines += "TUNNEL up=$tunnelUpNow local_port_open=$localPortOpen server_reachable=$serverReachable bg_alive=$bgAlive banner=$(if (Get-Command Get-TunnelBanner -ErrorAction SilentlyContinue) { Get-TunnelBanner } else { '?' })"
'@

Write-Host 'ALL_PS_OK'
