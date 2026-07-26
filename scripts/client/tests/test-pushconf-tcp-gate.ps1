# test-pushconf-tcp-gate.ps1 - Push-ServerConnectConf skips foreign/hostkey probes on closed port
# Callers: scripts/client/tests/run-all.ps1
# Guards the 2026-07-25 "Server setup ~4s waste" fix: on a fresh connect the reverse tunnel is
# not up yet, so the session port is closed. A closed port cannot host a foreign peer and has no
# host key, yet Test-TunnelHostKeyMismatch used to run a ~4s ssh-keyscan (Get-TunnelHostKeyFingerprint)
# that burned its full `timeout 4` against the dead port. Push-ServerConnectConf now gates BOTH
# safety probes behind one cheap Test-TunnelPortTcpOpen check. This test asserts the source shape;
# a full functional run needs a live tunnel (see the -live suites).
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Push-conf tcp gate ===' -ForegroundColor Cyan
Write-Host ''

$gm  = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$fn  = Get-FunctionSource -Content $gm -Name 'Push-ServerConnectConf'
Assert ($fn) 'extracted Push-ServerConnectConf body'

# Strip comment lines so function-name mentions in explanatory comments do not skew index order.
$code = (($fn -split "`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"

# The tcp-open gate must exist and wrap the two safety probes.
$tcpIdx     = $code.IndexOf('Test-TunnelPortTcpOpen')
$foreignIdx = $code.IndexOf('Test-TunnelPortIsForeignPeer')
$hostkeyIdx = $code.IndexOf('Test-TunnelHostKeyMismatch')
Assert ($tcpIdx -ge 0) 'Push-ServerConnectConf probes Test-TunnelPortTcpOpen'
Assert ($foreignIdx -ge 0 -and $hostkeyIdx -ge 0) 'foreign-peer + hostkey-mismatch checks still present'
Assert ($tcpIdx -lt $foreignIdx -and $tcpIdx -lt $hostkeyIdx) 'tcp-open gate runs BEFORE both safety probes'
Assert ($fn -match 'pushPortListening') 'uses a listening-gate variable'
Assert ($fn -match 'safety_probes_skipped.*tcp_closed') 'logs the closed-port skip for observability'
Assert ($fn -match 'safety_probes_skipped.*session_tunnel_fresh') 'logs session_tunnel_fresh skip (post Ensure-Tunnel Prepare path)'
Assert ($fn -match 'LastTunnelSpawnSuccessAt') 'session_tunnel_fresh consults LastTunnelSpawnSuccessAt'
Assert ($fn -match 'LastTunnelSpawnSuccessPort') 'session_tunnel_fresh checks port match'
Assert ($fn -match 'TotalSeconds\s*-lt\s*30') 'session_tunnel_fresh TTL is 30s (matches ENSURE recent_success)'

# The gate must guard both checks (they live inside the if-listening block, not unconditionally).
Assert ($fn -match 'if\s*\(\s*\$pushPortListening\s*\)') 'both safety probes are inside the if($pushPortListening) block'

# Regression guard: the hostkey scan itself keeps a bounded timeout.
Assert ($gm -match "timeout 4 ssh-keyscan") 'ssh-keyscan retains a bounded timeout'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
