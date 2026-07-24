# test-logsync-fast-timeout.ps1 - #P7 Sync-ConnectLogToServer was observed blocking the
# interactive boot path 30-60s+ (session start -> "Laptop SSH key", and again around
# "Server setup") because its mkdir/scp/cat probe chain ran fully sequentially with
# multi-second-to-20s per-call SSH timeouts. Non-Force syncs are best-effort telemetry and
# must fail fast; -Force syncs (day rollover, unhandled-error flush, exit) keep long budgets.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Log-sync fast-timeout budget #P7 (static) ===' -ForegroundColor Cyan

$s = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw

Assert ($s -match 'LogSyncFastProbeMs') 'fast probe budget variable defined'
Assert ($s -match 'LogSyncFastMkdirMs') 'fast mkdir budget variable defined'
Assert ($s -match 'LogSyncFastScpMs') 'fast scp budget variable defined'
Assert ($s -match 'LogSyncFastCatMs') 'fast cat budget variable defined'
Assert ($s -match [regex]::Escape('if ($Force) { 10000 } else { 2500 }')) 'probe budget is short (2.5s) unless -Force'
Assert ($s -match [regex]::Escape('if ($Force) { 12000 } else { 3000 }')) 'mkdir budget is short (3s) unless -Force'
Assert ($s -match [regex]::Escape('if ($Force) { 20000 } else { 4000 }')) 'scp budget is short (4s) unless -Force'

Assert ($s -match 'function Get-ConnectRemoteLogByteSize') 'Get-ConnectRemoteLogByteSize defined'
$probeIdx = $s.IndexOf('function Get-ConnectRemoteLogByteSize')
if ($probeIdx -ge 0) {
    $probeBody = $s.Substring($probeIdx, [Math]::Min(1200, $s.Length - $probeIdx))
    Assert ($probeBody -match '\[int\]\$TimeoutMs\s*=\s*10000') 'probe helper has an overridable TimeoutMs param (default unchanged)'
    Assert ($probeBody -match '-TimeoutMs \$TimeoutMs') 'probe helper forwards the caller-supplied timeout to Invoke-ConnectLogProcTimed'
}

Assert ($s -match 'function Test-ConnectLogChunkAlreadyRemote') 'Test-ConnectLogChunkAlreadyRemote defined'
$chunkIdx = $s.IndexOf('function Test-ConnectLogChunkAlreadyRemote')
if ($chunkIdx -ge 0) {
    $chunkBody = $s.Substring($chunkIdx, [Math]::Min(1200, $s.Length - $chunkIdx))
    Assert ($chunkBody -match '\[int\]\$TimeoutMs\s*=\s*12000') 'chunk-hash helper has an overridable TimeoutMs param (default unchanged)'
}

$syncIdx = $s.IndexOf('function Sync-ConnectLogToServer')
Assert ($syncIdx -ge 0) 'Sync-ConnectLogToServer defined'
if ($syncIdx -ge 0) {
    $nextFn = $s.IndexOf("`nfunction ", $syncIdx + 40)
    $body = if ($nextFn -gt $syncIdx) { $s.Substring($syncIdx, $nextFn - $syncIdx) } else { $s.Substring($syncIdx) }
    Assert ($body -match [regex]::Escape('Get-ConnectRemoteLogByteSize -Target $target -Day $day -SshOpts $sshOpts -TimeoutMs $script:LogSyncFastProbeMs')) 'remote-size probes pass the fast budget'
    Assert ($body -match [regex]::Escape("-TimeoutMs `$script:LogSyncFastMkdirMs")) 'mkdir call uses the fast budget'
    Assert ($body -match [regex]::Escape('-TimeoutMs $script:LogSyncFastScpMs')) 'scp call uses the fast budget'
    Assert ($body -match [regex]::Escape('-TimeoutMs $script:LogSyncFastCatMs')) 'cat call uses the fast budget'
    Assert ($body -notmatch 'TimeoutMs 12000\)\s*\r?\n\s*if \(-not \$mkRes\.Ok\)') 'old hardcoded 12000ms mkdir timeout removed from mkdir call site'
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
