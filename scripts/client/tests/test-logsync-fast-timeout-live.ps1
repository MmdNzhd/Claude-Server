# test-logsync-fast-timeout-live.ps1 - #P7 LIVE: the fast per-call timeout budgets used by
# Sync-ConnectLogToServer's probe/mkdir/scp/cat sub-calls must actually bound real ssh.exe
# wall-clock time against an unreachable target - not merely exist as variables in the source.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Log-sync fast-timeout budget #P7 (LIVE) ===' -ForegroundColor Cyan

$uiContent = Get-Content (Get-ClientFile 'connect-ui.ps1') -Raw
$elContent = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
foreach ($pair in @(
        @{ Content = $elContent; Name = 'Format-ProcessArgumentString' }
        @{ Content = $uiContent; Name = 'Invoke-ConnectLogProcTimed' }
        @{ Content = $uiContent; Name = 'Get-ConnectRemoteLogByteSize' }
        @{ Content = $uiContent; Name = 'Test-ConnectLogChunkAlreadyRemote' }
    )) {
    $src = Get-FunctionSource -Content $pair.Content -Name $pair.Name
    if (-not $src) {
        Write-Host "  FAIL  could not extract $($pair.Name) - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}

# RFC5737 TEST-NET-1: reserved for documentation, expected non-routable/black-holed - real TCP
# SYNs go out and get no response, which is exactly the "degraded network" case #P7 fixes.
# (Upper-bound timing is asserted; a strict lower bound is intentionally NOT asserted because
# how fast a given network/gateway rejects vs. silently drops this address varies by
# environment - the property that matters here is "never blocks past the fast budget".)
$blackHole = '192.0.2.1'
$fastProbeMs = 2500
$fastChunkMs = 2500
$sshOpts = @('-o', 'StrictHostKeyChecking=no', '-o', 'BatchMode=yes')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$size = Get-ConnectRemoteLogByteSize -Target $blackHole -Day '2026-07-24' -SshOpts $sshOpts -TimeoutMs $fastProbeMs
$sw.Stop()
Write-Host "  INFO  probe wall-clock: $($sw.ElapsedMilliseconds)ms (fast budget=$fastProbeMs ms)" -ForegroundColor DarkGray
Assert ($size -eq -1) 'probe against a black-holed host correctly reports failure (-1), never a false success'
Assert ($sw.ElapsedMilliseconds -le ($fastProbeMs + 3000)) "probe against a black-holed host returned in $($sw.ElapsedMilliseconds)ms - bounded near the $fastProbeMs ms fast budget, not the old 10-20s+ default"

$chunk = [System.Text.Encoding]::UTF8.GetBytes('live-test-chunk-payload')
$sw2 = [System.Diagnostics.Stopwatch]::StartNew()
$already = Test-ConnectLogChunkAlreadyRemote -Target $blackHole -Day '2026-07-24' -Chunk $chunk -Take $chunk.Length -SshOpts $sshOpts -TimeoutMs $fastChunkMs
$sw2.Stop()
Write-Host "  INFO  chunk-hash wall-clock: $($sw2.ElapsedMilliseconds)ms (fast budget=$fastChunkMs ms)" -ForegroundColor DarkGray
Assert ($already -eq $false) 'chunk-hash probe against a black-holed host fails closed (assumes NOT already remote - never silently drops data that should be sent)'
Assert ($sw2.ElapsedMilliseconds -le ($fastChunkMs + 3000)) "chunk-hash probe returned in $($sw2.ElapsedMilliseconds)ms - bounded near the $fastChunkMs ms fast budget"

Start-Sleep -Milliseconds 500
$leaked = @(Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match [regex]::Escape($blackHole) })
Assert ($leaked.Count -eq 0) "no orphaned ssh.exe left targeting $blackHole after both timed-out probes (found $($leaked.Count))"

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
