# test-xray-probe-cache.ps1 - xray SOCKS probe caching + reseed short-circuit
# Callers: scripts/client/tests/run-all.ps1
# The remote xray probe opens a fresh one-shot ssh (no ControlMaster on Windows) and can burn the
# full ~7s ConnectTimeout budget. It runs at least twice per connect and every connect.bat is a
# fresh process, so we (a) cache the verdict in-memory + on disk (survives across processes, TTL
# bounded) and (b) short-circuit Test-TunnelNeedsProxyReseed on the cheap local leg-state check
# before ever probing. This guards both behaviors.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Xray probe cache ===' -ForegroundColor Cyan
Write-Host ''

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw

# --- Source-level guards -------------------------------------------------------------------
Assert ($gm -match 'function Get-XrayProbeCachePath')     'Get-XrayProbeCachePath defined'
Assert ($gm -match 'function Import-XrayProbeDiskCache')  'Import-XrayProbeDiskCache defined'
Assert ($gm -match 'function Save-XrayProbeDiskCache')    'Save-XrayProbeDiskCache defined'
Assert ($gm -match '\$script:XrayProbeCache')             'in-memory xray cache present'

$fnProbe = Get-FunctionSource -Content $gm -Name 'Test-RemoteXraySocksOpen'
Assert ($fnProbe -match 'Import-XrayProbeDiskCache') 'probe hydrates disk cache before checking'
Assert ($fnProbe -match 'remote_xray_probe=cache_hit') 'probe short-circuits on cache hit'
Assert ($fnProbe -match 'Save-XrayProbeDiskCache') 'probe persists verdict to disk'

# Reseed must consult the cheap local leg-state BEFORE the expensive remote probe.
$fnReseed = Get-FunctionSource -Content $gm -Name 'Test-TunnelNeedsProxyReseed'
$legIdx   = $fnReseed.IndexOf('Get-TunnelProxyLegState')
$probeIdx = $fnReseed.IndexOf('Test-RemoteXraySocksOpen')
Assert ($legIdx -ge 0 -and $probeIdx -ge 0 -and $legIdx -lt $probeIdx) 'reseed checks leg-state before probing xray'

# --- Functional disk-cache round-trip using the REAL extracted functions --------------------
function Write-GitModeLog { param($m, $lvl) }  # no-op stub for isolation
. ([ScriptBlock]::Create((Get-FunctionSource -Content $gm -Name 'Get-XrayProbeCachePath')))
. ([ScriptBlock]::Create((Get-FunctionSource -Content $gm -Name 'Import-XrayProbeDiskCache')))
. ([ScriptBlock]::Create((Get-FunctionSource -Content $gm -Name 'Save-XrayProbeDiskCache')))

$tmpDir = Join-Path $env:TEMP ("xray-cache-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$script:CfgDir = $tmpDir
$script:XrayProbeCacheTtlSec = 1800
try {
    # Populate + save, then simulate a fresh process (clear memory + loaded flag) and re-import.
    $script:XrayProbeCache = @{}
    $script:XrayProbeDiskLoaded = $false
    $script:XrayProbeCache['claude-server:10808'] = @{ Result = $false; Time = (Get-Date) }
    Save-XrayProbeDiskCache
    Assert (Test-Path -LiteralPath (Get-XrayProbeCachePath)) 'disk cache file written'

    $script:XrayProbeCache = @{}
    $script:XrayProbeDiskLoaded = $false
    Import-XrayProbeDiskCache
    Assert ($script:XrayProbeCache.ContainsKey('claude-server:10808')) 'verdict restored across process'
    Assert ($script:XrayProbeCache['claude-server:10808'].Result -eq $false) 'restored verdict value correct'

    # Expired entries must be dropped on import.
    $script:XrayProbeCache = @{}
    $script:XrayProbeDiskLoaded = $false
    $script:XrayProbeCache['stale:10808'] = @{ Result = $false; Time = ((Get-Date).AddSeconds(-99999)) }
    Save-XrayProbeDiskCache
    $script:XrayProbeCache = @{}
    $script:XrayProbeDiskLoaded = $false
    Import-XrayProbeDiskCache
    Assert (-not $script:XrayProbeCache.ContainsKey('stale:10808')) 'expired disk entry dropped on import'
} finally {
    Remove-Item -Recurse -Force -LiteralPath $tmpDir -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
