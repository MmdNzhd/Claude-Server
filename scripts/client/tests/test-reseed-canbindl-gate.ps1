#Requires -Version 5.1
# test-reseed-canbindl-gate.ps1 - Gap: ReseedRaw AND NOT CanBindL must not kill -R
# Locks D1/D2 + S2 token foreign_owner_cannot_bind (Win Ensure, connect.ps1 bg_init, Mac).
# Pattern: test-tunnel-proxy-skip-hard.ps1 (static + behavioral counters).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== reseed CanBindL gate (foreign_owner_cannot_bind) ===' -ForegroundColor Cyan
Write-Host ''

$gmPath = Get-ClientFile 'git-mode.ps1'
$winPath = Get-ClientFile 'windows\connect.ps1'
$shPath = Get-ClientFile 'git-mode.sh'
$gm = Get-Content -LiteralPath $gmPath -Raw
$win = Get-Content -LiteralPath $winPath -Raw
$sh = Get-Content -LiteralPath $shPath -Raw

# --- Static (necessary, not sufficient) ---
Assert ($gm -match 'function Test-CanClaimCursorProxyOwner') 'Win Test-CanClaimCursorProxyOwner'
Assert ($gm -match 'function Test-ProxyReseedShouldKill') 'Win Test-ProxyReseedShouldKill preferred chokepoint'
Assert ($gm -match 'foreign_owner_cannot_bind') 'Win foreign_owner_cannot_bind'
Assert ($win -match 'foreign_owner_cannot_bind') 'connect.ps1 bg_init token'
Assert ($sh -match 'can_claim_cursor_proxy_owner') 'Mac can_claim_cursor_proxy_owner'
Assert ($sh -match 'foreign_owner_cannot_bind') 'Mac foreign_owner_cannot_bind'
Assert ($sh -match 'proxy_reseed_should_kill|can_claim_cursor_proxy_owner') 'Mac ensure uses claim gate helper'

$ens = Get-FunctionSource -Content $gm -Name 'Ensure-SessionTunnel'
Assert (-not [string]::IsNullOrWhiteSpace($ens)) 'extracted Ensure-SessionTunnel'
Assert ($ens -match 'Test-ProxyReseedShouldKill') 'Ensure gates via Test-ProxyReseedShouldKill'
$canRel = $ens.IndexOf('Test-ProxyReseedShouldKill')
$killRel = $ens.IndexOf('killing stale bg')
Assert ($canRel -ge 0 -and $killRel -gt $canRel) 'gate before killing stale bg in Ensure'
$gateCount = ([regex]::Matches($ens, 'Test-ProxyReseedShouldKill')).Count
Assert ($gateCount -ge 4) "Ensure calls Test-ProxyReseedShouldKill >=4 times (got $gateCount)"

$reseedFn = Get-FunctionSource -Content $gm -Name 'Test-TunnelNeedsProxyReseed'
Assert (-not [string]::IsNullOrWhiteSpace($reseedFn)) 'extracted Test-TunnelNeedsProxyReseed'
Assert ($reseedFn -notmatch 'Claim-CursorProxyOwner|Test-CanClaimCursorProxyOwner') `
    'ReseedRaw stays Claim-free'

# bg_init must clear needReseed when CanClaim false
Assert (
    ($win -match 'Test-CanClaimCursorProxyOwner') -and
    ($win -match 'bg_init_reseed_skip reason=foreign_owner_cannot_bind')
) 'connect.ps1 bg_init gates needReseed with CanClaim + token'

# Claim adopts non-Connect live PID (stale_non_connect path may land later; shape check required)
$claimFn = Get-FunctionSource -Content $gm -Name 'Claim-CursorProxyOwner'
Assert ($claimFn -match 'Test-ProcessCommandIsConnectUi') 'Claim checks Connect-shaped cmdline before live_owner skip'

# --- Behavioral: Gap => kill_count=0; positive => kill_count>=1 ---
Write-Host '-- behavioral Ensure Gap + positive --' -ForegroundColor White

$CfgDir = Join-Path $env:TEMP ("reseed-canbindl-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
try {
    . $gmPath

    $script:Port = 20020
    $script:TunnelSoftFailCount = 0
    $script:TunnelSoftFailBudget = 3
    $script:TunnelSyncFailCount = 0
    $script:SessionBgTunnel = $null
    $script:LastTunnelSpawnSuccessAt = $null
    $script:kill_count = 0
    $script:gmLogs = New-Object System.Collections.Generic.List[string]
    $script:CanClaimStub = $false

    function Write-GitModeLog {
        param([string]$Message, [string]$Level = 'INFO')
        [void]$script:gmLogs.Add($Message)
    }
    function Write-ConnectLog {
        param([string]$Message, [string]$Level = 'INFO')
        [void]$script:gmLogs.Add($Message)
    }
    function Test-TunnelUp { param([int]$Retries = 1) $true }
    function Test-TunnelPortTcpOpen { $false }
    function Get-LocalTunnelSshPids { param([int]$TargetPort) @() }
    function Set-SocksProxyPortOnReuse {
        param([int]$TunnelPid, [string]$Alias, [string]$SshCfgPath = '')
    }
    function Complete-CursorProxyAfterTunnel { }
    function Clear-TunnelBannerCache { }
    function Clear-ServerStaleTunnelForward { param([int]$TargetPort) }
    function Remove-LocalOrphanTunnel {
        param($TargetPort, $CurrentBgTunnel, $ProtectedProcessIds)
    }
    function Stop-TunnelProcessWithExitLog {
        param([int]$ProcessId, [string]$Reason = '')
        $script:kill_count++
        [void]$script:gmLogs.Add(('KILL:{0}:{1}' -f $Reason, $ProcessId))
        throw 'STOP_COUNTED_AFTER_KILL'
    }
    function Test-TunnelNeedsProxyReseed {
        param([int]$TunnelPid, [string]$Alias, [string]$SshCfgPath = '')
        return $true
    }
    function Test-CanClaimCursorProxyOwner {
        return [bool]$script:CanClaimStub
    }

    # Gap: ReseedRaw true, CanClaim false => must not kill
    $script:CanClaimStub = $false
    $script:kill_count = 0
    $script:gmLogs.Clear()
    $fakeBg = [pscustomobject]@{ Id = 424242; HasExited = $false }
    $bg = $fakeBg
    $reused = $false
    $ok = $false
    $threw = $false
    try {
        $ok = Ensure-SessionTunnel -Alias 'claude-server' -SshCfgPath '' -BgTunnel ([ref]$bg) -TunnelReused ([ref]$reused)
    } catch {
        $threw = $true
        if ("$($_.Exception.Message)" -ne 'STOP_COUNTED_AFTER_KILL') { throw }
    }
    $logText = ($script:gmLogs -join "`n")
    Assert (-not $threw) 'Gap: Ensure does not reach kill (no STOP_COUNTED throw)'
    Assert ($ok -eq $true) 'Gap: Ensure returns success $true'
    Assert ($script:kill_count -eq 0) 'Gap: kill_count=0 (D1)'
    Assert ($reused -eq $true) 'Gap: TunnelReused stays true (keep bg)'
    Assert ($logText -match 'foreign_owner_cannot_bind') 'Gap: logs foreign_owner_cannot_bind'

    # Positive: CanClaim true => kill path still runs
    $script:CanClaimStub = $true
    $script:kill_count = 0
    $script:gmLogs.Clear()
    $fakeBg2 = [pscustomobject]@{ Id = 424243; HasExited = $false }
    $bg2 = $fakeBg2
    $reused2 = $false
    $posThrew = $false
    try {
        $null = Ensure-SessionTunnel -Alias 'claude-server' -SshCfgPath '' -BgTunnel ([ref]$bg2) -TunnelReused ([ref]$reused2)
    } catch {
        $posThrew = $true
        if ("$($_.Exception.Message)" -ne 'STOP_COUNTED_AFTER_KILL') { throw }
    }
    Assert ($script:kill_count -ge 1) 'positive: kill_count>=1 when CanBindL (heal still runs)'
    Assert ($posThrew) 'positive: Stop-TunnelProcessWithExitLog reached'

    # Direct chokepoint: Test-ProxyReseedShouldKill mirrors Gap / positive
    if (Get-Command Test-ProxyReseedShouldKill -ErrorAction SilentlyContinue) {
        $script:CanClaimStub = $false
        $script:gmLogs.Clear()
        $shouldKillGap = Test-ProxyReseedShouldKill -TunnelPid 1 -Alias 'claude-server' -SshCfgPath ''
        Assert (-not $shouldKillGap) 'chokepoint: Gap => ShouldKill false'
        Assert (($script:gmLogs -join "`n") -match 'foreign_owner_cannot_bind') `
            'chokepoint: Gap logs foreign_owner_cannot_bind'

        $script:CanClaimStub = $true
        $shouldKillPos = Test-ProxyReseedShouldKill -TunnelPid 1 -Alias 'claude-server' -SshCfgPath ''
        Assert ($shouldKillPos) 'chokepoint: CanBindL => ShouldKill true'
    } else {
        Assert $false 'Test-ProxyReseedShouldKill exists for chokepoint asserts'
    }

    # bg_init sim (D2): needReseed cleared under Gap
    $script:CanClaimStub = $false
    $needReseed = $true
    if ($needReseed -and (Get-Command Test-CanClaimCursorProxyOwner -ErrorAction SilentlyContinue)) {
        if (-not (Test-CanClaimCursorProxyOwner)) {
            $needReseed = $false
            Write-ConnectLog "ENSURE_TUNNEL bg_init_reseed_skip reason=foreign_owner_cannot_bind pid=1 port=$($script:Port)" 'WARN'
        }
    }
    Assert (-not $needReseed) 'D2 sim: bg_init needReseed=false under Gap'
} finally {
    try { Remove-Item -LiteralPath $CfgDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All reseed-canbindl contracts passed ({0} asserts)." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} passed, {1} failed." -f $Pass, $Fail) -ForegroundColor Red
exit 1
