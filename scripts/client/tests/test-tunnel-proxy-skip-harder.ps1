#Requires -Version 5.1
# test-tunnel-proxy-skip-harder.ps1 - HARDER than test-tunnel-proxy-skip-hard.ps1.
# Designed to FAIL on residual bugs Bugbot found after "hard tests passed"
# while live Connect still burned ~15s (a8a37c2a418d / trust gap 2026-07-28).
#
# Cases the weaker hard suite MISSED:
#   A) SessionTunnelProxyLegs=$null + orphan 19080/19180 "listening" must SKIP
#      (old adopt_backends called Ensure → live thrash)
#   B) SessionTunnelProxyLegs=$false wins even if stale SocksProxyPort is set
#   C) Set-SocksProxyPortOnReuse sets SessionTunnelProxyLegs false/true
#   D) connect.ps1 Start-CursorProxySidecar retry gated by mayEnsureSidecar
#   E) Mac + Win have NO adopt_backends
#   F) With SessionTunnelProxyLegs=$true + ports, Ensure still runs
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== tunnel proxy skip HARDER (reuse / adopt / Start ungated) ===' -ForegroundColor Cyan
Write-Host ''

$gmPath = Get-ClientFile 'git-mode.ps1'
$winPath = Get-ClientFile 'windows\connect.ps1'
$macPath = Get-ClientFile 'git-mode.sh'
$gmSrc = Get-Content -LiteralPath $gmPath -Raw
$winSrc = Get-Content -LiteralPath $winPath -Raw
$macSrc = Get-Content -LiteralPath $macPath -Raw

# --- Static ---
Assert ($gmSrc -notmatch 'adopt_backends continuing_sidecar') 'Win Complete has NO orphan-listener adopt path'
Assert ($macSrc -notmatch 'adopt_backends continuing_sidecar') 'Mac complete has NO orphan-listener adopt path'
Assert ($macSrc -match 'skip_sidecar reason=no_tunnel_proxy_legs') 'Mac logs skip_sidecar when session has no proxy ports'

$reuseFn = Get-FunctionSource -Content $gmSrc -Name 'Set-SocksProxyPortOnReuse'
Assert (
    ($reuseFn -match 'SessionTunnelProxyLegs\s*=\s*\$false') -and
    ($reuseFn -match 'SessionTunnelProxyLegs\s*=\s*\$true')
) 'Set-SocksProxyPortOnReuse sets SessionTunnelProxyLegs on success and failure paths'

$completeFn = Get-FunctionSource -Content $gmSrc -Name 'Complete-CursorProxyAfterTunnel'
Assert (
    ($completeFn -match 'SessionTunnelProxyLegs -eq \$false') -and
    ($completeFn -match 'sessionHasLegs')
) 'Complete early-skips on SessionTunnelProxyLegs=false before sessionHasLegs'

$authIdx = $winSrc.IndexOf('Heal sticky proxy front door before Cursor')
Assert ($authIdx -ge 0) 'post-auth sidecar heal block present'
$slice = $winSrc.Substring($authIdx, [Math]::Min(2200, $winSrc.Length - $authIdx))
Assert (
    ($slice -match 'SIDECAR_ENSURE skip reason=no_tunnel_proxy_legs') -and
    ($slice -match '\$mayEnsureSidecar -and \$null -ne \$script:LastProxyHealthOk') -and
    ($slice -match 'Start-CursorProxySidecar')
) 'post-auth Start-CursorProxySidecar requires mayEnsureSidecar (not ungated)'

# --- Behavioral helpers ---
. $gmPath

function Write-GitModeLog {
    param([string]$Message, [string]$Level = 'INFO')
    if ($Message -match 'skip_sidecar') { $script:SkipSeen = $true }
    if ($Message -match 'adopt_backends') { $script:AdoptSeen = $true }
}
function Test-LocalPortOpen {
    param([int]$PortNum)
    return ($PortNum -eq 19080 -or $PortNum -eq 19180 -or $PortNum -eq 18998)
}
function Get-CursorHttpFrontPort { 18998 }
function Clear-CursorProxySettingsSidecar { $true }
function Ensure-CursorProxySidecar { $script:EnsureCalls++; throw 'ENSURE_MUST_NOT_RUN' }
function Start-CursorProxySidecar { $script:EnsureCalls++; throw 'START_MUST_NOT_RUN' }
function Test-ProxyHealth { $true }
function Get-CursorProxyMode { 'server_direct' }

function Reset-ProxySkipState {
    $script:EnsureCalls = 0
    $script:SkipSeen = $false
    $script:AdoptSeen = $false
}

# A) unset flag + orphan listeners listening → skip (would have adopted before)
Reset-ProxySkipState
$script:SessionTunnelProxyLegs = $null
$script:SocksProxyPort = $null
$script:HttpProxyPort = $null
$threw = $false
try { Complete-CursorProxyAfterTunnel } catch { $threw = $true }
Assert ($script:SkipSeen -and -not $threw -and $script:EnsureCalls -eq 0 -and -not $script:AdoptSeen) `
    'HARDER A: Legs=$null + orphan 19080/19180 up => skip, no Ensure'

# B) Legs=false + stale SocksProxyPort still set → skip (explicit false wins)
Reset-ProxySkipState
$script:SessionTunnelProxyLegs = $false
$script:SocksProxyPort = 19080
$script:HttpProxyPort = 19180
$threw = $false
try { Complete-CursorProxyAfterTunnel } catch { $threw = $true }
Assert ($script:SkipSeen -and -not $threw -and $script:EnsureCalls -eq 0) `
    'HARDER B: Legs=$false wins over stale SocksProxyPort (no Ensure)'

# C) reuse helper: no -L cmdline => Legs=false
Reset-ProxySkipState
$script:SessionTunnelProxyLegs = $null
$script:SocksProxyPort = $null
$script:HttpProxyPort = $null
$script:XrayServerSocksPort = 10808
$script:XrayServerHttpPort = 10809
function Get-CimInstance {
    param($ClassName, $Filter)
    return [pscustomobject]@{ CommandLine = 'ssh -N -R 20021:localhost:22 claude-server' }
}
function Test-RemoteXraySocksOpen { param($Alias, $SshCfgPath, $RemotePort) $true }
Set-SocksProxyPortOnReuse -TunnelPid 1 -Alias 'claude-server' -SshCfgPath ''
Assert ($script:SessionTunnelProxyLegs -eq $false) `
    'HARDER C: Set-SocksProxyPortOnReuse sets Legs=$false when tunnel cmdline has no -L'

# D) Legs=true + session ports => Ensure runs
Reset-ProxySkipState
$script:SessionTunnelProxyLegs = $true
$script:SocksProxyPort = 19080
$script:HttpProxyPort = 19180
function Ensure-CursorProxySidecar { $script:EnsureCalls++; return $true }
function Start-CursorProxySidecar { $script:EnsureCalls++; return $true }
function Test-ProxyHealth { $script:LastProxyHealthOk = $true; return $true }
Complete-CursorProxyAfterTunnel
Assert ((-not $script:SkipSeen) -and ($script:EnsureCalls -ge 1)) `
    'HARDER D: Legs=$true still calls Ensure (positive path)'

Write-Host ''
if ($Fail -eq 0) {
    Write-Host ("All HARDER tunnel-proxy-skip tests passed ({0} asserts)." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} passed, {1} failed." -f $Pass, $Fail) -ForegroundColor Red
exit 1
