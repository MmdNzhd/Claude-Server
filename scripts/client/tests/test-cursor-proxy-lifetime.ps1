# test-cursor-proxy-lifetime.ps1 - Phase A/B proxy contracts (static)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = (Get-Location).Path }
# When run from scripts/client/tests, parent is scripts/client
$ClientRoot = Split-Path -Parent $PSScriptRoot
$failed = 0
function Assert([bool]$cond, [string]$msg) {
    if ($cond) { Write-Host "  PASS $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:failed++ }
}

$el = Get-Content -LiteralPath (Join-Path $ClientRoot 'editor-launch.ps1') -Raw
$gm = Get-Content -LiteralPath (Join-Path $ClientRoot 'git-mode.ps1') -Raw
$cp = Get-Content -LiteralPath (Join-Path $ClientRoot 'windows\connect.ps1') -Raw
$els = Get-Content -LiteralPath (Join-Path $ClientRoot 'editor-launch.sh') -Raw
$gms = Get-Content -LiteralPath (Join-Path $ClientRoot 'git-mode.sh') -Raw

Assert ($el -match 'CURSOR_PROXY_CLEAR_SKIP') 'Win CLEAR_SKIP present'
Assert ($el -match 'function Test-MayClearCursorProxySettings') 'Win Test-MayClearCursorProxySettings'
Assert ($el -match 'CURSOR_PROXY_ALIGN') 'Win CURSOR_PROXY_ALIGN'
Assert ($el -match 'CursorSocksFrontPort') 'Win prefers sidecar front port'
Assert ($gm -match 'return 19080') 'Win fixed socks 19080'
Assert ($gm -match 'return 19180') 'Win fixed http 19180'
Assert ($gm -notmatch 'return 19080 \+ \$slot') 'Win no per-slot socks'
Assert ($gm -match 'function Claim-CursorProxyOwner') 'Win owner claim'
Assert ($gm -match 'function Test-ProxyHealth') 'Win PROXY_HEALTH'
Assert ($gm -match 'Test-LocalPortOpen') 'Win TcpClient port probe'
Assert ($gm -notmatch 'Test-NetConnection') 'Win no Test-NetConnection'
Assert ($gm -match 'TunnelWaitBackoffSec') 'Win wait backoff'
Assert ($gm -match 'reseed_skip') 'Win reseed_skip'
Assert ($gm -match 'proxy_adopted_elsewhere') 'Win proxy_adopted_elsewhere'
Assert ($cp -match "ConnectVersion = '\d{8}\.\d+'") 'Win ConnectVersion defined'
Assert ($els -match 'auth_relaunch_never_kill') 'Mac never_kill'
Assert ($els -match 'CURSOR_PROXY_CLEAR_SKIP|test_may_clear_cursor_proxy_settings') 'Mac clear skip'
Assert ($gms -match 'printf ''%s'' 19080' -or $gms -match 'printf "%s" 19080' -or ($gms -match 'socks_proxy_port' -and $gms -match '19080')) 'Mac fixed 19080'
Assert ($gms -match 'claim_cursor_proxy_owner') 'Mac owner claim'
Assert ($gms -match 'reseed_skip') 'Mac reseed_skip'
Assert ($gms -match 'proxy_adopted_elsewhere') 'Mac proxy_adopted_elsewhere'
$side = Join-Path $ClientRoot 'windows\cursor-proxy-sidecar.ps1'
Assert (Test-Path -LiteralPath $side) 'Win sidecar file exists'
Assert ((Get-Content -LiteralPath $side -Raw) -match 'Start-CursorProxySidecar') 'Win sidecar function'

# server_direct last-resort contracts (xray/sidecar down -> clear dead proxy)
Assert ($gm -match 'PROXY_FALLBACK mode=server_direct') 'Win PROXY_FALLBACK server_direct'
Assert ($gm -match 'function Get-CursorProxyMode') 'Win Get-CursorProxyMode'
Assert ($gm -match "return 'server_direct'") 'Win Get-CursorProxyMode server_direct'
Assert ($el -match 'LAUNCH_PROXY mode=') 'Win LAUNCH_PROXY log'
Assert ($el -match 'mode=server_direct') 'Win LAUNCH_PROXY server_direct'
Assert ($gms -match 'PROXY_FALLBACK mode=server_direct') 'Mac PROXY_FALLBACK server_direct'
Assert ($gms -match 'get_cursor_proxy_mode') 'Mac get_cursor_proxy_mode'
Assert ($els -match 'LAUNCH_PROXY mode=') 'Mac LAUNCH_PROXY log'
$remoteSync = Join-Path (Split-Path -Parent $ClientRoot) 'server\cursor-remote-proxy-sync.sh'
if (-not (Test-Path -LiteralPath $remoteSync)) {
    $remoteSync = Join-Path (Split-Path -Parent (Split-Path -Parent $ClientRoot)) 'scripts\server\cursor-remote-proxy-sync.sh'
}
Assert (Test-Path -LiteralPath $remoteSync) 'cursor-remote-proxy-sync.sh exists'
Assert ((Get-Content -LiteralPath $remoteSync -Raw) -match 'server_direct') 'remote sync server_direct mode'
Assert ((Get-Content -LiteralPath $remoteSync -Raw) -match 'http\.proxySupport.*=.*off|proxySupport.: .off.') 'remote sync proxySupport off'

if ($failed -gt 0) { Write-Host "FAILED $failed" -ForegroundColor Red; exit 1 }
Write-Host 'All proxy lifetime asserts passed' -ForegroundColor Green
exit 0
