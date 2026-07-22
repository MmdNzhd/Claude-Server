$ErrorActionPreference = 'Stop'
$root = 'D:\Smart\Claude-Code-Server'
$gm = Join-Path $root 'scripts\client\git-mode.ps1'
$g = [IO.File]::ReadAllText($gm)
$nl = if ($g.Contains("`r`n")) { "`r`n" } else { "`n" }

# Fix missing newline before Get-TunnelHostKeyFingerprint
$g = $g.Replace('}function Get-TunnelHostKeyFingerprint', '}' + $nl + $nl + 'function Get-TunnelHostKeyFingerprint')

# Replace entire Acquire-TunnelPort function
$acqStart = $g.IndexOf('function Acquire-TunnelPort {')
$acqEnd = $g.IndexOf('function Test-TunnelUp {')
if ($acqStart -lt 0 -or $acqEnd -lt 0) { throw "acq bounds $acqStart $acqEnd" }

$newAcq = @'
function Get-LocalTunnelPortPidMap {
    # One CIM scan for all ssh -R forwards (avoids ~500ms Get-CimInstance per port).
    $map = @{}
    Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match '-R\s+(\d+):localhost:22' } |
        ForEach-Object {
            if ($_.CommandLine -match '-R\s+(\d+):localhost:22') {
                $p = [int]$Matches[1]
                if (-not $map.ContainsKey($p)) { $map[$p] = New-Object System.Collections.Generic.List[int] }
                $map[$p].Add([int]$_.ProcessId)
            }
        }
    return $map
}

function Get-ServerOpenTunnelPorts {
    param([Parameter(Mandatory)][int[]]$Ports)
    $set = New-Object "System.Collections.Generic.HashSet[int]"
    if (-not $Ports -or $Ports.Count -eq 0) { return $set }
    $list = ($Ports | Select-Object -Unique) -join ' '
    # Single SSH: probe all candidates. Closed ports are free to claim.
    $script = @"
for p in $list; do
  if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/`$p" 2>/dev/null; then echo OPEN:`$p; fi
done
"@
    $out = (SshX $script 2>$null) -join "`n"
    foreach ($line in @($out -split "`n")) {
        if ($line -match 'OPEN:(\d+)') { [void]$set.Add([int]$Matches[1]) }
    }
    Write-GitModeLog ("ACQUIRE_BATCH open_ports={0} probed={1}" -f (($set | Sort-Object) -join ','), $Ports.Count) 'DEBUG'
    return $set
}

function Acquire-TunnelPort {
    param(
        [string]$UidStr,
        [System.Diagnostics.Process]$CurrentBgTunnel = $null,
        [int[]]$ProtectedProcessIds = @()
    )
    $portBase = 20000
    if (-not $UidStr) { return $false }

    # Already bound to a live session tunnel — do not rescan.
    if ($Port -and $script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) {
        $mine = @($ProtectedProcessIds)
        $mine += [int]$script:SessionBgTunnel.Id
        if ($CurrentBgTunnel -and -not $CurrentBgTunnel.HasExited) { $mine += [int]$CurrentBgTunnel.Id }
        $localNow = @(Get-LocalTunnelSshPids -TargetPort $Port)
        foreach ($pid in $localNow) {
            if ($mine -contains [int]$pid) {
                Write-GitModeLog "ACQUIRE_KEEP: session_tunnel port=$Port pid=$pid" 'DEBUG'
                return $true
            }
        }
    }

    $preferred = ''
    if ($env:CLAUDE_CONNECT_UI_SLOT -match '^\d+$') { $preferred = $env:CLAUDE_CONNECT_UI_SLOT }
    if (-not $preferred -and $Cfg -and (Test-Path $Cfg)) {
        $slotLine = Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -match '^TUNNEL_SLOT=' } | Select-Object -Last 1
        if ($slotLine -match 'TUNNEL_SLOT=(\d+)') { $preferred = $matches[1] }
    }
    # Also honor sticky PORT from conf when present.
    $preferredPort = $null
    if ($Cfg -and (Test-Path $Cfg)) {
        $portLine = Get-Content $Cfg -ErrorAction SilentlyContinue | Where-Object { $_ -match '^(PORT|TUNNEL_PORT)=' } | Select-Object -Last 1
        if ($portLine -match '=(2\d{4})$') { $preferredPort = [int]$Matches[1] }
    }

    $preferredInt = $null
    if ($preferred -match '^\d+$') { $preferredInt = [int]$preferred }
    $trySlots = @()
    if ($null -ne $preferredInt -and $preferredInt -le 9) { $trySlots += $preferredInt }
    0..9 | ForEach-Object { if ($_ -ne $preferredInt) { $trySlots += $_ } }

    $candidates = @()
    foreach ($slot in $trySlots) {
        $port = $portBase + [int]$UidStr + $slot
        if ($port -le 65535) { $candidates += @{ Slot = $slot; Port = $port } }
    }
    if ($preferredPort) {
        $candidates = @($candidates | Sort-Object { if ($_.Port -eq $preferredPort) { 0 } else { 1 } }, { $_.Slot })
    }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $localMap = Get-LocalTunnelPortPidMap
    $protected = @($ProtectedProcessIds)
    if ($CurrentBgTunnel -and -not $CurrentBgTunnel.HasExited) { $protected += [int]$CurrentBgTunnel.Id }
    if ($script:SessionBgTunnel -and -not $script:SessionBgTunnel.HasExited) { $protected += [int]$script:SessionBgTunnel.Id }

    $probePorts = @()
    foreach ($c in $candidates) {
        $port = [int]$c.Port
        if (Get-Command Test-CachedForeignTunnelPort -ErrorAction SilentlyContinue) {
            if (Test-CachedForeignTunnelPort -TargetPort $port) { continue }
        }
        $peerLive = $false
        if ($localMap.ContainsKey($port)) {
            foreach ($processId in @($localMap[$port])) {
                if ($protected -contains [int]$processId) { continue }
                $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
                if ($proc -and -not $proc.HasExited) { $peerLive = $true; break }
            }
        }
        if ($peerLive) {
            Write-GitModeLog "ACQUIRE_SKIP: peer_live port=$port slot=$($c.Slot)" 'DEBUG'
            continue
        }
        $probePorts += $port
    }

    $openSet = Get-ServerOpenTunnelPorts -Ports $probePorts
    Write-GitModeLog ("ACQUIRE_FAST prep_ms={0} candidates={1} probe={2} open={3}" -f $sw.ElapsedMilliseconds, $candidates.Count, $probePorts.Count, $openSet.Count) 'INFO'

    # Pass 1: claim first CLOSED port (truly free) — no banner/hostkey/foreign SSH.
    foreach ($c in $candidates) {
        $port = [int]$c.Port
        $slot = [int]$c.Slot
        if ($probePorts -notcontains $port) { continue }
        if ($openSet.Contains($port)) { continue }
        $script:TunnelSlot = $slot
        $script:Port = $port
        Save-TunnelSlot
        Push-ServerConnectConf
        Write-GitModeLog ("ACQUIRE_FAST claim_free port={0} slot={1} ms={2}" -f $port, $slot, $sw.ElapsedMilliseconds) 'INFO'
        return $true
    }

    # Pass 2: TCP-open ports — only then do ownership/foreign checks (expensive).
    foreach ($c in $candidates) {
        $port = [int]$c.Port
        $slot = [int]$c.Slot
        if ($probePorts -notcontains $port) { continue }
        if (-not $openSet.Contains($port)) { continue }
        if (Test-TunnelPortIsForeignPeer -TargetPort $port -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds) {
            continue
        }
        $script:Port = $port
        Clear-TunnelBannerCache
        $banner = Get-TunnelBanner
        if ($banner -and -not (Test-TunnelBannerIsWindows -Banner $banner)) {
            Write-GitModeLog "ACQUIRE_STALE: foreign_banner port=$port banner=$banner" 'DEBUG'
            Clear-ServerStaleTunnelForward -TargetPort $port
            Clear-TunnelBannerCache
            $banner = Get-TunnelBanner
            if ($banner -and -not (Test-TunnelBannerIsWindows -Banner $banner)) { continue }
            if (Test-TunnelPortIsForeignPeer -TargetPort $port -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds) { continue }
        }
        if (-not $banner) {
            if (Test-TunnelPortAuthOwned -TargetPort $port) {
                Write-GitModeLog "ACQUIRE_STALE: sticky_ours port=$port reclaim" 'DEBUG'
                Clear-ServerStaleTunnelForward -TargetPort $port
                Clear-TunnelBannerCache
                $banner = Get-TunnelBanner
            } elseif (Test-TunnelPortIsForeignPeer -TargetPort $port -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds) {
                continue
            } else {
                Write-GitModeLog "ACQUIRE_STALE: zombie port=$port tcp=open banner=(empty)" 'WARN'
                Clear-ServerStaleTunnelForward -TargetPort $port
                Clear-TunnelBannerCache
                $banner = Get-TunnelBanner
            }
            if ($banner -and -not (Test-TunnelBannerIsWindows -Banner $banner)) { continue }
            if (Test-TunnelPortIsForeignPeer -TargetPort $port -CurrentBgTunnel $CurrentBgTunnel -ProtectedProcessIds $ProtectedProcessIds) { continue }
            if (-not $banner -and $openSet.Contains($port)) { continue }
        }
        if (-not $banner -or (Test-TunnelBannerIsWindows -Banner $banner)) {
            $localNow = @(Get-LocalTunnelSshPids -TargetPort $port)
            if ($banner -and $localNow.Count -eq 0 -and -not (Test-TunnelPortAuthOwned -TargetPort $port)) {
                Write-GitModeLog "ACQUIRE_SKIP: unauth_windows port=$port slot=$slot" 'INFO'
                continue
            }
            $script:TunnelSlot = $slot
            $script:Port = $port
            Save-TunnelSlot
            Push-ServerConnectConf
            Write-GitModeLog ("ACQUIRE_FAST claim_reclaim port={0} slot={1} ms={2}" -f $port, $slot, $sw.ElapsedMilliseconds) 'INFO'
            return $true
        }
    }

    $script:Port = $portBase + [int]$UidStr
    $script:TunnelSlot = 0
    Write-GitModeLog ("ACQUIRE_FAST fail ms={0} fallback_port={1}" -f $sw.ElapsedMilliseconds, $script:Port) 'WARN'
    return $false
}

'@

if ($nl -eq "`r`n") { $newAcq = $newAcq -replace "(?<!\r)`n", "`r`n" }
$g = $g.Remove($acqStart, $acqEnd - $acqStart).Insert($acqStart, $newAcq)

# ForeignPeer: TCP before banner (when possible) — reorder to avoid SSH banner on closed ports
# Replace the try body start to check tcp first via a quick path
$oldFp = @'
    try {
        Clear-TunnelBannerCache
        $banner = Get-TunnelBanner
        $tcpOpen = $false
        try { $tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen = $false }
        if (-not $tcpOpen -and -not (Test-TunnelBannerIsWindows -Banner $banner)) {
            return $false
        }
'@
$newFp = @'
    try {
        $tcpOpen = $false
        try { $tcpOpen = [bool](Test-TunnelPortTcpOpen) } catch { $tcpOpen = $false }
        if (-not $tcpOpen) {
            # Closed port cannot be a live foreign peer — skip expensive banner/hostkey SSH.
            return $false
        }
        Clear-TunnelBannerCache
        $banner = Get-TunnelBanner
        if (-not $tcpOpen -and -not (Test-TunnelBannerIsWindows -Banner $banner)) {
            return $false
        }
'@
$replacedFp = $false
foreach ($pair in @(@($oldFp, $newFp), @(($oldFp -replace "`r`n","`n"), ($newFp -replace "`r`n","`n")))) {
  if ($g.Contains($pair[0])) { $g = $g.Replace($pair[0], $pair[1]); $replacedFp = $true; break }
}
if (-not $replacedFp) { Write-Host 'WARN ForeignPeer reorder skipped' } else { Write-Host 'OK ForeignPeer tcp-first' }

[IO.File]::WriteAllText($gm, $g)

# version
$cps = Join-Path $root 'scripts\client\windows\connect.ps1'
$c = [IO.File]::ReadAllText($cps)
$c = [regex]::Replace($c, "ConnectVersion = '20260721\.\d+'", "ConnectVersion = '20260721.13'")
[IO.File]::WriteAllText($cps, $c)
[IO.File]::WriteAllText((Join-Path $root 'scripts\client\windows\connect-version.txt'), '20260721.13')

$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($gm, [ref]$null, [ref]$errs)
if ($errs -and $errs.Count) { $errs | ForEach-Object { $_.ToString() }; throw 'parse fail' }
Write-Host 'PARSE_OK'

$v = [IO.File]::ReadAllText($gm)
foreach ($m in @('Get-ServerOpenTunnelPorts','ACQUIRE_FAST claim_free','Get-LocalTunnelPortPidMap','skip_acquire')) {
  if ($v -notmatch [regex]::Escape($m) -and $v -notmatch $m.Replace(' ','\s+')) {
    if ($v.Contains($m)) { "HAS $m" } else { throw "MISSING $m" }
  } else { "HAS $m" }
}
Write-Host 'DONE'
