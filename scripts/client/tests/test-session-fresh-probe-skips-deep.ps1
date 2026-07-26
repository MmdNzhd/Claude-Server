#Requires -Version 5.1
# Deep HARD contracts for session-fresh probe skips (spawn-TTL / reverse-SSH / mount check).
# Complements test-session-fresh-probe-skips.ps1 - do not weaken that suite.
# Product version: 20260725.40
# Plan: docs/superpowers/plans/2026-07-25-connect-speed-stability-logging.md

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
$passed = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green; $script:passed++ }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Session-fresh probe skips (DEEP) ===' -ForegroundColor Cyan
Write-Host ''

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$connect = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$ttu = Get-FunctionSource -Content $gm -Name 'Test-TunnelUp'
$ensureCached = Get-FunctionSource -Content $gm -Name 'Ensure-LaptopReverseSshCached'
$ensureTunnel = Get-FunctionSource -Content $gm -Name 'Ensure-SessionTunnel'
if ([string]::IsNullOrWhiteSpace($ensureTunnel)) {
    $ensureTunnel = Get-FunctionSource -Content $gm -Name 'Ensure-Tunnel'
}
$clearMount = Get-FunctionSource -Content $gm -Name 'Clear-SessionMount'

Assert (-not [string]::IsNullOrWhiteSpace($ttu)) 'extracted Test-TunnelUp'
Assert (-not [string]::IsNullOrWhiteSpace($ensureCached)) 'extracted Ensure-LaptopReverseSshCached'
Assert (-not [string]::IsNullOrWhiteSpace($ensureTunnel)) 'extracted Ensure-SessionTunnel (or Ensure-Tunnel)'
Assert (-not [string]::IsNullOrWhiteSpace($clearMount)) 'extracted Clear-SessionMount'

# =============================================================================
# A) Test-TunnelUp deep
# =============================================================================
Write-Host '-- A) Test-TunnelUp deep --' -ForegroundColor White

# Shared stubs for behavioral probes of extracted Test-TunnelUp
$script:BannerCallCount = 0
$script:GitModeLogLines = New-Object System.Collections.Generic.List[string]
function Write-GitModeLog {
    param([string]$Message, [string]$Level = 'INFO')
    $script:GitModeLogLines.Add("$Level|$Message")
}
function Get-TunnelBanner {
    param([int]$TargetPort = 0)
    $script:BannerCallCount++
    # Mirror product cache side-effect so A5 can exercise TunnelBannerCache 3s hit.
    $banner = 'SSH-2.0-OpenSSH_for_Windows'
    $script:TunnelBannerCacheAt = Get-Date
    $script:TunnelBannerCacheBanner = $banner
    $script:TunnelBannerCacheUp = $true
    return $banner
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

# A1: HasExited=$true -> MUST call Get-TunnelBanner even if age<30s and pid matches stamp
$script:LastTunnelSpawnSuccessAt = Get-Date
$script:LastTunnelSpawnSuccessPort = $Port
$script:LastTunnelSpawnPid = 424242
$script:SessionBgTunnel = [pscustomobject]@{ Id = 424242; HasExited = $true }
$script:TunnelBannerCacheInvalidate = $false
$script:TunnelBannerCacheAt = $null
$script:TunnelBannerCacheUp = $false
$script:BannerCallCount = 0
$null = Test-TunnelUp
Assert ($script:BannerCallCount -ge 1) `
    'A1-beh: HasExited=$true MUST call Get-TunnelBanner (even age<30s + pid match)'

# A2: Port mismatch -> MUST probe
$script:LastTunnelSpawnSuccessAt = Get-Date
$script:LastTunnelSpawnSuccessPort = ($Port + 1)
$script:LastTunnelSpawnPid = 424242
$script:SessionBgTunnel = [pscustomobject]@{ Id = 424242; HasExited = $false }
$script:TunnelBannerCacheAt = $null
$script:TunnelBannerCacheUp = $false
$script:BannerCallCount = 0
$null = Test-TunnelUp
Assert ($script:BannerCallCount -ge 1) `
    'A2-beh: LastTunnelSpawnSuccessPort != Port MUST probe Get-TunnelBanner'

# A3: SessionBgTunnel=$null -> MUST probe
$script:LastTunnelSpawnSuccessAt = Get-Date
$script:LastTunnelSpawnSuccessPort = $Port
$script:LastTunnelSpawnPid = 424242
$script:SessionBgTunnel = $null
$script:TunnelBannerCacheAt = $null
$script:TunnelBannerCacheUp = $false
$script:BannerCallCount = 0
$null = Test-TunnelUp
Assert ($script:BannerCallCount -ge 1) `
    'A3-beh: SessionBgTunnel=$null MUST probe Get-TunnelBanner'

# A4: Fresh skip must NOT pollute TunnelBannerCacheUp (prefer no cache side effect)
$script:LastTunnelSpawnSuccessAt = Get-Date
$script:LastTunnelSpawnSuccessPort = $Port
$script:LastTunnelSpawnPid = 424242
$script:SessionBgTunnel = [pscustomobject]@{ Id = 424242; HasExited = $false }
$script:TunnelBannerCacheInvalidate = $false
$script:TunnelBannerCacheAt = $null
$script:TunnelBannerCacheUp = $false
$script:TunnelBannerCacheBanner = ''
$script:BannerCallCount = 0
$upFreshDeep = Test-TunnelUp
Assert ($upFreshDeep -eq $true) 'A4-beh: fresh spawn-TTL returns $true'
Assert ($script:BannerCallCount -eq 0) 'A4-beh: fresh spawn-TTL does not call Get-TunnelBanner'
Assert ($script:TunnelBannerCacheUp -eq $false) `
    'A4-beh: fresh skip does NOT set TunnelBannerCacheUp (no cache pollution)'
Assert ($null -eq $script:TunnelBannerCacheAt) `
    'A4-beh: fresh skip leaves TunnelBannerCacheAt unset'

# A5: After aged-out probe succeeds, subsequent call within 3s may use TunnelBannerCache;
#     spawn-TTL remains an independent source branch (not only banner-cache).
$script:LastTunnelSpawnSuccessAt = (Get-Date).AddSeconds(-31)
$script:LastTunnelSpawnSuccessPort = $Port
$script:LastTunnelSpawnPid = 424242
$script:SessionBgTunnel = [pscustomobject]@{ Id = 424242; HasExited = $false }
$script:TunnelBannerCacheInvalidate = $false
$script:TunnelBannerCacheAt = $null
$script:TunnelBannerCacheUp = $false
$script:BannerCallCount = 0
$upAged1 = Test-TunnelUp
Assert ($upAged1 -eq $true) 'A5-beh: aged-out first call probes and returns $true'
Assert ($script:BannerCallCount -eq 1) 'A5-beh: aged-out first call hits Get-TunnelBanner once'
Assert ($script:TunnelBannerCacheUp -eq $true) 'A5-beh: successful probe may populate TunnelBannerCacheUp'

$script:BannerCallCount = 0
$upAged2 = Test-TunnelUp
Assert ($upAged2 -eq $true) 'A5-beh: second call within 3s still returns $true'
Assert ($script:BannerCallCount -eq 0) `
    'A5-beh: second call within 3s uses TunnelBannerCache (zero Get-TunnelBanner)'
Assert ($ttu -match 'LastTunnelSpawnSuccessAt') `
    'A5-src: spawn-TTL branch (LastTunnelSpawnSuccessAt) remains independent of TunnelBannerCache'
Assert ($ttu -match 'TunnelBannerCache') `
    'A5-src: TunnelBannerCache 3s path still present alongside spawn-TTL'

# =============================================================================
# B) Ensure-LaptopReverseSshCached deep
# =============================================================================
Write-Host '-- B) Ensure-LaptopReverseSshCached deep --' -ForegroundColor White

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

$Port = 21004
$script:LaptopSshVerified = $false
$script:LastTunnelSpawnSuccessAt = Get-Date
$script:LastTunnelSpawnSuccessPort = $Port
$script:LastTunnelSpawnPid = 424242
$script:SessionBgTunnel = [pscustomobject]@{ Id = 424242; HasExited = $false }
$script:TunnelBannerCacheUp = $false

. ([scriptblock]::Create($ensureCached))

# B1: Fresh spawn + TunnelBannerCacheUp=$false -> MUST skip (banner not required)
$script:LaptopSshVerified = $false
$script:LastTunnelSpawnSuccessAt = Get-Date
$script:LastTunnelSpawnSuccessPort = $Port
$script:LastTunnelSpawnPid = 424242
$script:SessionBgTunnel = [pscustomobject]@{ Id = 424242; HasExited = $false }
$script:TunnelBannerCacheUp = $false
$script:ReverseProbeCount = 0
$script:EnsureReverseCount = 0
$script:GitModeLogLines.Clear()
$rcB1 = Ensure-LaptopReverseSshCached -PubB 'ssh-ed25519 AAAA'
Assert ($rcB1 -eq 0) 'B1-beh: fresh spawn + TunnelBannerCacheUp=$false returns rc=0'
Assert (($script:ReverseProbeCount + $script:EnsureReverseCount) -eq 0) `
    'B1-beh: fresh spawn + TunnelBannerCacheUp=$false issues ZERO reverse probe calls'
$logB1 = ($script:GitModeLogLines -join "`n")
Assert ($logB1 -match 'reason=session_tunnel_fresh') `
    'B1-beh: fresh spawn + banner=false skip logs reason=session_tunnel_fresh'

# B2: Fresh spawn + banner up + age=29s -> skip (rc=0, zero reverse calls)
$script:LaptopSshVerified = $false
$script:LastTunnelSpawnSuccessAt = (Get-Date).AddSeconds(-29)
$script:LastTunnelSpawnSuccessPort = $Port
$script:LastTunnelSpawnPid = 424242
$script:SessionBgTunnel = [pscustomobject]@{ Id = 424242; HasExited = $false }
$script:TunnelBannerCacheUp = $true
$script:ReverseProbeCount = 0
$script:EnsureReverseCount = 0
$script:GitModeLogLines.Clear()
$rc29 = Ensure-LaptopReverseSshCached -PubB 'ssh-ed25519 AAAA'
Assert ($rc29 -eq 0) 'B2-beh: age=29s + banner up returns rc=0'
Assert (($script:ReverseProbeCount + $script:EnsureReverseCount) -eq 0) `
    'B2-beh: age=29s + banner up issues ZERO reverse probe calls'
$log29 = ($script:GitModeLogLines -join "`n")
Assert ($log29 -match 'reason=session_tunnel_fresh|reason=spawn_fresh') `
    'B2-beh: age=29s skip logs reason=session_tunnel_fresh'

# B3: Fresh spawn + banner up + age=31s -> MUST probe
$script:LaptopSshVerified = $false
$script:LastTunnelSpawnSuccessAt = (Get-Date).AddSeconds(-31)
$script:LastTunnelSpawnSuccessPort = $Port
$script:LastTunnelSpawnPid = 424242
$script:SessionBgTunnel = [pscustomobject]@{ Id = 424242; HasExited = $false }
$script:TunnelBannerCacheUp = $true
$script:ReverseProbeCount = 0
$script:EnsureReverseCount = 0
$script:GitModeLogLines.Clear()
$null = Ensure-LaptopReverseSshCached -PubB 'ssh-ed25519 AAAA'
Assert (($script:ReverseProbeCount + $script:EnsureReverseCount) -ge 1) `
    'B3-beh: age=31s + banner up MUST probe (TTL expired)'

# B4: LaptopSshVerified=$true + Test-TunnelUp stub true -> verified_tunnel_up path
$script:LaptopSshVerified = $true
$script:LastTunnelSpawnSuccessAt = $null
$script:TunnelBannerCacheUp = $false
$script:ReverseProbeCount = 0
$script:EnsureReverseCount = 0
$script:GitModeLogLines.Clear()
$rcVerified = Ensure-LaptopReverseSshCached -PubB 'ssh-ed25519 AAAA'
Assert ($rcVerified -eq 0) 'B4-beh: verified_tunnel_up returns rc=0'
Assert (($script:ReverseProbeCount + $script:EnsureReverseCount) -eq 0) `
    'B4-beh: verified_tunnel_up issues ZERO reverse probe calls'
$logVerified = ($script:GitModeLogLines -join "`n")
Assert ($logVerified -match 'reason=verified_tunnel_up') `
    'B4-beh: verified path logs reason=verified_tunnel_up'

# B5: After session_tunnel_fresh skip, LaptopSshVerified becomes $true
$script:LaptopSshVerified = $false
$script:LastTunnelSpawnSuccessAt = Get-Date
$script:LastTunnelSpawnSuccessPort = $Port
$script:LastTunnelSpawnPid = 424242
$script:SessionBgTunnel = [pscustomobject]@{ Id = 424242; HasExited = $false }
$script:TunnelBannerCacheUp = $true
$script:ReverseProbeCount = 0
$script:EnsureReverseCount = 0
$script:GitModeLogLines.Clear()
$rcFreshB5 = Ensure-LaptopReverseSshCached -PubB 'ssh-ed25519 AAAA'
Assert ($rcFreshB5 -eq 0) 'B5-beh: session_tunnel_fresh returns rc=0'
Assert ($script:LaptopSshVerified -eq $true) `
    'B5-beh: after session_tunnel_fresh skip, LaptopSshVerified becomes $true (script scope)'
Assert ($ensureCached -match 'LaptopSshVerified\s*=\s*\$true') `
    'B5-src: Ensure-LaptopReverseSshCached assigns LaptopSshVerified=$true on fresh skip'

# =============================================================================
# C) Mount check TTL deep
# =============================================================================
Write-Host '-- C) Mount check TTL deep --' -ForegroundColor White

# C1: Clear-SessionMount MUST null LastMountCheckOkAt AND LastMountCheckOkProject
Assert ($clearMount -match 'LastMountCheckOkAt\s*=\s*\$null') `
    'C1-src: Clear-SessionMount nulls LastMountCheckOkAt'
Assert ($clearMount -match 'LastMountCheckOkProject\s*=\s*\$null') `
    'C1-src: Clear-SessionMount nulls LastMountCheckOkProject'

# C2: recoverCheckOk=$false MUST clear LastMountCheckOk* (not leave stale ok stamp)
# Brace-match the full if ($gitModeOff) { ... } so we do not truncate at the first nested }.
$gitOffBlock = ''
$gmOffAnchor = [regex]::Match(
    $connect,
    '(?ms)try\s*\{\s*\$gitModeOff\s*=\s*\(\(Get-GitMode\)\s*-eq\s*''off''\).*?if\s*\(\s*\$gitModeOff\s*\)\s*\{'
)
if ($gmOffAnchor.Success) {
    $braceStart = $connect.IndexOf('{', $gmOffAnchor.Index + $gmOffAnchor.Length - 1)
    if ($braceStart -ge 0) {
        $depth = 0
        for ($j = $braceStart; $j -lt $connect.Length; $j++) {
            if ($connect[$j] -eq '{') { $depth++ }
            elseif ($connect[$j] -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $gitOffBlock = $connect.Substring($gmOffAnchor.Index, $j - $gmOffAnchor.Index + 1)
                    break
                }
            }
        }
    }
}
Assert ($gitOffBlock.Length -gt 80) 'C2-src: extracted gitModeOff mount-check block'
Assert (
    $gitOffBlock -match '(?ms)if\s*\(\s*\$recoverCheckOk\s*\)\s*\{.*?LastMountCheckOkAt\s*=\s*Get-Date.*?\}.*?else\s*\{.*?LastMountCheckOkAt\s*=\s*\$null.*?LastMountCheckOkProject\s*=\s*\$null'
) 'C2-src: recoverCheckOk=$false clears LastMountCheckOkAt and LastMountCheckOkProject'

# C3: session_mount_ok sets recoverCheckOk=$true WITHOUT calling Invoke-RecoverIfNeeded
#     (gated by mountCheckSessionOk / -not $mountCheckSessionOk)
Assert ($gitOffBlock -match 'mountCheckSessionOk') `
    'C3-src: gitModeOff block uses mountCheckSessionOk gate'
Assert ($gitOffBlock -match '(?ms)\$mountCheckSessionOk\s*=\s*\$true.*?\$recoverCheckOk\s*=\s*\$true') `
    'C3-src: session_mount_ok path sets recoverCheckOk=$true'
Assert ($gitOffBlock -match 'if\s*\(\s*-not\s*\$mountCheckSessionOk\s*\)') `
    'C3-src: Invoke-RecoverIfNeeded gated by -not $mountCheckSessionOk'
$recoverOnlyWhenNotOk = [regex]::Match(
    $gitOffBlock,
    '(?ms)if\s*\(\s*-not\s*\$mountCheckSessionOk\s*\)\s*\{.*?Invoke-RecoverIfNeeded'
)
Assert ($recoverOnlyWhenNotOk.Success) `
    'C3-src: Invoke-RecoverIfNeeded only inside -not $mountCheckSessionOk branch'

# C4: Different ProjectId: comparison uses go.Id vs LastMountCheckOkProject
Assert ($gitOffBlock -match 'LastMountCheckOkProject.*-eq.*\$go\.Id|\$go\.Id.*-eq.*LastMountCheckOkProject') `
    'C4-src: ProjectId gate compares LastMountCheckOkProject to $go.Id'
Assert ($connect -match '\[string\]\$script:LastMountCheckOkProject\s*-eq\s*\[string\]\$go\.Id') `
    'C4-src HARD: comparison is [string]$script:LastMountCheckOkProject -eq [string]$go.Id'

# C5: TTL constant is 60 (TotalSeconds -lt 60)
Assert ($gitOffBlock -match 'TotalSeconds\s*-lt\s*60') `
    'C5-src: mount-check TTL is TotalSeconds -lt 60'

# =============================================================================
# D) Interaction / safety
# =============================================================================
Write-Host '-- D) Interaction / safety --' -ForegroundColor White

# D1: Ensure-SessionTunnel sets LastTunnelSpawnSuccess* AFTER Wait-ForTunnelUp success
$waitIdx = $ensureTunnel.IndexOf('Wait-ForTunnelUp')
$spawnAtIdx = $ensureTunnel.IndexOf('LastTunnelSpawnSuccessAt = Get-Date')
if ($spawnAtIdx -lt 0) {
    $spawnAtIdx = $ensureTunnel.IndexOf('LastTunnelSpawnSuccessAt=')
}
Assert ($waitIdx -ge 0) 'D1-src: Ensure ok path mentions Wait-ForTunnelUp'
Assert ($spawnAtIdx -ge 0) 'D1-src: Ensure ok path assigns LastTunnelSpawnSuccessAt'
Assert (($waitIdx -ge 0) -and ($spawnAtIdx -ge 0) -and ($waitIdx -lt $spawnAtIdx)) `
    'D1-src: Wait-ForTunnelUp appears BEFORE LastTunnelSpawnSuccessAt= assignment in ENSURE ok path'

# D2: connect.ps1 still has MOUNT_CHECK_SKIPPED reason=bg_up
Assert ($connect -match 'MOUNT_CHECK_SKIPPED reason=bg_up') `
    'D2-src: connect.ps1 still has MOUNT_CHECK_SKIPPED reason=bg_up'

# D3: No Persian / emoji / non-ASCII punctuation in this test file (ASCII only).
# Use printable-ASCII allowlist - do NOT use broken \u1F300 5-hex ranges (match digits).
$selfRaw = Get-Content $PSCommandPath -Raw -ErrorAction SilentlyContinue
if (-not $selfRaw) { $selfRaw = Get-Content (Join-Path $PSScriptRoot 'test-session-fresh-probe-skips-deep.ps1') -Raw }
$hasPersian = $selfRaw -match '[\u0600-\u06FF]'
$hasNonAscii = $selfRaw -match '[^\x09\x0A\x0D\x20-\x7E]'
$hasCurlyOrEmDash = $selfRaw -match '[\u2013\u2014\u2018\u2019\u201C\u201D]'
Assert (-not $hasPersian) 'D3: new test file has no Persian characters'
Assert (-not $hasNonAscii) 'D3: new test file is ASCII only (no emoji / non-ASCII)'
Assert (-not $hasCurlyOrEmDash) 'D3: new test file has no em-dash / curly quotes (ASCII only)'

Write-Host ''
Write-Host "Passed: $passed  Failed: $fail" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) {
    Write-Host "$fail test(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host 'All tests passed.' -ForegroundColor Green
exit 0
