#Requires -Version 5.1
# test-incident-gap-replay-contract.ps1 - Task 7: S2 token parity + S6 A-E source contracts
# FAIL build if any S2 token missing on Win or Mac, Ensure can kill before CanClaim gate,
# or Wait can succeed without local -R ownership check.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_paths.ps1')

$Pass = 0
$Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ''
Write-Host '=== incident Gap replay contract (S2 + S6 A-E) ===' -ForegroundColor Cyan
Write-Host ''

$gmPath = Get-ClientFile 'git-mode.ps1'
$shPath = Get-ClientFile 'git-mode.sh'
$winPath = Get-ClientFile 'windows\connect.ps1'
$gm = Get-Content -LiteralPath $gmPath -Raw
$sh = Get-Content -LiteralPath $shPath -Raw
$win = Get-Content -LiteralPath $winPath -Raw

# --- S2: byte-identical reason tokens on Win + Mac ---
$s2 = @(
    'foreign_owner_cannot_bind'
    'local_r_not_owned'
    'stale_port_busy'
    'reason=service_dead'
    'stale_non_connect'
    'soft_fail_exhausted_zombie_drop'
)
foreach ($tok in $s2) {
    Assert ($gm -match [regex]::Escape($tok)) "S2 Win git-mode.ps1 has $tok"
    Assert ($sh -match [regex]::Escape($tok)) "S2 Mac git-mode.sh has $tok"
}
Assert ($win -match 'foreign_owner_cannot_bind') 'S2 connect.ps1 bg_init has foreign_owner_cannot_bind'

# --- Ensure: CanClaim / ProxyReseedShouldKill before killing stale bg ---
$ens = Get-FunctionSource -Content $gm -Name 'Ensure-SessionTunnel'
Assert (-not [string]::IsNullOrWhiteSpace($ens)) 'extracted Ensure-SessionTunnel'
$gateIdx = $ens.IndexOf('Test-ProxyReseedShouldKill')
if ($gateIdx -lt 0) { $gateIdx = $ens.IndexOf('Test-CanClaimCursorProxyOwner') }
$killIdx = $ens.IndexOf('killing stale bg')
Assert ($gateIdx -ge 0) 'Ensure calls Test-ProxyReseedShouldKill or Test-CanClaimCursorProxyOwner'
Assert ($killIdx -ge 0) 'Ensure still has killing stale bg path (positive heal)'
Assert ($gateIdx -ge 0 -and $killIdx -gt $gateIdx) `
    'Ensure orders CanClaim/ProxyReseedShouldKill before killing stale bg'

$reseedKill = Get-FunctionSource -Content $gm -Name 'Test-ProxyReseedShouldKill'
Assert (-not [string]::IsNullOrWhiteSpace($reseedKill)) 'extracted Test-ProxyReseedShouldKill'
Assert ($reseedKill -match 'Test-CanClaimCursorProxyOwner') `
    'Test-ProxyReseedShouldKill consults Test-CanClaimCursorProxyOwner'
Assert ($reseedKill -match 'foreign_owner_cannot_bind') `
    'Test-ProxyReseedShouldKill emits foreign_owner_cannot_bind'

# Mac ensure: can_claim before kill of stale bg
Assert ($sh -match 'proxy_reseed_should_kill|can_claim_cursor_proxy_owner') `
    'Mac ensure uses claim/reseed gate helper'
$macEnsure = ''
if ($sh -match '(?s)ensure_session_tunnel\(\)\s*\{.*?(?=^[a-z_][a-z0-9_]*\(\)\s*\{|\z)') {
    $macEnsure = $Matches[0]
}
if ([string]::IsNullOrWhiteSpace($macEnsure) -and ($sh -match '(?s)ensure_session_tunnel\(\)\s*\{.*')) {
    $macEnsure = $Matches[0]
}
Assert (-not [string]::IsNullOrWhiteSpace($macEnsure)) 'extracted Mac ensure_session_tunnel'
$macGate = [Math]::Max(
    $macEnsure.IndexOf('proxy_reseed_should_kill'),
    $macEnsure.IndexOf('can_claim_cursor_proxy_owner')
)
# Mac may use kill/stop wording; accept either kill pattern near reseed
$macKill = $macEnsure.IndexOf('killing stale')
if ($macKill -lt 0) { $macKill = $macEnsure.IndexOf('stop_tunnel') }
if ($macKill -lt 0) { $macKill = $macEnsure.IndexOf('kill ') }
Assert ($macGate -ge 0) 'Mac ensure has claim/reseed gate'
Assert ($macGate -ge 0 -and ($macKill -lt 0 -or $macKill -gt $macGate)) `
    'Mac ensure orders claim gate before stale kill (or no kill string in body)'

# --- Wait: local -R check before success ---
$waitFn = Get-FunctionSource -Content $gm -Name 'Wait-ForTunnelUp'
Assert (-not [string]::IsNullOrWhiteSpace($waitFn)) 'extracted Wait-ForTunnelUp'
Assert ($waitFn -match 'Get-LocalTunnelSshPids') 'Wait calls Get-LocalTunnelSshPids'
Assert ($waitFn -match 'local_r_not_owned') 'Wait emits local_r_not_owned'
$pidsIdx = $waitFn.IndexOf('Get-LocalTunnelSshPids')
$trueIdx = $waitFn.LastIndexOf('return $true')
Assert ($pidsIdx -ge 0 -and $trueIdx -gt $pidsIdx) `
    'Wait: Get-LocalTunnelSshPids before return $true'

Assert (
    ($sh -match '(?s)wait_for_tunnel_up\(\)\s*\{.*?local_r_not_owned') -or
    ($sh -match '(?s)poll_tunnel_with_progress\(\)\s*\{.*?local_r_not_owned')
) 'Mac wait/poll has local_r_not_owned'
Assert ($sh -match 'get_local_tunnel_ssh_pids') 'Mac get_local_tunnel_ssh_pids present'

# --- S6 A-E encoded as static/source contracts (live quotes = Task 8) ---
Write-Host '-- S6 A-E source contracts --' -ForegroundColor White

# A: Second Connect logs foreign_owner_cannot_bind (Ensure and/or bg_init)
Assert (
    ($gm -match 'reseed_skip reason=foreign_owner_cannot_bind') -and
    ($win -match 'bg_init_reseed_skip reason=foreign_owner_cannot_bind') -and
    ($sh -match 'reseed_skip reason=foreign_owner_cannot_bind')
) 'S6-A: Win Ensure + bg_init + Mac emit foreign_owner_cannot_bind skip'

# B: Under Gap skip, no proxy-reseed kill (gate returns before killing stale bg)
Assert ($reseedKill -match 'return \$false') 'S6-B: ProxyReseedShouldKill can return false (keep -R)'
Assert ($ens -match 'Test-ProxyReseedShouldKill') 'S6-B: Ensure uses ProxyReseedShouldKill chokepoint'
# Claim/CanClaim must NOT live inside ReseedRaw predicate
$reseedRaw = Get-FunctionSource -Content $gm -Name 'Test-TunnelNeedsProxyReseed'
Assert ($reseedRaw -notmatch 'Claim-CursorProxyOwner|Test-CanClaimCursorProxyOwner') `
    'S6-B: ReseedRaw stays Claim/CanClaim-free (gate at caller)'

# C: After port still busy, refuse_spawn/rebind or Wait local_r_not_owned — not blind TUNNEL_WAIT ok
Assert ($gm -match 'refuse_spawn reason=stale_port_busy') 'S6-C: Win refuse_spawn stale_port_busy'
Assert ($sh -match 'refuse_spawn reason=stale_port_busy') 'S6-C: Mac refuse_spawn stale_port_busy'
Assert ($ens -match 'Test-StaleForwardStillBusyAbort|stale_port_busy') `
    'S6-C: Ensure still-busy abort before spawn'
Assert ($waitFn -match 'TUNNEL_WAIT ok=0 attempt=.*reason=local_r_not_owned') `
    'S6-C: Wait logs ok=0 local_r_not_owned (not false ok=1)'

# D: service_dead release + stale_non_connect adopt path
Assert ($gm -match 'released reason=service_dead') 'S6-D: Win released reason=service_dead'
Assert ($sh -match 'released reason=service_dead') 'S6-D: Mac released reason=service_dead'
Assert ($gm -match 'stale_non_connect') 'S6-D: Win Claim stale_non_connect adopt'
Assert ($sh -match 'stale_non_connect') 'S6-D: Mac Claim stale_non_connect adopt'
Assert ($gm -match 'TotalSeconds\s*-ge\s*60|SERVICE_DEAD_SEC\s*=\s*60|deadSec\s*=\s*60') `
    'S6-D: SERVICE_DEAD_SEC locked at 60s'

# E: Healthy single-window still gets -L when xray up (no over-skip)
Assert ($gm -match 'proxy_leg=-L|proxy_leg=\$leg|-L.*19080|Add-TunnelProxyLocalArgs|Build-TunnelProxy') `
    'S6-E: Win still wires proxy -L path'
Assert (
    ($gm -match 'Complete-CursorProxyAfterTunnel') -and
    ($ens -match 'Complete-CursorProxyAfterTunnel' -or $gm -match 'proxy_skip')
) 'S6-E: Complete-CursorProxyAfterTunnel / proxy path retained'
# Gap skip must still Complete after keep -R (S1 MUST)
Assert ($ens -match 'foreign_owner_cannot_bind[\s\S]{0,400}Complete-CursorProxyAfterTunnel|Test-ProxyReseedShouldKill[\s\S]{0,800}Complete-CursorProxyAfterTunnel') `
    'S6-E: Ensure Gap/keep path still reaches Complete-CursorProxyAfterTunnel'

Write-Host ''
if ($Fail -gt 0) {
    Write-Host ("incident-gap-replay-contract: {0} passed, {1} FAILED" -f $Pass, $Fail) -ForegroundColor Red
    exit 1
}
Write-Host ("All incident-gap-replay-contract tests passed ({0} asserts)." -f $Pass) -ForegroundColor Green
exit 0
