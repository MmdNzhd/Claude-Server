#Requires -Version 5.1
# Session-fresh probe skips (spawn-TTL / reverse-SSH / GIT_MODE=off mount check).
#   A) Test-TunnelUp spawn-TTL (#8)
#   B) Ensure-LaptopReverseSshCached session-fresh skip (#3)
#   C) GIT_MODE=off mount check TTL (#2)
# Plan refs: wave2 / connect-speed-stability leftover probes after tunnel spawn.

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
$passed = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Session-fresh probe skips ===' -ForegroundColor Cyan
Write-Host ''

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$ttu = Get-FunctionSource -Content $gm -Name 'Test-TunnelUp'
$ensureCached = Get-FunctionSource -Content $gm -Name 'Ensure-LaptopReverseSshCached'
$ensureTunnel = Get-FunctionSource -Content $gm -Name 'Ensure-SessionTunnel'
if ([string]::IsNullOrWhiteSpace($ensureTunnel)) {
    $ensureTunnel = Get-FunctionSource -Content $gm -Name 'Ensure-Tunnel'
}

Assert (-not [string]::IsNullOrWhiteSpace($ttu)) 'extracted Test-TunnelUp'
Assert (-not [string]::IsNullOrWhiteSpace($ensureCached)) 'extracted Ensure-LaptopReverseSshCached'
Assert (-not [string]::IsNullOrWhiteSpace($ensureTunnel)) 'extracted Ensure-SessionTunnel (or Ensure-Tunnel)'

# =============================================================================
# A) Test-TunnelUp spawn-TTL (#8)
# =============================================================================
Write-Host '-- A) Test-TunnelUp spawn-TTL (#8) --' -ForegroundColor White

# Source: spawn-fresh skip must consult LastTunnelSpawnSuccessAt inside Test-TunnelUp
# (or a helper it calls for this skip - not only Ensure-SessionTunnel's recent_success).
$ttuMentionsSpawnAt = $ttu -match 'LastTunnelSpawnSuccessAt'
$helperForSkip = $null
if (-not $ttuMentionsSpawnAt -and $ttu -match '([A-Za-z_][\w-]*)\s*\(') {
    # If Test-TunnelUp delegates, any helper named *Spawn*Fresh* / *SessionTunnelFresh* counts.
    $helperNames = [regex]::Matches($ttu, '(?m)\b(Test|Get|Assert)-[\w]+') | ForEach-Object { $_.Value } | Select-Object -Unique
    foreach ($hn in $helperNames) {
        if ($hn -match 'Spawn|SessionTunnelFresh|TunnelSpawnFresh') {
            $hs = Get-FunctionSource -Content $gm -Name $hn
            if ($hs -and $hs -match 'LastTunnelSpawnSuccessAt') { $helperForSkip = $hn; break }
        }
    }
}
Assert ($ttuMentionsSpawnAt -or $helperForSkip) `
    'A-src: Test-TunnelUp (or its spawn-fresh helper) mentions LastTunnelSpawnSuccessAt'

Assert ($ttu -match 'LastTunnelSpawnSuccessPort' -or ($helperForSkip -and (Get-FunctionSource -Content $gm -Name $helperForSkip) -match 'LastTunnelSpawnSuccessPort')) `
    'A-src: spawn-TTL checks LastTunnelSpawnSuccessPort match'
Assert ($ttu -match 'LastTunnelSpawnPid' -or ($helperForSkip -and (Get-FunctionSource -Content $gm -Name $helperForSkip) -match 'LastTunnelSpawnPid')) `
    'A-src: spawn-TTL checks LastTunnelSpawnPid match'
Assert ($ttu -match 'SessionBgTunnel' -or ($helperForSkip -and (Get-FunctionSource -Content $gm -Name $helperForSkip) -match 'SessionBgTunnel')) `
    'A-src: spawn-TTL requires SessionBgTunnel alive same pid'
Assert ($ttu -match 'TotalSeconds\s*-lt\s*30' -or ($helperForSkip -and (Get-FunctionSource -Content $gm -Name $helperForSkip) -match 'TotalSeconds\s*-lt\s*30')) `
    'A-src: spawn-TTL age window is < 30s'

# Must NOT be only the generic TunnelBannerCache 3s path (that path is allowed to remain,
# but spawn-TTL must be a distinct branch using LastTunnelSpawnSuccess*).
$bannerCacheOnly = ($ttu -match 'TunnelBannerCache') -and ($ttu -notmatch 'LastTunnelSpawnSuccessAt') -and (-not $helperForSkip)
Assert (-not $bannerCacheOnly) `
    'A-src: must NOT extend generic TunnelBannerCache 3s path blindly for all cases (need LastTunnelSpawnSuccess* branch)'

# Negative source: aged-out / pid-mismatch must still reach Get-TunnelBanner (probe path present).
Assert ($ttu -match 'Get-TunnelBanner') `
    'A-neg-src: Test-TunnelUp still has Get-TunnelBanner probe path for age>=30s / pid mismatch'

# Behavioral: fresh spawn markers + matching SessionBgTunnel pid -> $true WITHOUT Get-TunnelBanner.
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
$script:TunnelBannerCacheInvalidate = $false
$script:TunnelBannerCacheAt = $null
$script:TunnelBannerCacheUp = $false
$script:TunnelBannerCacheBanner = ''
$script:TunnelSoftFailCount = 0
$script:LastTunnelSpawnSuccessAt = Get-Date
$script:LastTunnelSpawnSuccessPort = $Port
$script:LastTunnelSpawnPid = 424242
$script:SessionBgTunnel = [pscustomobject]@{ Id = 424242; HasExited = $false }

. ([scriptblock]::Create($ttu))

$script:BannerCallCount = 0
$script:GitModeLogLines.Clear()
$upFresh = Test-TunnelUp
Assert ($upFresh -eq $true) 'A-beh: fresh spawn-TTL returns $true'
Assert ($script:BannerCallCount -eq 0) `
    'A-beh: fresh spawn-TTL does NOT call Get-TunnelBanner (no SSH banner probe)'

# Negative behavioral: age >= 30s -> must probe (Get-TunnelBanner called).
$script:LastTunnelSpawnSuccessAt = (Get-Date).AddSeconds(-31)
$script:BannerCallCount = 0
$upAged = Test-TunnelUp
Assert ($script:BannerCallCount -ge 1) `
    'A-neg-beh: age>=30s still probes via Get-TunnelBanner'

# Negative behavioral: pid mismatch -> must probe.
$script:LastTunnelSpawnSuccessAt = Get-Date
$script:LastTunnelSpawnPid = 999001
$script:SessionBgTunnel = [pscustomobject]@{ Id = 424242; HasExited = $false }
$script:BannerCallCount = 0
$null = Test-TunnelUp
Assert ($script:BannerCallCount -ge 1) `
    'A-neg-beh: pid mismatch still probes via Get-TunnelBanner'

# =============================================================================
# B) Ensure-LaptopReverseSshCached / post-spawn (#3)
# =============================================================================
Write-Host '-- B) Ensure-LaptopReverseSshCached session-fresh (#3) --' -ForegroundColor White

# connect.ps1 Verifying laptop SSH path uses Ensure-LaptopReverseSshCached (already true).
Assert ($connect -match "(?ms)Step\s+'Verifying laptop SSH key'.*?Ensure-LaptopReverseSshCached") `
    'B-src: connect.ps1 Verifying laptop SSH uses Ensure-LaptopReverseSshCached'

# Fresh-spawn skip reason logged in ensure_cached.
Assert ($ensureCached -match 'reason=session_tunnel_fresh|reason=spawn_fresh') `
    'B-src: Ensure-LaptopReverseSshCached logs reason=session_tunnel_fresh or reason=spawn_fresh'

# HARD: must have a fresh-spawn skip branch (not only LaptopSshVerified=true skips).
$hasFreshSpawnBranch = ($ensureCached -match 'LastTunnelSpawnSuccessAt') -and (
    $ensureCached -match 'session_tunnel_fresh|spawn_fresh|TotalSeconds\s*-lt\s*30'
)
Assert ($hasFreshSpawnBranch) `
    'B-src HARD: ensure_cached has fresh-spawn skip branch (LastTunnelSpawnSuccess* + TTL), not solely LaptopSshVerified'

# Preferred OR acceptable product shape:
#  (preferred) ENSURE_TUNNEL ok sets LaptopSshVerified=$true after successful reverse probe, OR
#  (acceptable) ensure_cached skips when session spawn fresh + SessionBgTunnel (banner cache NOT required)
$ensureOkSetsVerified = $ensureTunnel -match '(?ms)ENSURE_TUNNEL ok=1.*?LaptopSshVerified\s*=\s*\$true' `
    -or $ensureTunnel -match '(?ms)LastTunnelSpawnSuccessAt\s*=\s*Get-Date.*?LaptopSshVerified\s*=\s*\$true'
$acceptableSkipShape = ($ensureCached -match 'LastTunnelSpawnSuccessAt') -and (
    $ensureCached -match 'TunnelBannerCacheUp|SessionBgTunnel'
)
Assert ($ensureOkSetsVerified -or $acceptableSkipShape) `
    'B-src: preferred (ENSURE ok sets LaptopSshVerified after reverse probe) OR acceptable (ensure_cached session-fresh + SessionBgTunnel)'

# Behavioral: LaptopSshVerified=false + fresh spawn + SessionBgTunnel alive -> skip reverse probe.
# TunnelBannerCacheUp=$false proves banner cache is NOT required for session_tunnel_fresh skip.
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
$script:GitModeLogLines.Clear()
$rcFresh = Ensure-LaptopReverseSshCached -PubB 'ssh-ed25519 AAAA'
Assert ($rcFresh -eq 0) 'B-beh: session-fresh ensure_cached returns 0 without reverse probe'
Assert (($script:ReverseProbeCount + $script:EnsureReverseCount) -eq 0) `
    'B-beh: session-fresh skip issues ZERO Test-LaptopReverseSsh / Ensure-LaptopReverseSsh calls'
$logFresh = ($script:GitModeLogLines -join "`n")
Assert ($logFresh -match 'reason=session_tunnel_fresh|reason=spawn_fresh') `
    'B-beh: session-fresh skip logs reason=session_tunnel_fresh or spawn_fresh'

# HARD negative: with LaptopSshVerified=false and NO fresh-spawn markers, must still probe
# (must not skip solely because verified=false forever / silent no-op).
$script:LastTunnelSpawnSuccessAt = $null
$script:LastTunnelSpawnPid = $null
$script:LaptopSshVerified = $false
$script:TunnelBannerCacheUp = $false
$script:ReverseProbeCount = 0
$script:EnsureReverseCount = 0
$script:GitModeLogLines.Clear()
$null = Ensure-LaptopReverseSshCached -PubB 'ssh-ed25519 AAAA'
Assert (($script:ReverseProbeCount + $script:EnsureReverseCount) -ge 1) `
    'B-neg-beh: without fresh-spawn markers, ensure_cached still probes (not forever-skip on verified=false)'

# =============================================================================
# C) GIT_MODE=off mount check TTL (#2)
# =============================================================================
Write-Host '-- C) GIT_MODE=off mount check TTL (#2) --' -ForegroundColor White

Assert ($connect -match '(?ms)\$gitModeOff\s*=\s*\(\(Get-GitMode\)\s*-eq\s*''off''\)') `
    'C-src: $gitModeOff derived from Get-GitMode -eq ''off'''

# Session-scoped cache vars
Assert ($connect -match 'LastMountCheckOkAt') `
    'C-src: connect.ps1 has $script:LastMountCheckOkAt (or equivalent) for mount-check TTL'
Assert ($connect -match 'LastMountCheckOkProject') `
    'C-src: connect.ps1 has $script:LastMountCheckOkProject for same-ProjectId skip'

Assert ($connect -match 'MOUNT_CHECK_SKIPPED reason=session_mount_ok') `
    'C-src: logs MOUNT_CHECK_SKIPPED reason=session_mount_ok (or session mount-ok skip)'

# Extract post-pick gitModeOff recover block
$gitOffBlock = [regex]::Match(
    $connect,
    '(?ms)\$gitModeOff\s*=\s*\$false.*?try\s*\{\s*\$gitModeOff\s*=\s*\(\(Get-GitMode\)\s*-eq\s*''off''\).*?if\s*\(\s*\$gitModeOff\s*\)\s*\{.*?^\s*\}'
).Value
if ($gitOffBlock.Length -lt 40) {
    $gitOffBlock = [regex]::Match(
        $connect,
        '(?ms)if\s*\(\s*\$gitModeOff\s*\)\s*\{\s*\$recoverCheckOk\s*=\s*Invoke-RecoverIfNeeded.*?^\s*\}'
    ).Value
}
Assert ($gitOffBlock.Length -gt 40) 'C-src: extracted if ($gitModeOff) { Invoke-RecoverIfNeeded ... } block'

# Skip path must consult LastMountCheck* before calling recover (or gate the call).
Assert ($gitOffBlock -match 'LastMountCheckOkAt|LastMountCheckOkProject|session_mount_ok') `
    'C-src: gitModeOff block consults LastMountCheck* / session_mount_ok before recover'

# Cold first pick: GIT_MODE=off check must NOT be removed entirely.
Assert ($gitOffBlock -match 'Invoke-RecoverIfNeeded') `
    'C-neg-src: cold first pick still has Invoke-RecoverIfNeeded inside gitModeOff (not removed)'

# Negative structural: different ProjectId OR TTL expired -> still calls check.
# Product must keep an Invoke-RecoverIfNeeded / Test-ProjectMountHealthy path when
# LastMountCheckOkProject differs or age exceeds TTL (e.g. 60s).
Assert (
    ($connect -match 'LastMountCheckOkProject') -and (
        $connect -match 'TotalSeconds\s*-lt\s*60' -or
        $connect -match 'TotalSeconds\s*-ge\s*60' -or
        $connect -match 'AddSeconds\(-60\)' -or
        $connect -match 'MountCheck.*60' -or
        $connect -match 'MOUNT_CHECK.*TTL|mount_check_ttl|LastMountCheckOkAt'
    )
) 'C-neg-src: TTL (~60s) + ProjectId gate present so different ProjectId / expiry still checks'

# Must not collapse to only BG skip (session_mount_ok is distinct from bg_up).
Assert ($connect -match 'MOUNT_CHECK_SKIPPED reason=bg_up') `
    'C-guard: BG up skip (reason=bg_up) still present - session_mount_ok is additive'
Assert (
    ($connect -match 'MOUNT_CHECK_SKIPPED reason=session_mount_ok') -and
    ($connect -match 'MOUNT_CHECK_SKIPPED reason=bg_up')
) 'C-src: both session_mount_ok and bg_up skip reasons exist (session TTL does not replace BG skip)'

Write-Host ''
Write-Host "Passed: $passed  Failed: $fail" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) {
    Write-Host "$fail test(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host 'All tests passed.' -ForegroundColor Green
exit 0
