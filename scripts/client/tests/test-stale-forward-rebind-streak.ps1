#Requires -Version 5.1
# test-stale-forward-rebind-streak.ps1
# Bug1 (P0.1): still-busy refuse_spawn must rebind to another slot (D4) and cap the streak.
# Locks: refuse_spawn_streak_exhausted token, RefuseSpawnStreakCap, rebind before spawn on busy port.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== stale-forward rebind + refuse_spawn streak cap ===' -ForegroundColor Cyan
Write-Host ''

$gmPath = Get-ClientFile 'git-mode.ps1'
$shPath = Get-ClientFile 'git-mode.sh'
$gmSrc = Get-Content -LiteralPath $gmPath -Raw
$shSrc = Get-Content -LiteralPath $shPath -Raw

# --- Static contracts ---
Assert ($gmSrc -match 'refuse_spawn_streak_exhausted') 'Win: refuse_spawn_streak_exhausted token'
Assert ($shSrc -match 'refuse_spawn_streak_exhausted') 'Mac: refuse_spawn_streak_exhausted token'
Assert ($gmSrc -match 'RefuseSpawnStreakCap\s*=\s*5|RefuseSpawnStreakMax\s*=\s*5') 'Win: RefuseSpawnStreakCap=5 locked'
Assert ($shSrc -match 'REFUSE_SPAWN_STREAK_CAP=5|REFUSE_SPAWN_STREAK_MAX=5') 'Mac: REFUSE_SPAWN_STREAK_CAP=5 locked'
Assert ($gmSrc -match 'stale_port_busy_rebind|reason=stale_port_busy_rebind|rebind.*stale_port_busy') `
    'Win: still-busy path logs rebind reason'
Assert ($shSrc -match 'stale_port_busy_rebind|reason=stale_port_busy_rebind') `
    'Mac: still-busy path logs rebind reason'

$ens = Get-FunctionSource -Content $gmSrc -Name 'Ensure-SessionTunnel'
Assert (-not [string]::IsNullOrWhiteSpace($ens)) 'extracted Ensure-SessionTunnel'
Assert ($ens -match 'Acquire-TunnelPort') 'Win Ensure calls Acquire-TunnelPort on still-busy (rebind)'
Assert ($ens -match 'RefuseSpawnStreak') 'Win Ensure tracks RefuseSpawnStreak'

# --- Behavioral ---
Write-Host '-- behavioral rebind + streak --' -ForegroundColor White

$CfgDir = Join-Path $env:TEMP ("stale-rebind-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
try {
    . $gmPath

    $busyPort = 20020
    $rebindPort = 20021
    $script:Port = $busyPort
    $script:ServerUidStr = '1000'
    $script:TunnelSoftFailCount = 0
    $script:TunnelSoftFailBudget = 3
    $script:TunnelSyncFailCount = 0
    $script:SessionBgTunnel = $null
    $script:LastTunnelSpawnSuccessAt = $null
    $script:StillBusyWindowSec = 15
    $script:RefuseSpawnStreak = 0
    if (-not $script:RefuseSpawnStreakCap) { $script:RefuseSpawnStreakCap = 5 }
    $script:spawn_count = 0
    $script:spawn_ports = New-Object System.Collections.Generic.List[int]
    $script:gmLogs = New-Object System.Collections.Generic.List[string]
    $script:TcpOpenStub = $true
    $script:LocalPidStub = @()
    $script:AcquireCalls = 0
    $script:AcquireForceFail = $false

    function Write-GitModeLog {
        param([string]$Message, [string]$Level = 'INFO')
        [void]$script:gmLogs.Add($Message)
    }
    function Write-ConnectLog {
        param([string]$Message, [string]$Level = 'INFO')
        [void]$script:gmLogs.Add($Message)
    }
    function Test-TunnelUp { param([int]$Retries = 1) $false }
    function Test-TunnelPortTcpOpen {
        param([int]$TargetPort, [int]$MaxCacheAgeMs = 0)
        return [bool]$script:TcpOpenStub
    }
    function Get-LocalTunnelSshPids { param([int]$TargetPort) @($script:LocalPidStub) }
    function Set-SocksProxyPortOnReuse {
        param([int]$TunnelPid, [string]$Alias, [string]$SshCfgPath = '')
    }
    function Complete-CursorProxyAfterTunnel { }
    function Clear-TunnelBannerCache { }
    function Clear-TunnelTcpState { param([int]$Port) }
    function Clear-ServerStaleTunnelForward { param([int]$TargetPort) }
    function Release-StaleTunnelPort { }
    function Remove-LocalOrphanTunnel {
        param($TargetPort, $CurrentBgTunnel, $ProtectedProcessIds)
    }
    function Sanitize-SshAliasConfig { param([string]$CfgPath, [string]$AliasName) }
    function Clear-LegacyDynamicSocksTunnels { param($ProtectPid, $SocksPort) }
    function Test-RemoteXraySocksOpen { param([string]$Alias, [string]$SshCfgPath = '', [switch]$ForceProbe) $false }
    function Claim-CursorProxyOwner { $true }
    function Wait-ForTunnelUp { param($TunnelProc, [switch]$Quiet) $true }
    function Add-CursorProxySidecarJobProcess { param($Process) }
    function Stop-TunnelProcessWithExitLog {
        param([int]$ProcessId, [string]$Reason = '')
    }
    function Get-SocksProxyPort { 18999 }
    function Get-HttpProxyPort { 18998 }
    function Test-LocalPortFree { param([int]$PortNum) $true }
    function Test-LocalPortOpen { param([int]$PortNum) $false }
    function Add-TunnelHttpProxyLeg { param($SshArgs, [string]$Alias, [string]$SshCfgPath = '') }
    function Acquire-TunnelPort {
        param(
            [string]$UidStr,
            $CurrentBgTunnel = $null,
            $ProtectedProcessIds = @()
        )
        $script:AcquireCalls++
        if ($script:AcquireForceFail) { return $false }
        $script:Port = $script:rebindPort
        $script:TunnelSlot = 1
        $Port = $script:Port
        return $true
    }
    function Start-Process {
        param(
            [Parameter(Position = 0)][string]$FilePath,
            [string[]]$ArgumentList,
            [switch]$PassThru,
            [System.Diagnostics.ProcessWindowStyle]$WindowStyle,
            [switch]$NoNewWindow
        )
        $script:spawn_count++
        [void]$script:spawn_ports.Add([int]$script:Port)
        return [pscustomobject]@{ Id = 77702; HasExited = $false }
    }

    # Case A: still-busy -> rebind to free slot -> spawn on NEW port only
    $script:LastStaleForwardStillBusyPort = $busyPort
    $script:LastStaleForwardStillBusyAt = Get-Date
    $script:TcpOpenStub = $true
    $script:LocalPidStub = @()
    $script:Port = $busyPort
    $script:rebindPort = $rebindPort
    $script:AcquireForceFail = $false
    $script:AcquireCalls = 0
    $script:spawn_count = 0
    $script:spawn_ports.Clear()
    $script:gmLogs.Clear()
    $script:RefuseSpawnStreak = 0
    $bg = $null
    $reused = $false
    $ok = Ensure-SessionTunnel -Alias 'claude-server' -SshCfgPath '' -BgTunnel ([ref]$bg) -TunnelReused ([ref]$reused)
    $logText = ($script:gmLogs -join "`n")
    $spawnOnBusy = @($script:spawn_ports | Where-Object { $_ -eq $busyPort }).Count
    $spawnOnNew = @($script:spawn_ports | Where-Object { $_ -eq $rebindPort }).Count
    Assert ($logText -match 'stale_port_busy') 'rebind: logs stale_port_busy'
    Assert ($logText -match 'stale_port_busy_rebind|rebind') 'rebind: logs rebind'
    Assert ($script:AcquireCalls -ge 1) 'rebind: Acquire-TunnelPort called'
    Assert ($spawnOnBusy -eq 0) 'rebind: zero spawns on busy port (D4)'
    Assert ($spawnOnNew -ge 1) 'rebind: spawn on rebound port'
    Assert $ok 'rebind: Ensure returns true after spawn+Wait'
    Assert ($script:RefuseSpawnStreak -eq 0) 'rebind success resets RefuseSpawnStreak'

    # Case B: still-busy + Acquire fails repeatedly -> streak cap terminal
    # Clear Case A session bg so Ensure reaches still-busy (not soft_fail/reuse).
    $script:SessionBgTunnel = $null
    $script:LastTunnelSpawnSuccessAt = $null
    $script:LastTunnelSpawnSuccessPort = $null
    $script:LastTunnelSpawnPid = $null
    $script:TunnelSoftFailCount = 0
    $script:AcquireForceFail = $true
    $script:RefuseSpawnStreak = 0
    $script:Port = $busyPort
    $cap = 5
    if ($script:RefuseSpawnStreakCap) { $cap = [int]$script:RefuseSpawnStreakCap }
    $sawExhausted = $false
    for ($n = 1; $n -le ($cap + 1); $n++) {
        $script:LastStaleForwardStillBusyPort = $busyPort
        $script:LastStaleForwardStillBusyAt = Get-Date
        $script:TcpOpenStub = $true
        $script:LocalPidStub = @()
        $script:Port = $busyPort
        $script:SessionBgTunnel = $null
        $script:spawn_count = 0
        $script:spawn_ports.Clear()
        $script:gmLogs.Clear()
        $bg2 = $null
        $reused2 = $false
        $ok2 = Ensure-SessionTunnel -Alias 'claude-server' -SshCfgPath '' -BgTunnel ([ref]$bg2) -TunnelReused ([ref]$reused2)
        $lt = ($script:gmLogs -join "`n")
        Assert ($ok2 -eq $false) ("streak iter=$n Ensure returns false")
        Assert ($script:spawn_count -eq 0) ("streak iter=$n no spawn")
        if ($lt -match 'refuse_spawn_streak_exhausted') { $sawExhausted = $true }
    }
    Assert $sawExhausted 'streak: refuse_spawn_streak_exhausted logged within cap+1 cycles'
    Assert ([int]$script:RefuseSpawnStreak -ge $cap) 'streak: RefuseSpawnStreak reaches cap'
} finally {
    try { Remove-Item -LiteralPath $CfgDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All stale-forward-rebind-streak contracts passed ({0} asserts)." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} passed, {1} failed." -f $Pass, $Fail) -ForegroundColor Red
exit 1
