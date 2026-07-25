# test-xray-http-leg-resilience.ps1 - HTTP proxy leg reliably rides through xray
# Callers: scripts/client/tests/run-all.ps1
#
# Guards the 2026-07-25 "all Cursor traffic went server_direct instead of xray" incident. Root
# cause chain (all in git-mode.ps1):
#   1. Test-RemoteXraySocksOpen probed xray HTTP (10809) once; a Win32-OpenSSH ConnectTimeout can
#      spuriously burn the full budget even against a LIVE target, so the probe returned $false and
#      that INCONCLUSIVE verdict was cached as a definitive "closed" for the whole TTL.
#   2. Add-TunnelHttpProxyLeg saw "closed" and skipped the HTTP -L leg (19180) - the SOCKS leg
#      (19080) on the same transport still came up, so the tunnel was 'missing_http'.
#   3. Test-CursorProxyBackendOpen needs BOTH 19080+19180 -> reports backend_down -> the sidecar
#      CLEARS Cursor's proxy settings -> Cursor egresses server_direct (bypassing xray).
#   4. Test-TunnelNeedsProxyReseed refused to self-heal 'missing_http' because a still-listening
#      sidecar FRONT (18998/18999) - whose HTTP backend was dead - was a false "adopted elsewhere".
#
# Fixes asserted here:
#   A. Test-RemoteXraySocksOpen only caches CONCLUSIVE OPEN/CLOSED (never a timeout/error) + gains
#      a -ForceProbe switch to bypass the cache on retry.
#   B. Add-TunnelHttpProxyLeg retries the HTTP probe once with -ForceProbe before giving up.
#   C. Test-TunnelNeedsProxyReseed treats 'missing_http' differently from a full non-owner
#      ('missing'): a sticky FRONT alone must NOT suppress the reseed - only a genuinely-listening
#      HTTP backend may. This test drives the REAL extracted function to prove the decision.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Xray HTTP leg resilience ===' -ForegroundColor Cyan
Write-Host ''

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw

# --- A. probe: -ForceProbe + do not cache inconclusive -------------------------------------
$fnProbe = Get-FunctionSource -Content $gm -Name 'Test-RemoteXraySocksOpen'
Assert ($fnProbe -match '\[switch\]\$ForceProbe')                 'probe accepts -ForceProbe'
Assert ($fnProbe -match '-not\s+\$ForceProbe\s+-and')            'ForceProbe bypasses the cache lookup'
Assert ($fnProbe -match '\$conclusive\s*=\s*\$true')             'probe tracks a conclusive flag'
Assert ($fnProbe -match 'timeout[\s\S]*\$conclusive\s*=\s*\$false') 'timeout marks verdict inconclusive'
Assert ($fnProbe -match 'if\s*\(\$conclusive\s+-and\s+\$script:XrayProbeCache') 'only CONCLUSIVE verdicts are cached'

# --- B. Add-TunnelHttpProxyLeg retries once with -ForceProbe -------------------------------
$fnHttp = Get-FunctionSource -Content $gm -Name 'Add-TunnelHttpProxyLeg'
Assert ($fnHttp) 'extracted Add-TunnelHttpProxyLeg body'
$forceIdx = $fnHttp.IndexOf('-ForceProbe')
$skipIdx  = $fnHttp.IndexOf('skipping_http_proxy_leg')
Assert ($forceIdx -ge 0)                       'HTTP leg re-probes with -ForceProbe'
Assert ($forceIdx -ge 0 -and $skipIdx -ge 0 -and $forceIdx -lt $skipIdx) 'retry happens BEFORE giving up on the HTTP leg'
Assert ($fnHttp -match 'open_on_retry')        'logs a recovered-on-retry outcome'

# --- C. reseed self-heals missing_http (functional, real extracted body) -------------------
$fnReseed = Get-FunctionSource -Content $gm -Name 'Test-TunnelNeedsProxyReseed'
Assert ($fnReseed) 'extracted Test-TunnelNeedsProxyReseed body'
Assert ($fnReseed -match '-not\s+\$backendsOk\s+-and\s+\$state\s+-eq\s+''missing''') 'front-adoption is gated to full non-owner (missing) only'

# Shared stubs: xray is UP; ports/logging are deterministic; the HTTP *backend* (19180) is DOWN
# while the sidecar FRONT (18998/18999) is UP - the exact false-positive shape from the incident.
function Write-GitModeLog { param($m, $lvl) }
function Get-SocksProxyPort { 19080 }
function Get-HttpProxyPort  { 19180 }
function Get-CursorSocksFrontPort { 18998 }
function Get-CursorHttpFrontPort  { 18999 }
function Test-RemoteXraySocksOpen { param([string]$Alias, [string]$SshCfgPath = '', [int]$RemotePort = 0, [switch]$ForceProbe) return $true } # xray up
function Test-CursorProxySidecarListening { param([int]$Port) return $true } # fronts UP
$script:XrayServerSocksPort = 10808
$script:XrayServerHttpPort  = 10809
$script:SocksProxyPort = 0
$script:HttpProxyPort  = 0

. ([ScriptBlock]::Create($fnReseed))

# Case 1: missing_http, http backend 19180 DOWN, fronts UP -> MUST reseed (self-heal).
function Get-TunnelProxyLegState { param([int]$TunnelPid) return 'missing_http' }
function Test-LocalPortOpen { param([int]$PortNum) return ($PortNum -eq 19080) } # socks backend up, http backend down
$r1 = Test-TunnelNeedsProxyReseed -TunnelPid 4242 -Alias 'claude-server'
Assert ($r1 -eq $true) 'missing_http with dead HTTP backend + live front => reseed_needed (self-heal, not false-adopt)'

# Case 2: full non-owner (missing), both backends DOWN but fronts UP -> adopt, skip reseed.
function Get-TunnelProxyLegState { param([int]$TunnelPid) return 'missing' }
function Test-LocalPortOpen { param([int]$PortNum) return $false } # no backends locally
$r2 = Test-TunnelNeedsProxyReseed -TunnelPid 4243 -Alias 'claude-server'
Assert ($r2 -eq $false) 'missing (non-owner) with live sidecar fronts => adopt, skip reseed'

# Case 3: missing_http but http backend 19180 genuinely UP -> real adoption, skip reseed.
function Get-TunnelProxyLegState { param([int]$TunnelPid) return 'missing_http' }
function Test-LocalPortOpen { param([int]$PortNum) return $true } # both backends up
$r3 = Test-TunnelNeedsProxyReseed -TunnelPid 4244 -Alias 'claude-server'
Assert ($r3 -eq $false) 'missing_http with LIVE http backend => genuine adoption, skip reseed'

# Case 4: 'ok' short-circuits before any xray probe.
function Get-TunnelProxyLegState { param([int]$TunnelPid) return 'ok' }
$r4 = Test-TunnelNeedsProxyReseed -TunnelPid 4245 -Alias 'claude-server'
Assert ($r4 -eq $false) 'ok state => no reseed'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
