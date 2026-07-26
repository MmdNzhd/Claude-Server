#Requires -Version 5.1
# Cross-cutting session-fresh TTL consistency + false-green guards.
# Complements test-session-fresh-probe-skips*.ps1 with shared 30s family,
# mount 60s isolation, boundary matrix, and Clear/recover invalidation.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
$passed = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Session-fresh TTL matrix (cross-cutting) ===' -ForegroundColor Cyan
Write-Host ''

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw

$pushConf = Get-FunctionSource -Content $gm -Name 'Push-ServerConnectConf'
$ttu = Get-FunctionSource -Content $gm -Name 'Test-TunnelUp'
$ensureCached = Get-FunctionSource -Content $gm -Name 'Ensure-LaptopReverseSshCached'
$clearMount = Get-FunctionSource -Content $gm -Name 'Clear-SessionMount'

Assert (-not [string]::IsNullOrWhiteSpace($pushConf)) 'extracted Push-ServerConnectConf'
Assert (-not [string]::IsNullOrWhiteSpace($ttu)) 'extracted Test-TunnelUp'
Assert (-not [string]::IsNullOrWhiteSpace($ensureCached)) 'extracted Ensure-LaptopReverseSshCached'
Assert (-not [string]::IsNullOrWhiteSpace($clearMount)) 'extracted Clear-SessionMount'

# =============================================================================
# 1) Same TTL family: TotalSeconds -lt 30 for session_tunnel_fresh
# =============================================================================
Write-Host '-- 1) Shared 30s session_tunnel_fresh TTL family --' -ForegroundColor White

Assert ($pushConf -match 'TotalSeconds\s*-lt\s*30') `
    '1: Push-ServerConnectConf uses TotalSeconds -lt 30'
Assert ($ttu -match 'TotalSeconds\s*-lt\s*30') `
    '1: Test-TunnelUp uses TotalSeconds -lt 30'
Assert ($ensureCached -match 'TotalSeconds\s*-lt\s*30') `
    '1: Ensure-LaptopReverseSshCached uses TotalSeconds -lt 30'

# Guard: each must actually mention session_tunnel_fresh (not a silent -lt 30 elsewhere).
Assert ($pushConf -match 'reason=session_tunnel_fresh') `
    '1-guard: Push-ServerConnectConf logs reason=session_tunnel_fresh'
Assert ($ttu -match 'reason=session_tunnel_fresh') `
    '1-guard: Test-TunnelUp logs reason=session_tunnel_fresh'
Assert ($ensureCached -match 'reason=session_tunnel_fresh') `
    '1-guard: Ensure-LaptopReverseSshCached logs reason=session_tunnel_fresh'

# =============================================================================
# 2) Mount check TTL is 60s â€” must NOT share 30s with tunnel fresh
# =============================================================================
Write-Host '-- 2) Mount check TTL is 60 (not 30) --' -ForegroundColor White

$mountTtlBlock = [regex]::Match(
    $connect,
    '(?ms)LastMountCheckOkAt.*?TotalSeconds\s*-lt\s*(\d+)'
).Value
Assert ($mountTtlBlock.Length -gt 20) '2: extracted LastMountCheckOkAt TTL comparison'
Assert ($mountTtlBlock -match 'TotalSeconds\s*-lt\s*60') `
    '2: mount check uses TotalSeconds -lt 60'
Assert ($mountTtlBlock -notmatch 'TotalSeconds\s*-lt\s*30') `
    '2 HARD: mount check must NOT use TotalSeconds -lt 30 (tunnel-fresh family)'

# =============================================================================
# 3) Test-TunnelUp spawn skip logs reason=session_tunnel_fresh
# =============================================================================
Write-Host '-- 3) Test-TunnelUp reason=session_tunnel_fresh --' -ForegroundColor White

Assert ($ttu -match 'reason=session_tunnel_fresh') `
    '3: Test-TunnelUp source logs reason=session_tunnel_fresh'

# =============================================================================
# 4) Ensure-LaptopReverseSshCached session skip logs reason=session_tunnel_fresh
# =============================================================================
Write-Host '-- 4) Ensure-LaptopReverseSshCached reason=session_tunnel_fresh --' -ForegroundColor White

Assert ($ensureCached -match 'reason=session_tunnel_fresh') `
    '4: Ensure-LaptopReverseSshCached source logs reason=session_tunnel_fresh'

# =============================================================================
# 5) Behavioral matrix for Test-TunnelUp (dot-source body, stub Get-TunnelBanner)
# =============================================================================
Write-Host '-- 5) Test-TunnelUp behavioral BannerCalls matrix --' -ForegroundColor White

$script:BannerCallCount = 0
$script:GitModeLogLines = New-Object System.Collections.Generic.List[string]
function Write-GitModeLog {
    param([string]$Message, [string]$Level = 'INFO')
    $script:GitModeLogLines.Add("$Level|$Message")
}
function Get-TunnelBanner {
    param([int]$TargetPort = 0)
    $script:BannerCallCount++
    return 'SSH-2.0-OpenSSH_for_Windows'
}
function Test-TunnelBannerIsWindows {
    param([string]$Banner)
    return ($Banner -match 'OpenSSH_for_Windows|SSH-2.0')
}

$Port = 21004
$script:TunnelBannerCacheInvalidate = $true  # force spawn-TTL path only (no 3s banner cache hit)
$script:TunnelBannerCacheAt = $null
$script:TunnelBannerCacheUp = $false
$script:TunnelBannerCacheBanner = ''
$script:TunnelSoftFailCount = 0

. ([scriptblock]::Create($ttu))

function Invoke-TtuMatrixCase {
    param(
        [double]$AgeSec,
        [bool]$PortMatch,
        [bool]$PidMatch,
        [string]$BgMode,   # 'alive' | 'exited'
        [string]$Expect,   # '0' | 'ge1'
        [string]$Label
    )
    $script:LastTunnelSpawnSuccessAt = (Get-Date).AddSeconds(-$AgeSec)
    $script:LastTunnelSpawnSuccessPort = if ($PortMatch) { $Port } else { $Port + 1 }
    $script:LastTunnelSpawnPid = 424242
    $bgPid = if ($PidMatch) { 424242 } else { 999001 }
    $hasExited = ($BgMode -eq 'exited')
    $script:SessionBgTunnel = [pscustomobject]@{ Id = $bgPid; HasExited = $hasExited }
    $script:TunnelBannerCacheInvalidate = $true
    $script:TunnelBannerCacheAt = $null
    $script:TunnelBannerCacheUp = $false
    $script:BannerCallCount = 0
    $null = Test-TunnelUp
    if ($Expect -eq '0') {
        Assert ($script:BannerCallCount -eq 0) "5-matrix: $Label -> BannerCalls=0"
    } else {
        Assert ($script:BannerCallCount -ge 1) "5-matrix: $Label -> BannerCalls>=1"
    }
}

# | LastAt age | Port match | Pid match | Bg alive | expect BannerCalls |
Invoke-TtuMatrixCase -AgeSec 0  -PortMatch $true  -PidMatch $true  -BgMode 'alive'  -Expect '0'   -Label 'age=0s port=yes pid=yes bg=alive'
Invoke-TtuMatrixCase -AgeSec 0  -PortMatch $true  -PidMatch $true  -BgMode 'exited' -Expect 'ge1' -Label 'age=0s port=yes pid=yes bg=HasExited'
Invoke-TtuMatrixCase -AgeSec 0  -PortMatch $false -PidMatch $true  -BgMode 'alive'  -Expect 'ge1' -Label 'age=0s port=no pid=yes bg=alive'
Invoke-TtuMatrixCase -AgeSec 0  -PortMatch $true  -PidMatch $false -BgMode 'alive'  -Expect 'ge1' -Label 'age=0s port=yes pid=no bg=alive'
Invoke-TtuMatrixCase -AgeSec 29 -PortMatch $true  -PidMatch $true  -BgMode 'alive'  -Expect '0'   -Label 'age=29s port=yes pid=yes bg=alive'
Invoke-TtuMatrixCase -AgeSec 30 -PortMatch $true  -PidMatch $true  -BgMode 'alive'  -Expect 'ge1' -Label 'age=30s boundary (-lt 30) probes'

# =============================================================================
# 6) Ensure-LaptopReverseSshCached: skip then clear stamps -> probe
# =============================================================================
Write-Host '-- 6) Ensure-LaptopReverseSshCached skip then probe after clear --' -ForegroundColor White

$script:ReverseProbeCount = 0
$script:EnsureReverseCount = 0
$script:GitModeLogLines = New-Object System.Collections.Generic.List[string]
function Write-GitModeLog {
    param([string]$Message, [string]$Level = 'INFO')
    $script:GitModeLogLines.Add("$Level|$Message")
}
function Test-TunnelUp { param([int]$Retries = 0) return $true }
function Test-LaptopReverseSsh {
    $script:ReverseProbeCount++
    return $false
}
function Ensure-LaptopReverseSsh {
    param([string]$PubB = '')
    $script:EnsureReverseCount++
    return 1
}

$script:LaptopSshVerified = $false
$script:LastTunnelSpawnSuccessAt = Get-Date
$script:LastTunnelSpawnSuccessPort = 21004
$script:LastTunnelSpawnPid = 424242
$Port = 21004
$script:SessionBgTunnel = [pscustomobject]@{ Id = 424242; HasExited = $false }
$script:TunnelBannerCacheUp = $false

. ([scriptblock]::Create($ensureCached))

$script:ReverseProbeCount = 0
$script:EnsureReverseCount = 0
$rcFresh = Ensure-LaptopReverseSshCached -PubB 'ssh-ed25519 AAAA'
Assert ($rcFresh -eq 0) '6-beh: verified=false + spawn fresh + SessionBgTunnel alive + age=0 returns 0'
Assert (($script:ReverseProbeCount + $script:EnsureReverseCount) -eq 0) `
    '6-beh: session-fresh skip (banner not required) -> ReverseProbe+EnsureReverse = 0'

# Clear spawn stamps -> next call must probe
$script:LastTunnelSpawnSuccessAt = $null
$script:LastTunnelSpawnPid = $null
$script:LastTunnelSpawnSuccessPort = $null
$script:LaptopSshVerified = $false
$script:TunnelBannerCacheUp = $false
$script:ReverseProbeCount = 0
$script:EnsureReverseCount = 0
$null = Ensure-LaptopReverseSshCached -PubB 'ssh-ed25519 AAAA'
Assert (($script:ReverseProbeCount + $script:EnsureReverseCount) -ge 1) `
    '6-beh: after clearing spawn stamps, next call probes >=1'

# =============================================================================
# 7) Clear-SessionMount clears both LastMountCheckOk*
# =============================================================================
Write-Host '-- 7) Clear-SessionMount clears LastMountCheckOk* --' -ForegroundColor White

Assert ($clearMount -match 'LastMountCheckOkAt\s*=\s*\$null') `
    '7: Clear-SessionMount clears LastMountCheckOkAt'
Assert ($clearMount -match 'LastMountCheckOkProject\s*=\s*\$null') `
    '7: Clear-SessionMount clears LastMountCheckOkProject'

# =============================================================================
# 8) connect.ps1: session_mount_ok skip + recover-fail clear path
# =============================================================================
Write-Host '-- 8) connect.ps1 session_mount_ok + recover-fail clear --' -ForegroundColor White

Assert ($connect -match 'MOUNT_CHECK_SKIPPED reason=session_mount_ok') `
    '8: connect.ps1 has session_mount_ok skip path'
Assert (
    ($connect -match '(?ms)if\s*\(\s*\$recoverCheckOk\s*\)\s*\{.*?LastMountCheckOkAt\s*=\s*Get-Date') -and
    ($connect -match '(?ms)else\s*\{\s*\$script:LastMountCheckOkAt\s*=\s*\$null\s*\$script:LastMountCheckOkProject\s*=\s*\$null')
) '8: recover fail clear path sets both LastMountCheckOk* to $null'

# =============================================================================
# 9) HARD: gitModeOff recover gated by mountCheckSessionOk
# =============================================================================
Write-Host '-- 9) HARD: no Invoke-RecoverIfNeeded when mountCheckSessionOk --' -ForegroundColor White

$gitOffBlock = [regex]::Match(
    $connect,
    '(?ms)if\s*\(\s*\$gitModeOff\s*\)\s*\{.*?\$mountCheckSessionOk.*?Invoke-RecoverIfNeeded.*?^\s*\}'
).Value
if ($gitOffBlock.Length -lt 80) {
    $gitOffBlock = [regex]::Match(
        $connect,
        '(?ms)\$mountCheckSessionOk\s*=\s*\$false.*?if\s*\(\s*-not\s*\$mountCheckSessionOk\s*\)\s*\{.*?Invoke-RecoverIfNeeded.*?\}'
    ).Value
}
Assert ($gitOffBlock.Length -gt 80) '9: extracted gitModeOff / mountCheckSessionOk recover block'

# Exact gating pattern required by contract
Assert ($gitOffBlock -match '(?ms)if\s*\(\s*-not\s*\$mountCheckSessionOk\s*\)\s*\{[^}]*Invoke-RecoverIfNeeded') `
    '9 HARD: if (-not $mountCheckSessionOk) { ... Invoke-RecoverIfNeeded }'

# False-green guard: must NOT call Invoke-RecoverIfNeeded unconditionally inside gitModeOff
# (i.e. call must sit inside the -not $mountCheckSessionOk gate, not before it).
$ungated = [regex]::Match(
    $gitOffBlock,
    '(?ms)\$mountCheckSessionOk\s*=\s*\$false.*?Invoke-RecoverIfNeeded.*?if\s*\(\s*-not\s*\$mountCheckSessionOk\s*\)'
)
Assert (-not $ungated.Success) `
    '9-guard: Invoke-RecoverIfNeeded must not appear before if (-not $mountCheckSessionOk)'

Write-Host ''
Write-Host "Passed: $passed  Failed: $fail" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) {
    Write-Host "$fail test(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host 'All tests passed.' -ForegroundColor Green
exit 0
