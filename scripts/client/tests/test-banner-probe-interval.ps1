#Requires -Version 5.1
# test-banner-probe-interval.ps1
# Source-level contract for Stage B (#2 adaptive banner interval + #1 keepalive-first shrink):
#   #2   Forward-probe interval in the bg-alive path of Windows Sync-SessionTunnelProcess
#        (git-mode.ps1) and Mac sync_session_tunnel_forward() (git-mode.sh) grows from
#        30s to 45s, and the TunnelSoftFailCount budget shrinks from 6 to 4 everywhere in
#        that same soft-fail path (keeps ~3min dwell: 45x4=180s). Log strings must show
#        "/4" not "/6". Steady-state probe attempts: when SoftFailCount==0 the probe loop
#        only needs 1 attempt (bg-alive forward is trusted); when SoftFailCount>0 it keeps
#        the existing x3 retry loop (Windows currently always loops `$i -le 3`).
#   #1   Keepalive-first (shrink): when the 45s probe comes due AND SoftFailCount==0 AND
#        the last banner cache was successful AND the banner-defer counter is 0/empty, the
#        tick MAY defer the nc probe entirely (increment the defer counter, log something
#        containing probe_deferred/keepalive_defer, and must NOT call Test-TunnelUp /
#        tunnel_up for that tick). SoftFailCount>0, OR the defer counter already non-zero,
#        MUST still probe (regression guard against bug #3: never skip nc solely because
#        the bg ssh process is alive).
#
# ============================================================================
# EXACT NAMES IMPLEMENTERS MUST MATCH (chosen here, verbatim, do not deviate):
# ============================================================================
#
# WINDOWS (scripts/client/git-mode.ps1), inside Sync-SessionTunnelProcess's
# "$BgTunnel.Value -and -not $BgTunnel.Value.HasExited" bg-alive branch:
#   - Forward-probe gate becomes (bare 45, or a $script:-scoped variable that
#     resolves to 45; either is accepted by this test):
#       elseif (($now - $script:LastForwardProbeAt).TotalSeconds -ge 45) {
#   - TunnelSoftFailCount budget checks change from "-ge 6" to "-ge 4" (both the
#     no_proc_tcp_open_budget AND banner_miss_tcp_open_budget branches in this
#     function).
#   - Matching log strings change from ".../6" to ".../4", e.g.:
#       "TUNNEL_SYNC soft_fail count=$script:TunnelSoftFailCount/4 ..."
#     (at least 2 occurrences of this exact "/4" suffix inside the function.)
#   - New local variable, name:                                   $probeAttempts
#     computed as:
#       $probeAttempts = if ($script:TunnelSoftFailCount -eq 0) { 1 } else { 3 }
#     and the probe loop bound becomes `for ($i = 1; $i -le $probeAttempts; $i++)`
#     (the old hardcoded `$i -le 3` loop bound must be gone).
#   - New script-scoped counter, name:                    $script:TunnelBannerDeferCount
#     initialized to 0 alongside the other script-scoped Tunnel* variables near
#     the top of the file (same block as $script:TunnelSoftFailCount = 0).
#   - Defer gate: a condition inside the bg-alive branch that requires BOTH
#       $script:TunnelSoftFailCount -eq 0
#     AND
#       $script:TunnelBannerDeferCount -eq 0
#     (in either order) plus a check of $script:TunnelBannerCacheUp (last banner
#     cache was successful). On taking this branch: increment
#     $script:TunnelBannerDeferCount, log a message containing "probe_deferred"
#     or "keepalive_defer", and do NOT call Test-TunnelUp for that tick.
#   - Anti-regression: the defer branch must never be gated on
#     $script:TunnelBannerDeferCount alone (without also requiring
#     $script:TunnelSoftFailCount -eq 0) - otherwise a SoftFail>0 tick could
#     still defer, which is forbidden by the locked design.
#
# MAC (scripts/client/git-mode.sh), inside sync_session_tunnel_forward():
#   - Forward-probe gate becomes:
#       if [ $(( now - _LAST_FORWARD_PROBE_AT )) -lt 45 ]; then
#   - _TUNNEL_SOFT_FAIL_COUNT budget checks change from "-ge 6" to "-ge 4".
#   - Matching log strings change from ".../6" to ".../4", e.g.:
#       "TUNNEL_SYNC soft_fail count=$_TUNNEL_SOFT_FAIL_COUNT/4 ..."
#     (at least 2 occurrences of this exact "/4" suffix inside the function.)
#   - New global counter, name:                            _TUNNEL_BANNER_DEFER_COUNT
#     initialized to 0 alongside the other tunnel globals near the top of the
#     file (same block as _TUNNEL_SOFT_FAIL_COUNT=0 / _LAST_FORWARD_PROBE_AT=0).
#   - Defer gate: a condition requiring BOTH
#       _TUNNEL_SOFT_FAIL_COUNT -eq 0 (or equivalent "$_TUNNEL_SOFT_FAIL_COUNT" check)
#     AND
#       _TUNNEL_BANNER_DEFER_COUNT -eq 0
#     (in either order) plus a check of _TUNNEL_BANNER_CACHE_UP (last banner
#     cache was successful), logging probe_deferred/keepalive_defer and skipping
#     the tunnel_up call for that tick.
#   - tunnel_up must still be called in this function for the SoftFail>0 /
#     defer-already-used path (regression guard against bug #3).
#
# MUST-NOT (regression guards, all Stage B items):
#   - Skip the nc/tunnel_up probe solely because the bg ssh process is alive
#     (bug #3) - the defer path is only allowed when SoftFailCount==0 AND the
#     defer counter is still 0.
#   - Touch ControlMaster behavior.
#   - Collapse the SoftFail dwell window below ~3 minutes (45 x 4 = 180s).
#   - Hardcode ConnectVersion anywhere in this test.
# ============================================================================

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0

function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

# Resolve a PowerShell token (bare int literal OR a $script:-scoped variable name)
# to its integer value by looking up "$script:Name = N" elsewhere in $raw. Mirrors
# the "-ge 45 (or script variable ProbeIntervalSec = 45)" allowance the locked
# design explicitly grants for the interval, generalized to any numeric constant
# so this test verifies the CONTRACT VALUE, not a specific implementer's choice
# of literal-vs-named-constant style.
function Resolve-WinIntToken([string]$Token, [string]$Raw) {
    if ($Token -match '^\d+$') { return [int]$Token }
    if ($Token -match '^\$script:(\w+)$') {
        $name = $Matches[1]
        $m2 = [regex]::Match($Raw, "\`$script:$name\s*=\s*(\d+)\b")
        if ($m2.Success) { return [int]$m2.Groups[1].Value }
    }
    return $null
}

# Same idea for Mac shell tokens: bare int literal OR a (possibly quoted) $VAR_NAME
# resolved via "VAR_NAME=N" elsewhere in $raw.
function Resolve-ShIntToken([string]$Token, [string]$Raw) {
    if ($Token -match '^\d+$') { return [int]$Token }
    if ($Token -match '^"?\$(\w+)"?$') {
        $name = $Matches[1]
        $m2 = [regex]::Match($Raw, "(?m)^$name=(\d+)\b")
        if ($m2.Success) { return [int]$m2.Groups[1].Value }
    }
    return $null
}

Write-Host ''
Write-Host '=== BANNER_PROBE_INTERVAL: adaptive 45s interval + SoftFail/4 budget + keepalive-first defer (source contracts) ===' -ForegroundColor Cyan
Write-Host ''

$win = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw
$mac = Get-Content (Get-ClientFile 'git-mode.sh') -Raw

# ----------------------------------------------------------------------------
# Extract focused function bodies
# ----------------------------------------------------------------------------

# Windows: Sync-SessionTunnelProcess function body (git-mode.ps1)
$syncFuncBlock = ''
if ($win -match '(?s)function Sync-SessionTunnelProcess \{.*?\r?\n\}\r?\n\r?\nfunction Wait-ForTunnelUp') {
    $syncFuncBlock = $Matches[0]
}
Assert ($syncFuncBlock.Length -gt 500) 'extracted Sync-SessionTunnelProcess function body'

# Mac: sync_session_tunnel_forward() function body (git-mode.sh)
$macSyncBlock = ''
if ($mac -match '(?s)sync_session_tunnel_forward\(\) \{.*?\r?\n\}\r?\n\r?\nwait_for_tunnel_up\(\) \{') {
    $macSyncBlock = $Matches[0]
}
Assert ($macSyncBlock.Length -gt 500) 'extracted sync_session_tunnel_forward() function body'

# ============================================================================
# #2 Windows: probe interval 30s -> 45s
# ============================================================================
Write-Host '--- #2 Windows: forward-probe interval 30s -> 45s ---' -ForegroundColor Cyan
$winIntervalMatch = [regex]::Match($syncFuncBlock, 'elseif\s*\(\(\$now\s*-\s*\$script:LastForwardProbeAt\)\.TotalSeconds\s*-ge\s*(\$script:\w+|\d+)\)')
Assert $winIntervalMatch.Success 'forward-probe elseif gate on ($now - $script:LastForwardProbeAt).TotalSeconds -ge <threshold> found'
$winIntervalToken = if ($winIntervalMatch.Success) { $winIntervalMatch.Groups[1].Value } else { '' }
$winIntervalIs45 = $false
if ($winIntervalToken -eq '45') {
    $winIntervalIs45 = $true
} elseif ($winIntervalToken -match '^\$script:(\w+)$') {
    $varName = $Matches[1]
    if ($win -match "\`$script:$varName\s*=\s*45\b") { $winIntervalIs45 = $true }
}
Assert $winIntervalIs45 "forward-probe gate threshold resolves to 45 seconds (found token: '$winIntervalToken')"
Assert ($winIntervalToken -ne '30') 'forward-probe gate is NOT the old bare 30s threshold'

# ============================================================================
# #2 Windows: SoftFail budget 6 -> 4 (Sync-SessionTunnelProcess only)
# Threshold may be a bare literal or a named $script: constant (same allowance
# as the interval above) - this test verifies the resolved VALUE is 4, not a
# specific spelling.
# ============================================================================
Write-Host '--- #2 Windows: SoftFail budget 6 -> 4 in Sync-SessionTunnelProcess ---' -ForegroundColor Cyan
$softFailGeMatches = [regex]::Matches($syncFuncBlock, '\$script:TunnelSoftFailCount\s*-ge\s*(\$script:\w+|\d+)')
$softFailGeGood = 0; $softFailGeBad6 = 0
foreach ($m in $softFailGeMatches) {
    $val = Resolve-WinIntToken $m.Groups[1].Value $win
    if ($val -eq 4) { $softFailGeGood++ }
    if ($val -eq 6) { $softFailGeBad6++ }
}
Assert ($softFailGeGood -ge 2) "Sync-SessionTunnelProcess has >=2 'TunnelSoftFailCount -ge <threshold>' checks resolving to 4 (found $softFailGeGood of $($softFailGeMatches.Count) total)"
Assert ($softFailGeBad6 -eq 0) 'no TunnelSoftFailCount -ge <threshold> check resolves to the old value 6'

$softFailLogMatches = [regex]::Matches($syncFuncBlock, [regex]::Escape('soft_fail count=$script:TunnelSoftFailCount/') + '(\$script:\w+|\d+)')
$softFailLogGood = 0; $softFailLogBad6 = 0
foreach ($m in $softFailLogMatches) {
    $val = Resolve-WinIntToken $m.Groups[1].Value $win
    if ($val -eq 4) { $softFailLogGood++ }
    if ($val -eq 6) { $softFailLogBad6++ }
}
Assert ($softFailLogGood -ge 2) "Sync-SessionTunnelProcess logs 'soft_fail count=.../<threshold>' at least twice resolving to 4 (found $softFailLogGood of $($softFailLogMatches.Count) total)"
Assert ($softFailLogBad6 -eq 0) "no 'soft_fail count=.../<threshold>' log resolves to the old value 6"

# ============================================================================
# #2 Windows: steady-state probe attempts (SoftFail==0 -> 1, SoftFail>0 -> x3)
# Accept either branch order ("-eq 0 -> 1 else 3" or "-gt 0 -> 3 else 1") and
# any local variable name - this test verifies the resolved 1-vs-3 mapping and
# that the probe loop bound actually uses that variable (not a hardcoded 3).
# ============================================================================
Write-Host '--- #2 Windows: steady-state probe attempts (SoftFail==0 -> 1 attempt, SoftFail>0 -> 3 attempts) ---' -ForegroundColor Cyan
$attemptsMatch = [regex]::Match($syncFuncBlock, '(?s)(\$\w+)\s*=\s*if\s*\(\s*\$script:TunnelSoftFailCount\s*(-eq|-gt)\s*0\s*\)\s*\{\s*(\d+)\s*\}\s*else\s*\{\s*(\d+)\s*\}')
$attemptsOk = $false
$attemptsVar = ''
if ($attemptsMatch.Success) {
    $attemptsVar = $attemptsMatch.Groups[1].Value
    $op = $attemptsMatch.Groups[2].Value
    $v1 = [int]$attemptsMatch.Groups[3].Value
    $v2 = [int]$attemptsMatch.Groups[4].Value
    if ($op -eq '-eq') { $zeroCaseVal = $v1; $nonZeroCaseVal = $v2 } else { $nonZeroCaseVal = $v1; $zeroCaseVal = $v2 }
    $attemptsOk = ($zeroCaseVal -eq 1) -and ($nonZeroCaseVal -eq 3)
}
Assert $attemptsOk 'a variable is assigned 1 attempt when TunnelSoftFailCount==0 and 3 attempts when TunnelSoftFailCount>0 (either branch order)'
Assert (
    $attemptsMatch.Success -and ($syncFuncBlock -match "\`$i\s*-le\s*$([regex]::Escape($attemptsVar))")
) "probe loop bound uses the adaptive attempts variable ($attemptsVar), not a hardcoded literal"
Assert ($syncFuncBlock -notmatch '\$i\s*=\s*1;\s*\$i\s*-le\s*3;\s*\$i\+\+') 'old hardcoded "for ($i = 1; $i -le 3; $i++)" probe loop bound removed'

# ============================================================================
# #1 Windows: keepalive-first shrink (defer nc when SoftFail==0, cache healthy, defer unused)
# ============================================================================
Write-Host '--- #1 Windows: keepalive-first defer path ---' -ForegroundColor Cyan
Assert ($win -match '\$script:TunnelBannerDeferCount\s*=\s*0') '$script:TunnelBannerDeferCount initialized at script scope (0)'
# Defer-count-is-unused check may be spelled "-eq 0" or "-lt 1" (equivalent for a
# non-negative counter) - accept either.
$deferZeroPat = '(?:\[int\])?\$script:TunnelBannerDeferCount\s*(?:-eq\s*0|-lt\s*1)'
$winDeferGate = (
    $syncFuncBlock -match "(?s)\`$script:TunnelSoftFailCount\s*-eq\s*0[\s\S]{0,160}?$deferZeroPat"
) -or (
    $syncFuncBlock -match "(?s)$deferZeroPat[\s\S]{0,160}?\`$script:TunnelSoftFailCount\s*-eq\s*0"
)
Assert $winDeferGate 'defer gate requires BOTH $script:TunnelSoftFailCount -eq 0 AND TunnelBannerDeferCount unused (-eq 0 / -lt 1)'
Assert ($syncFuncBlock -match 'TunnelBannerCacheUp') 'defer gate consults last banner cache success ($script:TunnelBannerCacheUp)'
Assert ($syncFuncBlock -match '\$script:TunnelBannerDeferCount\+\+') 'defer path increments $script:TunnelBannerDeferCount'
Assert ($syncFuncBlock -match 'probe_deferred|keepalive_defer') "defer path logs a message containing 'probe_deferred' or 'keepalive_defer'"

# ============================================================================
# Anti-#3 Windows regression guard: SoftFail>0 must still probe via Test-TunnelUp
# ============================================================================
Write-Host '--- Anti-#3 Windows: SoftFail>0 must still probe via Test-TunnelUp (never skip solely on bg_alive) ---' -ForegroundColor Cyan
Assert ($syncFuncBlock -match 'Test-TunnelUp') 'Sync-SessionTunnelProcess still calls Test-TunnelUp in the bg-alive path'
Assert (
    -not ($syncFuncBlock -match '(?s)if\s*\(\s*\$script:TunnelBannerDeferCount\s*-eq\s*0\s*\)\s*\{\s*\$script:TunnelBannerDeferCount\+\+[\s\S]{0,200}return \$true')
) 'defer branch is never gated on $script:TunnelBannerDeferCount alone (must also require $script:TunnelSoftFailCount -eq 0)'

# ============================================================================
# #2 Mac: probe interval 30s -> 45s (bare 45 or a shell variable resolving to 45)
# ============================================================================
Write-Host '--- #2 Mac: forward-probe interval 30s -> 45s ---' -ForegroundColor Cyan
$macIntervalMatch = [regex]::Match($macSyncBlock, '\(\(\s*now\s*-\s*_LAST_FORWARD_PROBE_AT\s*\)\)\s*-lt\s*("?\$\w+"?|\d+)')
Assert $macIntervalMatch.Success 'sync_session_tunnel_forward has a $(( now - _LAST_FORWARD_PROBE_AT )) -lt <threshold> gate'
$macIntervalToken = if ($macIntervalMatch.Success) { $macIntervalMatch.Groups[1].Value } else { '' }
$macIntervalVal = Resolve-ShIntToken $macIntervalToken $mac
Assert ($macIntervalVal -eq 45) "forward-probe gate threshold resolves to 45 seconds (found token: '$macIntervalToken')"
Assert ($macIntervalVal -ne 30) 'forward-probe gate is NOT the old bare 30s threshold'

# ============================================================================
# #2 Mac: SoftFail budget 6 -> 4
# ============================================================================
Write-Host '--- #2 Mac: SoftFail budget 6 -> 4 in sync_session_tunnel_forward ---' -ForegroundColor Cyan
Assert ($macSyncBlock -match '"\$_TUNNEL_SOFT_FAIL_COUNT"\s*-ge\s*4') 'sync_session_tunnel_forward checks "$_TUNNEL_SOFT_FAIL_COUNT" -ge 4'
Assert ($macSyncBlock -notmatch '"\$_TUNNEL_SOFT_FAIL_COUNT"\s*-ge\s*6') 'old "$_TUNNEL_SOFT_FAIL_COUNT" -ge 6 check removed'
$macSoftFailLog4 = [regex]::Matches($macSyncBlock, [regex]::Escape('soft_fail count=$_TUNNEL_SOFT_FAIL_COUNT/4'))
Assert ($macSoftFailLog4.Count -ge 2) "sync_session_tunnel_forward logs 'soft_fail count=.../4' at least twice (found $($macSoftFailLog4.Count))"
Assert ($macSyncBlock -notmatch [regex]::Escape('soft_fail count=$_TUNNEL_SOFT_FAIL_COUNT/6')) "sync_session_tunnel_forward no longer logs 'soft_fail count=.../6'"

# ============================================================================
# #1 Mac: keepalive-first defer counter
# ============================================================================
Write-Host '--- #1 Mac: keepalive-first defer path ---' -ForegroundColor Cyan
Assert ($mac -match '_TUNNEL_BANNER_DEFER_COUNT=0') '_TUNNEL_BANNER_DEFER_COUNT initialized (=0) alongside other tunnel globals'
$macDeferGate = (
    $macSyncBlock -match '(?s)_TUNNEL_SOFT_FAIL_COUNT[\s\S]{0,60}?-eq\s*0[\s\S]{0,120}?_TUNNEL_BANNER_DEFER_COUNT[\s\S]{0,60}?-eq\s*0'
) -or (
    $macSyncBlock -match '(?s)_TUNNEL_BANNER_DEFER_COUNT[\s\S]{0,60}?-eq\s*0[\s\S]{0,120}?_TUNNEL_SOFT_FAIL_COUNT[\s\S]{0,60}?-eq\s*0'
)
Assert $macDeferGate 'defer gate requires BOTH _TUNNEL_SOFT_FAIL_COUNT -eq 0 AND _TUNNEL_BANNER_DEFER_COUNT -eq 0'
Assert ($macSyncBlock -match '_TUNNEL_BANNER_CACHE_UP') 'Mac defer gate consults last banner cache success (_TUNNEL_BANNER_CACHE_UP)'
Assert ($macSyncBlock -match 'probe_deferred|keepalive_defer') "Mac defer path logs a message containing 'probe_deferred' or 'keepalive_defer'"

# ============================================================================
# Anti-#3 Mac regression guard: SoftFail>0 must still call tunnel_up
# ============================================================================
Write-Host '--- Anti-#3 Mac: SoftFail>0 must still call tunnel_up ---' -ForegroundColor Cyan
Assert ($macSyncBlock -match 'tunnel_up') 'sync_session_tunnel_forward still calls tunnel_up() in the bg-alive path'
Assert (
    -not ($macSyncBlock -match '(?s)if\s*\[\s*"\$_TUNNEL_BANNER_DEFER_COUNT"\s*-eq\s*0\s*\][\s\S]{0,200}_TUNNEL_BANNER_DEFER_COUNT\s*=\s*\$\(\(\s*_TUNNEL_BANNER_DEFER_COUNT\s*\+\s*1\s*\)\)[\s\S]{0,120}return 0')
) 'Mac defer branch is never gated on _TUNNEL_BANNER_DEFER_COUNT alone (must also require _TUNNEL_SOFT_FAIL_COUNT -eq 0)'

Write-Host ''
if ($fail -gt 0) {
    Write-Host "FAILED: $fail assertion(s)" -ForegroundColor Red
    exit 1
}
Write-Host 'ALL PASS' -ForegroundColor Green
exit 0
