#Requires -Version 5.1
# test-tunnel-wait-backoff-fanout.ps1
# Bug3 (P0.3): wait-timeout backoff must keep increasing past streak>=6 (no skip-sleep),
# Wait loop fan-out is capped, and SshX classifies "Unknown error" as escalate ERROR.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== tunnel wait backoff + fan-out + Unknown error escalate ===' -ForegroundColor Cyan
Write-Host ''

$gmPath = Get-ClientFile 'git-mode.ps1'
$shPath = Get-ClientFile 'git-mode.sh'
$winConnect = Get-ClientFile 'windows/connect.ps1'
$macConnect = Get-ClientFile 'mac/connect.sh'
$gmSrc = Get-Content -LiteralPath $gmPath -Raw
$shSrc = Get-Content -LiteralPath $shPath -Raw
$winSrc = Get-Content -LiteralPath $winConnect -Raw
$macSrc = Get-Content -LiteralPath $macConnect -Raw

# --- Static: inverted backoff gone ---
$ens = Get-FunctionSource -Content $gmSrc -Name 'Ensure-SessionTunnel'
Assert (-not [string]::IsNullOrWhiteSpace($ens)) 'extracted Ensure-SessionTunnel'
# Old bug: sleep only in else of streak>=6 (skip sleep at high streak). Must sleep unconditionally.
Assert ($ens -notmatch '(?s)if\s*\(\s*\$script:TunnelWaitFailStreak\s*-ge\s*6\s*\)\s*\{[^}]*wait_timeout_budget_exhausted[^}]*\}\s*else\s*\{\s*Start-Sleep') `
    'Win: no skip-sleep else-branch after streak>=6'
Assert ($ens -match 'Start-Sleep\s+-Seconds\s*\(?\[int\]\$script:TunnelWaitBackoffSec') `
    'Win: Start-Sleep uses TunnelWaitBackoffSec after wait_timeout'
Assert ($shSrc -notmatch '(?s)TUNNEL_WAIT_FAIL_STREAK" -ge 6 \]; then.*?wait_timeout_budget_exhausted.*?else\s*\n\s*sleep "\$TUNNEL_WAIT_BACKOFF_SEC"') `
    'Mac: no skip-sleep else-branch after streak>=6'

# Wait loop capped (was 12; locked at TunnelWaitMaxAttempts=6 / seq 1 6)
$waitFn = Get-FunctionSource -Content $gmSrc -Name 'Wait-ForTunnelUp'
Assert ($waitFn -match 'TunnelWaitMaxAttempts|for\s*\(\s*\$i\s*=\s*1;\s*\$i\s*-le\s*6\s*;') `
    'Win Wait-ForTunnelUp max attempts capped at 6'
Assert ($shSrc -match 'TUNNEL_WAIT_MAX_ATTEMPTS=6|seq 1 6') `
    'Mac wait/poll max attempts capped at 6'

# Unknown error escalate in SshX (Win + Mac)
Assert ($winSrc -match '(?i)Unknown error') 'Win connect.ps1 SshX mentions Unknown error'
Assert ($winSrc -match '(?i)Permission denied\|Connection refused\|Could not resolve\|No route to host\|Connection timed out\|Unknown error') `
    'Win SshX escalate regex includes Unknown error'
Assert ($macSrc -match '(?i)Unknown error') 'Mac connect.sh sshx mentions Unknown error'

# --- Behavioral: backoff always sleeps and grows past streak 6 ---
Write-Host '-- behavioral monotonic backoff --' -ForegroundColor White

$CfgDir = Join-Path $env:TEMP ("wait-backoff-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
try {
    . $gmPath

    $script:Port = 20020
    $script:gmLogs = New-Object System.Collections.Generic.List[string]
    $script:SleepSecLog = New-Object System.Collections.Generic.List[int]
    $script:TunnelWaitFailStreak = 5
    $script:TunnelWaitBackoffSec = 32

    function Write-GitModeLog {
        param([string]$Message, [string]$Level = 'INFO')
        [void]$script:gmLogs.Add($Message)
    }
    function Write-ConnectLog {
        param([string]$Message, [string]$Level = 'INFO')
        [void]$script:gmLogs.Add($Message)
    }
    function SshX { param([string]$Cmd, [switch]$NoRetryOnTimeout) @('1000') }
    function Start-Sleep {
        param(
            [int]$Seconds = 0,
            [int]$Milliseconds = 0
        )
        if ($Seconds -gt 0) { [void]$script:SleepSecLog.Add([int]$Seconds) }
    }
    function Test-TunnelUp { param([int]$Retries = 0) $false }
    function Wait-ForTunnelUp { param($TunnelProc, [switch]$Quiet) $false }
    function Test-StaleForwardStillBusyAbort { param([int]$TargetPort) $false }
    function Release-StaleTunnelPort { }
    function Remove-LocalOrphanTunnel { param($TargetPort, $CurrentBgTunnel, $ProtectedProcessIds) }
    function Sanitize-SshAliasConfig { param([string]$CfgPath, [string]$AliasName) }
    function Clear-LegacyDynamicSocksTunnels { param($ProtectPid, $SocksPort) 0 }
    function Test-RemoteXraySocksOpen { param([string]$Alias, [string]$SshCfgPath = '', [switch]$ForceProbe) $false }
    function Claim-CursorProxyOwner { $true }
    function Complete-CursorProxyAfterTunnel { }
    function Clear-TunnelBannerCache { }
    function Clear-TunnelTcpState { param([int]$Port) }
    function Clear-ServerStaleTunnelForward { param([int]$TargetPort) }
    function Get-LocalTunnelSshPids { param([int]$TargetPort) @() }
    function Test-TunnelPortTcpOpen { param([int]$TargetPort = 0, [int]$MaxCacheAgeMs = 0) $false }
    function Get-SocksProxyPort { 18999 }
    function Get-HttpProxyPort { 18998 }
    function Test-LocalPortFree { param([int]$PortNum) $true }
    function Test-LocalPortOpen { param([int]$PortNum) $false }
    function Add-TunnelHttpProxyLeg { param($SshArgs, [string]$Alias, [string]$SshCfgPath = '') }
    function Add-CursorProxySidecarJobProcess { param($Process) }
    function Stop-TunnelProcessWithExitLog { param([int]$ProcessId, [string]$Reason = '') }
    function Start-Process {
        param(
            [Parameter(Position = 0)][string]$FilePath,
            [string[]]$ArgumentList,
            [switch]$PassThru,
            [System.Diagnostics.ProcessWindowStyle]$WindowStyle,
            [switch]$NoNewWindow
        )
        return [pscustomobject]@{ Id = 88801; HasExited = $false }
    }

    $bg = $null
    $reused = $false
    $beforeBackoff = [int]$script:TunnelWaitBackoffSec
    $null = Ensure-SessionTunnel -Alias 'claude-server' -SshCfgPath '' -BgTunnel ([ref]$bg) -TunnelReused ([ref]$reused)
    $logText = ($script:gmLogs -join "`n")
    Assert ($logText -match 'wait_timeout_budget_exhausted') 'streak>=6 still surfaces wait_timeout_budget_exhausted'
    Assert ($script:SleepSecLog.Count -ge 1) 'streak>=6 STILL sleeps (no inverted skip)'
    Assert ([int]$script:SleepSecLog[0] -eq $beforeBackoff) 'sleep uses current backoff before bump'
    Assert ([int]$script:TunnelWaitBackoffSec -ge [Math]::Min(60, $beforeBackoff * 2)) `
        'backoff doubles (capped) after high-streak failure'
} finally {
    try { Remove-Item -LiteralPath $CfgDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All tunnel-wait-backoff-fanout contracts passed ({0} asserts)." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} passed, {1} failed." -f $Pass, $Fail) -ForegroundColor Red
exit 1
