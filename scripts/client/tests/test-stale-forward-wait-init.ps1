#Requires -Version 5.1
# test-stale-forward-wait-init.ps1 - Task 3: Mac local i=0 + still-busy refuse spawn
# Locks D4 + S2 stale_port_busy + S3 STILL_BUSY_WINDOW_SEC=15.
# HARD: WARN-only then spawn same port = FAIL (spawn_count must stay 0 on still-busy).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== stale-forward wait-init + still-busy abort ===' -ForegroundColor Cyan
Write-Host ''

$gmPath = Get-ClientFile 'git-mode.ps1'
$shPath = Get-ClientFile 'git-mode.sh'
$gmSrc = Get-Content -LiteralPath $gmPath -Raw
$shSrc = Get-Content -LiteralPath $shPath -Raw

# --- Static ---
$clearFn = Get-FunctionSource -Content $gmSrc -Name 'Clear-ServerStaleTunnelForward'
Assert (-not [string]::IsNullOrWhiteSpace($clearFn)) 'extracted Clear-ServerStaleTunnelForward'
Assert ($clearFn -match 'LastStaleForwardStillBusyPort') 'Clear sets LastStaleForwardStillBusyPort'
Assert ($clearFn -match 'LastStaleForwardStillBusyAt') 'Clear sets LastStaleForwardStillBusyAt'
Assert ($clearFn -match 'port still busy') 'Clear still logs port still busy'

Assert ($gmSrc -match 'function Test-StaleForwardStillBusyAbort') 'Win Test-StaleForwardStillBusyAbort'
Assert ($gmSrc -match 'StillBusyWindowSec\s*=\s*15|STILL_BUSY_WINDOW_SEC') 'Win StillBusyWindowSec=15 locked'
Assert ($gmSrc -match 'TotalSeconds\s*-lt\s*\$windowSec|TotalSeconds\s*-ge\s*\$windowSec|StillBusyWindowSec') `
    'Win still-busy uses window seconds compare'

$ens = Get-FunctionSource -Content $gmSrc -Name 'Ensure-SessionTunnel'
Assert (-not [string]::IsNullOrWhiteSpace($ens)) 'extracted Ensure-SessionTunnel'
Assert ($ens -match 'stale_port_busy') 'Ensure emits stale_port_busy'
Assert ($ens -match 'Test-StaleForwardStillBusyAbort') 'Ensure calls Test-StaleForwardStillBusyAbort'
$abortRel = $ens.IndexOf('Test-StaleForwardStillBusyAbort')
$spawnRel = $ens.IndexOf('Start-Process ssh')
Assert ($abortRel -ge 0 -and $spawnRel -gt $abortRel) `
    'StillBusyAbort before Start-Process ssh in Ensure'

# Mac: local i=0 BEFORE while (S5)
Assert ($shSrc -match 'STILL_BUSY_WINDOW_SEC=15') 'Mac STILL_BUSY_WINDOW_SEC=15 locked'
Assert ($shSrc -match 'stale_port_busy') 'Mac stale_port_busy token'
Assert ($shSrc -match 'stale_forward_still_busy_abort') 'Mac stale_forward_still_busy_abort'
Assert (
    $shSrc -match '(?s)clear_server_stale_tunnel_forward\(\)\s*\{.*?local i=0\s*\r?\n\s*while \[ "\$i" -lt 8 \]'
) 'Mac clear_server_stale_tunnel_forward has local i=0 before while'
Assert (
    $shSrc -match '(?s)ensure_session_tunnel\(\)\s*\{.*?stale_forward_still_busy_abort.*?ssh -N'
) 'Mac ensure refuses before ssh spawn'

# --- Behavioral ---
Write-Host '-- behavioral still-busy refuse spawn --' -ForegroundColor White

$CfgDir = Join-Path $env:TEMP ("stale-fwd-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
try {
    . $gmPath

    $busyPort = 20021
    $script:Port = $busyPort
    $script:ServerUidStr = '1000'
    $script:TunnelSoftFailCount = 0
    $script:TunnelSoftFailBudget = 3
    $script:TunnelSyncFailCount = 0
    $script:SessionBgTunnel = $null
    $script:LastTunnelSpawnSuccessAt = $null
    $script:StillBusyWindowSec = 15
    $script:spawn_count = 0
    $script:spawn_ports = New-Object System.Collections.Generic.List[int]
    $script:gmLogs = New-Object System.Collections.Generic.List[string]
    $script:TcpOpenStub = $true
    $script:LocalPidStub = @()

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
    function Test-RemoteXraySocksOpen { param([string]$Alias, [string]$SshCfgPath = '') $false }
    function Claim-CursorProxyOwner { $true }
    function Wait-ForTunnelUp { param($TunnelProc, [switch]$Quiet) $true }
    function Add-CursorProxySidecarJobProcess { param($Process) }
    function Stop-TunnelProcessWithExitLog {
        param([int]$ProcessId, [string]$Reason = '')
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
        return [pscustomobject]@{ Id = 77701; HasExited = $false }
    }

    # Negative: still-busy markers + TCP open + empty local PIDs => no Start-Process on busy port
    $script:LastStaleForwardStillBusyPort = $busyPort
    $script:LastStaleForwardStillBusyAt = Get-Date
    $script:TcpOpenStub = $true
    $script:LocalPidStub = @()
    $script:spawn_count = 0
    $script:spawn_ports.Clear()
    $script:gmLogs.Clear()
    $bg = $null
    $reused = $false
    $ok = Ensure-SessionTunnel -Alias 'claude-server' -SshCfgPath '' -BgTunnel ([ref]$bg) -TunnelReused ([ref]$reused)
    $logText = ($script:gmLogs -join "`n")
    $spawnOnBusy = @($script:spawn_ports | Where-Object { $_ -eq $busyPort }).Count
    Assert ($ok -eq $false -or $script:Port -ne $busyPort) `
        'still-busy: Ensure returns false OR Port rebinds away from busy port'
    Assert ($spawnOnBusy -eq 0) 'still-busy: spawn_count on old port = 0 (D4)'
    Assert ($logText -match 'stale_port_busy') 'still-busy: logs stale_port_busy'
    Assert ($script:spawn_count -eq 0) 'still-busy: total spawn_count=0 on refuse path'

    # Positive control: markers cleared => spawn allowed
    $script:LastStaleForwardStillBusyPort = $null
    $script:LastStaleForwardStillBusyAt = $null
    $script:Port = $busyPort
    $script:TcpOpenStub = $false
    $script:LocalPidStub = @()
    $script:spawn_count = 0
    $script:spawn_ports.Clear()
    $script:gmLogs.Clear()
    $bg2 = $null
    $reused2 = $false
    $ok2 = Ensure-SessionTunnel -Alias 'claude-server' -SshCfgPath '' -BgTunnel ([ref]$bg2) -TunnelReused ([ref]$reused2)
    Assert ($script:spawn_count -ge 1) 'positive: spawn_count>=1 when not still-busy'
    Assert $ok2 'positive: Ensure returns true when spawn+Wait ok'

    # Helper direct: age window uses 15
    $script:LastStaleForwardStillBusyPort = $busyPort
    $script:LastStaleForwardStillBusyAt = (Get-Date).AddSeconds(-1)
    $script:TcpOpenStub = $true
    $script:LocalPidStub = @()
    $script:StillBusyWindowSec = 15
    Assert (Test-StaleForwardStillBusyAbort -TargetPort $busyPort) 'helper: age=1s within 15 => abort true'
    $script:LastStaleForwardStillBusyAt = (Get-Date).AddSeconds(-16)
    Assert (-not (Test-StaleForwardStillBusyAbort -TargetPort $busyPort)) 'helper: age=16s => abort false'
} finally {
    try { Remove-Item -LiteralPath $CfgDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All stale-forward-wait-init contracts passed ({0} asserts)." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} passed, {1} failed." -f $Pass, $Fail) -ForegroundColor Red
exit 1
