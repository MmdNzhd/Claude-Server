# test-known-down-selfheal-live.ps1 - LIVE: Bug 7 fix verification. Pre-fix, Test-CursorProxyBackendOpen
# (scripts/client/windows/cursor-proxy-sidecar.ps1) short-circuited to $false on Test-CursorProxyKnownDown
# for the FULL 120s TTL and never re-probed the real backend ports, even when both real backend
# listeners were genuinely UP - Clear-CursorProxyKnownDownCache was reachable ONLY from the
# real-probe branch, dead code while the cache was hot, so a backend that recovered mid-TTL stayed
# reported "down" for up to 120s. Post-fix, Test-CursorProxyBackendOpen always performs the real
# (cheap, bounded) port checks regardless of cache state, so recovery is caught immediately -
# this test now asserts that fixed/GREEN behavior against real listeners.
#
# This test dot-sources the REAL current source of the 5 functions under test (via
# Get-FunctionSource brace extraction, same idiom as sibling *-live.ps1 tests) and drives them
# against two REAL loopback TcpListeners, never against a re-implementation.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Known-down cache self-heal - Bug 7 fix (LIVE) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'windows\cursor-proxy-sidecar.ps1') -Raw

$fnNames = @(
    'Test-CursorProxyKnownDown',
    'Set-CursorProxyKnownDown',
    'Clear-CursorProxyKnownDownCache',
    'Test-CursorProxySidecarListening',
    'Test-CursorProxyBackendOpen'
)
foreach ($n in $fnNames) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
    Write-Host "  (extracted real source of ${n}: $($src.Length) chars)" -ForegroundColor DarkGray
}

# Isolate this run from the real shared %TEMP%\claude-connect-proxy-known-down.json - point the
# cache file the extracted functions reference at a run-unique TEMP path instead.
$script:CursorProxyKnownDownCacheFile = Join-Path $env:TEMP ("claude-connect-proxy-known-down-test-{0}.json" -f ([guid]::NewGuid().ToString('N')))
$script:CursorProxyKnownDownTtlSec = 120

if (Test-Path -LiteralPath $script:CursorProxyKnownDownCacheFile) {
    Remove-Item -LiteralPath $script:CursorProxyKnownDownCacheFile -Force -ErrorAction SilentlyContinue
}

# Never reuse real production ports (18998/18999 sidecar front, 19080/19180 backends, 20022 SSH
# tunnel) - pick two distinct random ephemeral ports for the two real backend listeners.
$excludedPorts = @(18998, 18999, 19080, 19180, 20022)
function New-RandomEphemeralPort([int[]]$Avoid) {
    $p = 0
    do {
        $p = Get-Random -Minimum 49152 -Maximum 65535
    } while (($Avoid + $excludedPorts) -contains $p)
    return $p
}
$httpPort = New-RandomEphemeralPort -Avoid @()
$socksPort = New-RandomEphemeralPort -Avoid @($httpPort)
Write-Host "  using random ephemeral backend ports: http=$httpPort socks=$socksPort" -ForegroundColor DarkGray

$script:HttpProxyPort = $httpPort
$script:SocksProxyPort = $socksPort

$httpListener = $null
$socksListener = $null

try {
    # --- Scenario A: cache hot, both real backends genuinely UP right now ---------------------
    $httpListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $httpPort)
    $httpListener.Start()
    $socksListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $socksPort)
    $socksListener.Start()

    Assert (Test-CursorProxySidecarListening -Port $httpPort) "sanity: http backend port $httpPort really listening before any known-down seeding"
    Assert (Test-CursorProxySidecarListening -Port $socksPort) "sanity: socks backend port $socksPort really listening before any known-down seeding"

    Set-CursorProxyKnownDown -Reason 'test_forced_down'
    Assert (Test-Path -LiteralPath $script:CursorProxyKnownDownCacheFile) 'known-down cache file was written by Set-CursorProxyKnownDown'
    Assert (Test-CursorProxyKnownDown) 'cache is hot immediately after Set-CursorProxyKnownDown (simulates a real prior down-detection)'

    $backendOpenResult = Test-CursorProxyBackendOpen
    Assert ($backendOpenResult -eq $true) "BUG 7 FIXED (GREEN): Test-CursorProxyBackendOpen returns `$true` even while the known-down cache is hot, because both real backend listeners are genuinely up right now and the fix always performs the real check"

    # Prove the contradiction that USED to exist is now resolved: real per-port probe says both
    # up, and the composite check agrees immediately - no more blind trust in a stale cache.
    $httpReallyUp = Test-CursorProxySidecarListening -Port $httpPort
    $socksReallyUp = Test-CursorProxySidecarListening -Port $socksPort
    Assert $httpReallyUp "contradiction check: Test-CursorProxySidecarListening -Port $httpPort (real backend) reports TRUE (backend genuinely up)"
    Assert $socksReallyUp "contradiction check: Test-CursorProxySidecarListening -Port $socksPort (real backend) reports TRUE (backend genuinely up)"

    if ($httpReallyUp -and $socksReallyUp -and ($backendOpenResult -eq $true)) {
        Write-Host '  ==> FIX CONFIRMED: real backend is up on both ports, and Test-CursorProxyBackendOpen agrees immediately despite a hot known-down cache - the short-circuit is gone.' -ForegroundColor Yellow
    }

    # Clear-CursorProxyKnownDownCache is now reachable on every successful real probe - the cache
    # file must be gone after this call succeeded (the real-probe/clear branch ran).
    $stillOpenAfterRerun = Test-CursorProxyBackendOpen
    Assert ($stillOpenAfterRerun -eq $true) 'repeated call: Test-CursorProxyBackendOpen still returns $true on a second call (real check every time, not a one-off)'
    Assert (-not (Test-Path -LiteralPath $script:CursorProxyKnownDownCacheFile)) 'known-down cache file WAS cleared once a real probe succeeded (Clear-CursorProxyKnownDownCache is reachable again)'

    # --- Bonus scenario B: with a short TTL, self-heal now happens IMMEDIATELY, not just on
    # blind TTL expiry - proving the fix removed the TTL-gated blind-wait entirely. ---------------
    Write-Host ''
    Write-Host '  --- bonus: shrink TTL, prove self-heal is now IMMEDIATE (real check every call), not blind-expiry-only ---' -ForegroundColor Cyan
    Remove-Item -LiteralPath $script:CursorProxyKnownDownCacheFile -Force -ErrorAction SilentlyContinue
    $script:CursorProxyKnownDownTtlSec = 3
    Set-CursorProxyKnownDown -Reason 'test_forced_down_short_ttl'
    $immediateResult = Test-CursorProxyBackendOpen
    Assert ($immediateResult -eq $true) "with short TTL=3s: immediately after seeding (no wait at all), Test-CursorProxyBackendOpen already returns `$true because both real backends are up and the fix never trusts the cache for correctness"

    Write-Host '  ==> Self-heal is now immediate on every call via a real cheap check - the known-down cache no longer gates correctness, only observability. That closes Bug 7.' -ForegroundColor Yellow
} finally {
    if ($httpListener) { try { $httpListener.Stop() } catch {} }
    if ($socksListener) { try { $socksListener.Stop() } catch {} }
    if (Test-Path -LiteralPath $script:CursorProxyKnownDownCacheFile) {
        try { Remove-Item -LiteralPath $script:CursorProxyKnownDownCacheFile -Force -ErrorAction SilentlyContinue } catch {}
    }
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
