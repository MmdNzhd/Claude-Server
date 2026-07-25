# test-tunnel-tcp-state-cache.ps1 - short-TTL reuse of the acquire-batch tcp verdict
# Callers: scripts/client/tests/run-all.ps1
# The acquire batch probe learns every candidate port's open/closed state in one ssh. The same
# port is then re-examined by the push-conf safety gate and the ENSURE_TUNNEL stale check - each a
# fresh ~1.4s one-shot ssh on Windows (no ControlMaster). A short-TTL cache lets those opt-in
# callers reuse the batch verdict. This test extracts the real functions and asserts a fresh cache
# entry is served WITHOUT an ssh probe, while a miss/expiry falls back to a live probe.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Tunnel tcp-state cache ===' -ForegroundColor Cyan
Write-Host ''

$gm = Get-Content (Get-ClientFile 'git-mode.ps1') -Raw

# --- Source-level guards -------------------------------------------------------------------
Assert ($gm -match 'function Set-TunnelTcpState')   'Set-TunnelTcpState defined'
Assert ($gm -match 'function Clear-TunnelTcpState') 'Clear-TunnelTcpState defined'
$fnProbe = Get-FunctionSource -Content $gm -Name 'Test-TunnelPortTcpOpen'
Assert ($fnProbe -match '\[int\]\$MaxCacheAgeMs') 'Test-TunnelPortTcpOpen accepts -MaxCacheAgeMs'
Assert ($fnProbe -match 'cache_hit') 'probe short-circuits on fresh cache entry'
$fnBatch = Get-FunctionSource -Content $gm -Name 'Get-ServerOpenTunnelPorts'
Assert ($fnBatch -match 'Set-TunnelTcpState') 'acquire batch seeds the tcp-state cache'
$fnPush = Get-FunctionSource -Content $gm -Name 'Push-ServerConnectConf'
Assert ($fnPush -match 'Test-TunnelPortTcpOpen -TargetPort .*-MaxCacheAgeMs') 'push-conf gate reuses cached verdict'
Assert ($gm -match 'Clear-TunnelTcpState -Port \(\[int\]\$Port\)') 'cache cleared after tunnel spawn'

# --- Functional cache behavior using the REAL extracted functions --------------------------
$script:sshCount = 0
function SshX { param($cmd) $script:sshCount++; return 'closed' }
function Write-GitModeLog { param($m, $lvl) }
. ([ScriptBlock]::Create((Get-FunctionSource -Content $gm -Name 'Set-TunnelTcpState')))
. ([ScriptBlock]::Create((Get-FunctionSource -Content $gm -Name 'Clear-TunnelTcpState')))
. ([ScriptBlock]::Create($fnProbe))

$script:TunnelTcpStateCache = @{}

# Fresh entry -> served from cache, no ssh.
Set-TunnelTcpState -Port 20028 -Open $false
$script:sshCount = 0
$r1 = Test-TunnelPortTcpOpen -TargetPort 20028 -MaxCacheAgeMs 8000
Assert ($r1 -eq $false) 'cache hit returns cached verdict (closed)'
Assert ($script:sshCount -eq 0) 'cache hit issues ZERO ssh probes'

# No opt-in -> always probes live.
$script:sshCount = 0
$null = Test-TunnelPortTcpOpen -TargetPort 20028
Assert ($script:sshCount -eq 1) 'default (no MaxCacheAgeMs) probes live'

# Expired entry -> miss -> live probe.
$script:TunnelTcpStateCache['20028'] = @{ Open = $false; At = ((Get-Date).AddSeconds(-30)) }
$script:sshCount = 0
$null = Test-TunnelPortTcpOpen -TargetPort 20028 -MaxCacheAgeMs 8000
Assert ($script:sshCount -eq 1) 'expired entry falls back to a live probe'

# Clear removes the entry.
Set-TunnelTcpState -Port 20028 -Open $false
Clear-TunnelTcpState -Port 20028
Assert (-not $script:TunnelTcpStateCache.ContainsKey('20028')) 'Clear-TunnelTcpState removes the entry'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
