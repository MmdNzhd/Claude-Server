#Requires -Version 5.1
# test-tunnel-banner-transport.ps1
# Bug2 (P0.2): transport/timeout strings must NOT be classified as "foreign banner".
# Also locks brief negative banner cache so dead-link probes are not re-issued every tick.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== tunnel banner transport vs foreign + negative cache ===' -ForegroundColor Cyan
Write-Host ''

$gmPath = Get-ClientFile 'git-mode.ps1'
$shPath = Get-ClientFile 'git-mode.sh'
$gmSrc = Get-Content -LiteralPath $gmPath -Raw
$shSrc = Get-Content -LiteralPath $shPath -Raw

# --- Static ---
Assert ($gmSrc -match 'function Test-TunnelBannerIsTransportNoise|function Test-TunnelBannerIsTransportFail') `
    'Win: Test-TunnelBannerIsTransportNoise helper exists'
Assert ($shSrc -match 'tunnel_banner_is_transport_noise|tunnel_banner_is_transport_fail') `
    'Mac: tunnel_banner_is_transport_noise helper exists'
Assert ($gmSrc -match 'transport_fail|skip_foreign_clear|transport_noise') `
    'Win: Release/Get path mentions transport_fail/skip_foreign'
Assert ($shSrc -match 'transport_fail|skip_foreign_clear|transport_noise') `
    'Mac: release/fetch path mentions transport_fail'
Assert ($gmSrc -match 'TunnelBannerCacheNegative|BannerCacheNegative|negative.?cache') `
    'Win: negative banner cache state exists'
Assert ($shSrc -match '_TUNNEL_BANNER_CACHE_NEGATIVE|BANNER_CACHE_NEGATIVE') `
    'Mac: negative banner cache state exists'

$rel = Get-FunctionSource -Content $gmSrc -Name 'Release-StaleTunnelPort'
Assert ($rel -match 'Test-TunnelBannerIsTransportNoise|Test-TunnelBannerIsTransportFail') `
    'Win Release-StaleTunnelPort guards foreign path with transport check'

# --- Behavioral ---
Write-Host '-- behavioral transport classification --' -ForegroundColor White

$CfgDir = Join-Path $env:TEMP ("banner-tx-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null
try {
    . $gmPath

    $script:Port = 20020
    $script:gmLogs = New-Object System.Collections.Generic.List[string]
    $script:ClearCalls = 0
    $script:SshXCalls = 0
    $script:SshXBannerOut = 'ssh: connect to host 192.168.210.240 port 22: Unknown error'

    function Write-GitModeLog {
        param([string]$Message, [string]$Level = 'INFO')
        [void]$script:gmLogs.Add($Message)
    }
    function Write-ConnectLog {
        param([string]$Message, [string]$Level = 'INFO')
        [void]$script:gmLogs.Add($Message)
    }
    function SshX {
        param([string]$Cmd, [switch]$NoRetryOnTimeout)
        $script:SshXCalls++
        return @($script:SshXBannerOut)
    }
    function Clear-ServerStaleTunnelForward {
        param([int]$TargetPort = $Port)
        $script:ClearCalls++
    }
    function Test-TunnelPortTcpOpen {
        param([int]$TargetPort = 0, [int]$MaxCacheAgeMs = 0)
        return $false
    }
    function Test-TunnelPortIsForeignPeer { param([int]$TargetPort) $false }
    function Get-LocalTunnelSshPids { param([int]$TargetPort) @() }
    function Test-TunnelPortAuthOwned { param([int]$TargetPort) $false }
    function Clear-TunnelAuthOwnedCache { param([int]$TargetPort) }
    function Add-ClearedTunnelPort { param([int]$TargetPort) }

    # Helper: Unknown error / timeout strings are transport noise
    Assert (Test-TunnelBannerIsTransportNoise -Banner 'ssh: connect to host x port 22: Unknown error') `
        'helper: Unknown error is transport noise'
    Assert (Test-TunnelBannerIsTransportNoise -Banner 'Connection timed out') `
        'helper: Connection timed out is transport noise'
    Assert (Test-TunnelBannerIsTransportNoise -Banner 'banner exchange: Connection to UNKNOWN port -1: Connection timed out') `
        'helper: banner exchange timeout is transport noise'
    Assert (-not (Test-TunnelBannerIsTransportNoise -Banner 'SSH-2.0-OpenSSH_9.2p1 Debian-2')) `
        'helper: real Linux SSH banner is NOT transport noise'
    Assert (-not (Test-TunnelBannerIsTransportNoise -Banner 'SSH-2.0-OpenSSH_for_Windows_9.5')) `
        'helper: real Windows SSH banner is NOT transport noise'

    # Get-TunnelBanner sanitizes transport noise to empty
    Clear-TunnelBannerCache
    $script:SshXCalls = 0
    $script:SshXBannerOut = 'ssh: connect to host 192.168.210.240 port 22: Unknown error'
    $b1 = Get-TunnelBanner
    Assert ([string]::IsNullOrEmpty($b1)) 'Get-TunnelBanner returns empty for Unknown error'
    Assert ($script:gmLogs -join "`n" -match 'transport_fail|transport_noise') `
        'Get-TunnelBanner logs transport_fail for Unknown error'

    # Negative cache: second call within TTL does not re-probe
    $script:gmLogs.Clear()
    $callsAfterFirst = [int]$script:SshXCalls
    $b2 = Get-TunnelBanner
    Assert ([string]::IsNullOrEmpty($b2)) 'negative cache: still empty'
    Assert ([int]$script:SshXCalls -eq $callsAfterFirst) `
        'negative cache: no extra SshX probe within TTL'

    # Release-StaleTunnelPort must NOT take foreign-banner kill path on transport noise
    # (inject banner via stub that bypasses Get sanitization to test Release guard)
    Clear-TunnelBannerCache
    $script:ClearCalls = 0
    $script:gmLogs.Clear()
    function Get-TunnelBanner {
        param([int]$TargetPort = 0)
        return 'ssh: connect to host 192.168.210.240 port 22: Unknown error'
    }
    Release-StaleTunnelPort
    $rlog = ($script:gmLogs -join "`n")
    Assert ($rlog -notmatch 'foreign banner') 'Release: does not log foreign banner for transport noise'
    Assert ($script:ClearCalls -eq 0) 'Release: does not Clear-ServerStaleTunnelForward for transport noise'
    Assert ($rlog -match 'transport_fail|skip_foreign|transport_noise') `
        'Release: logs transport skip path'

    # Positive control: a real foreign OpenSSH Linux banner still clears
    function Get-TunnelBanner {
        param([int]$TargetPort = 0)
        return 'SSH-2.0-OpenSSH_9.2p1 Debian-2'
    }
    $script:ClearCalls = 0
    $script:gmLogs.Clear()
    Release-StaleTunnelPort
    $flog = ($script:gmLogs -join "`n")
    Assert ($flog -match 'foreign banner') 'Release: real foreign SSH banner still logs foreign banner'
    Assert ($script:ClearCalls -ge 1) 'Release: real foreign SSH banner still clears'
} finally {
    try { Remove-Item -LiteralPath $CfgDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All tunnel-banner-transport contracts passed ({0} asserts)." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} passed, {1} failed." -f $Pass, $Fail) -ForegroundColor Red
exit 1
