# test-logsync-fast-timeout.ps1 - #P7 / P0.5 Sync-ConnectLogToServer budgets.
# Non-Force syncs must clear the 8s SSH ConnectTimeout with margin (old 2.5s/3s/4s
# caps false-failed under normal latency). -Force keeps longer budgets for ERROR /
# session-end / stall escape.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Log-sync fast-timeout budget #P7/P0.5 (static) ===' -ForegroundColor Cyan

$s = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw

Assert ($s -match 'LogSyncFastProbeMs') 'fast probe budget variable defined'
Assert ($s -match 'LogSyncFastMkdirMs') 'fast mkdir budget variable defined'
Assert ($s -match 'LogSyncFastScpMs') 'fast scp budget variable defined'
Assert ($s -match 'LogSyncFastCatMs') 'fast cat budget variable defined'
Assert ($s -match [regex]::Escape('if ($Force) { 10000 } else { 8000 }')) 'probe budget >= ConnectTimeout (8s) unless -Force'
Assert ($s -match [regex]::Escape('if ($Force) { 12000 } else { 10000 }')) 'mkdir budget >= ConnectTimeout+margin unless -Force'
Assert ($s -match [regex]::Escape('if ($Force) { 20000 } else { 16000 }')) 'scp budget raised vs ConnectTimeout unless -Force'
Assert ($s -match [regex]::Escape('if ($Force) { 12000 } else { 10000 }')) 'cat budget >= ConnectTimeout+margin unless -Force'
# Old false-fail budgets must stay gone.
Assert ($s -notmatch [regex]::Escape('if ($Force) { 12000 } else { 3000 }')) 'old 3s non-Force mkdir budget removed'
Assert ($s -notmatch [regex]::Escape('if ($Force) { 20000 } else { 4000 }')) 'old 4s non-Force scp budget removed'

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
