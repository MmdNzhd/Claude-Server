#Requires -Version 5.1
# test-tunnel-proxy-skip-hard.ps1 - HARD contracts for xray_closed Preparing-tunnel thrash
# (live a8a37c2a418d 2026-07-28: Preparing tunnel 15022ms + second Ensure after auth).
# Locks:
#   1) Complete-CursorProxyAfterTunnel skips when SessionTunnelProxyLegs=$false
#   2) Skip does not call Ensure-CursorProxySidecar
#   3) Get-SocksProxyPort defaults alone must NOT defeat skip
#   4) connect.ps1 post-auth Ensure is gated the same way
#   5) ENSURE_TUNNEL xray_closed clears session leg vars
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== tunnel proxy skip hard (xray_closed thrash) ===' -ForegroundColor Cyan
Write-Host ''

$gmPath = Get-ClientFile 'git-mode.ps1'
$winPath = Get-ClientFile 'windows\connect.ps1'
$gmSrc = Get-Content -LiteralPath $gmPath -Raw
$winSrc = Get-Content -LiteralPath $winPath -Raw

# --- Static ---
Assert (
    ($gmSrc -match 'SessionTunnelProxyLegs\s*=\s*\$false') -and
    ($gmSrc -match 'skip_sidecar reason=no_tunnel_proxy_legs')
) 'git-mode clears SessionTunnelProxyLegs on xray_closed and logs skip_sidecar'

Assert (
    ($winSrc -match 'SIDECAR_ENSURE skip reason=no_tunnel_proxy_legs') -and
    ($winSrc -match 'SessionTunnelProxyLegs -eq \$false')
) 'connect.ps1 gates post-auth Ensure when SessionTunnelProxyLegs=false'

$completeFn = Get-FunctionSource -Content $gmSrc -Name 'Complete-CursorProxyAfterTunnel'
Assert (
    ($completeFn -match 'SessionTunnelProxyLegs -eq \$false') -and
    ($completeFn -notmatch 'elseif \(Get-Command Get-SocksProxyPort')
) 'Complete early-returns on SessionTunnelProxyLegs=false without Get-SocksProxyPort fallback'

# --- Behavioral: Complete must skip and must NOT call Ensure ---
. $gmPath
$script:EnsureCalls = 0
$script:SkipSeen = $false
$script:SessionTunnelProxyLegs = $false
$script:SocksProxyPort = $null
$script:HttpProxyPort = $null

function Write-GitModeLog {
    param([string]$Message, [string]$Level = 'INFO')
    if ($Message -match 'skip_sidecar') { $script:SkipSeen = $true }
}
function Test-LocalPortOpen { param([int]$PortNum) $false }
function Get-CursorHttpFrontPort { 18998 }
function Clear-CursorProxySettingsSidecar { $true }
function Ensure-CursorProxySidecar { $script:EnsureCalls++; throw 'ENSURE_MUST_NOT_RUN' }
function Start-CursorProxySidecar { $script:EnsureCalls++; throw 'START_MUST_NOT_RUN' }
function Test-ProxyHealth { $true }
function Get-CursorProxyMode { 'server_direct' }

$threw = $false
try { Complete-CursorProxyAfterTunnel } catch { $threw = $true }

Assert ($script:SkipSeen) 'behavioral: Complete logs skip_sidecar when SessionTunnelProxyLegs=false'
Assert (-not $threw) 'behavioral: Complete does not throw into Ensure/Start'
Assert ($script:EnsureCalls -eq 0) 'behavioral: Complete never invokes Ensure/Start when no legs'

# Defaults alone must not create legs
$script:SkipSeen = $false
$script:EnsureCalls = 0
$script:SessionTunnelProxyLegs = $false
$script:SocksProxyPort = $null
$script:HttpProxyPort = $null
# Poison: pretend Get-SocksProxyPort would return 19080 (always true in real code)
# Complete must still skip because SessionTunnelProxyLegs=$false
Complete-CursorProxyAfterTunnel
Assert ($script:SkipSeen -and $script:EnsureCalls -eq 0) `
    'behavioral: SessionTunnelProxyLegs=false wins even if fixed ports exist in Get-*'

# Legs present: Complete should attempt Ensure (not skip)
$script:SkipSeen = $false
$script:EnsureCalls = 0
$script:SessionTunnelProxyLegs = $true
$script:SocksProxyPort = 19080
$script:HttpProxyPort = 19180
function Ensure-CursorProxySidecar { $script:EnsureCalls++; return $true }
function Start-CursorProxySidecar { $script:EnsureCalls++; return $true }
function Test-ProxyHealth { $script:LastProxyHealthOk = $true; return $true }
Complete-CursorProxyAfterTunnel
Assert ((-not $script:SkipSeen) -and ($script:EnsureCalls -ge 1)) `
    'behavioral: with SessionTunnelProxyLegs=true Complete still calls Ensure'

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All tunnel-proxy-skip hard tests passed ({0} asserts)." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} passed, {1} failed." -f $Pass, $Fail) -ForegroundColor Red
exit 1
