# test-job-detach-survives-close-live.ps1 - Bug 5 LIVE: proves that today, a process assigned
# to the shared KILL_ON_JOB_CLOSE sidecar/tunnel job object is ALWAYS killed the instant the job's
# last handle closes (e.g. when connect.ps1 exits normally) - there is currently no way to keep a
# specific member (like the reverse tunnel, when keepTunnelForEditor is true) alive across that
# close. This is real Win32 Job Object + DuplicateHandle behavior, not source-text pattern
# matching: it spawns real decoy processes, assigns them to a real job, and observes real process
# death via Process.HasExited.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Bug 5: job-object member cannot survive job-handle close (LIVE) ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'windows\cursor-proxy-sidecar.ps1') -Raw
foreach ($n in @('Initialize-CursorProxySidecarJob', 'Add-CursorProxySidecarJobProcess', 'Stop-CursorProxySidecarJob')) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}

# Bug 5's fix will add this function (Detach-CursorProxySidecarJobProcess or similarly named) to
# cursor-proxy-sidecar.ps1. Detect whichever name the fix lands with so this test stays GREEN
# post-fix without needing another edit; today (pre-fix) none of these exist, which is itself
# part of the RED evidence.
$detachFnName = $null
foreach ($candidate in @('Detach-CursorProxySidecarJobProcess', 'Detach-ProcessFromKillOnCloseJob', 'Preserve-CursorProxySidecarJobProcess')) {
    if ([regex]::Match($content, "function\s+$candidate\b").Success) { $detachFnName = $candidate; break }
}
if ($detachFnName) {
    $detachSrc = Get-FunctionSource -Content $content -Name $detachFnName
    . ([scriptblock]::Create($detachSrc))
    Write-Host "  INFO  found detach primitive: $detachFnName (post-fix state)" -ForegroundColor DarkGray
} else {
    Write-Host '  INFO  no detach primitive found yet in cursor-proxy-sidecar.ps1 (pre-fix state - expected today)' -ForegroundColor DarkGray
}

function Start-Decoy {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 120') -WindowStyle Hidden -PassThru
}

Write-Host ''
Write-Host '--- Scenario A: current behavior - ALL members die when job handle closes (baseline) ---' -ForegroundColor Yellow
$memberA = $null
try {
    $memberA = Start-Decoy
    Start-Sleep -Milliseconds 400
    Assert (-not $memberA.HasExited) 'Scenario A: decoy member process actually started'
    Add-CursorProxySidecarJobProcess -Process $memberA
    Stop-CursorProxySidecarJob
    $deadline = (Get-Date).AddSeconds(6)
    $dead = $false
    while ((Get-Date) -lt $deadline) {
        if ($memberA.HasExited) { $dead = $true; break }
        Start-Sleep -Milliseconds 200
    }
    Assert $dead 'Scenario A: an ordinary job-assigned member is killed the instant the job handle closes (confirms KILL_ON_JOB_CLOSE fires on real close, baseline sanity check)'
} finally {
    if ($memberA -and -not $memberA.HasExited) { try { $memberA.Kill() } catch {} }
}

Write-Host ''
Write-Host '--- Scenario B: the actual bug - a member we WANT to survive (tunnel with keepTunnelForEditor) still dies today ---' -ForegroundColor Yellow
$memberB = $null
$siblingB = $null
try {
    $memberB = Start-Decoy   # stands in for the reverse-tunnel ssh.exe process
    $siblingB = Start-Decoy  # stands in for a sidecar relay/watchdog process in the same job
    Start-Sleep -Milliseconds 400
    Assert (-not $memberB.HasExited) 'Scenario B: tunnel-stand-in decoy actually started'
    Assert (-not $siblingB.HasExited) 'Scenario B: sibling (relay/watchdog stand-in) decoy actually started'
    Add-CursorProxySidecarJobProcess -Process $memberB
    Add-CursorProxySidecarJobProcess -Process $siblingB

    $detached = $false
    if ($detachFnName) {
        $detachCmd = Get-Command $detachFnName -ErrorAction SilentlyContinue
        if ($detachCmd) {
            $detached = [bool](& $detachFnName -Process $memberB)
        }
    }
    Write-Host "  INFO  detach attempted=$([bool]$detachFnName) detach_reported_ok=$detached" -ForegroundColor DarkGray

    # This is the connect.ps1 exit simulation: close OUR OWN handle to the job (what happens
    # automatically when connect.ps1's process exits normally after the keepTunnelForEditor
    # branch decided to skip Stop-SessionTunnelCleanup).
    Stop-CursorProxySidecarJob

    $deadline = (Get-Date).AddSeconds(6)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    $survivedAfterClose = (-not $memberB.HasExited)

    if ($detachFnName -and $detached) {
        Assert $survivedAfterClose 'Scenario B (post-fix): the DETACHED tunnel-stand-in process survives the job handle close - the bug 5 fix works'
        Assert (-not $siblingB.HasExited) 'Scenario B (post-fix): the sibling process ALSO survives (job as a whole was kept alive by the one duplicated handle, not destroyed) - matches documented DuplicateHandle/Job-Object semantics'
    } else {
        Write-Host "  INFO  survived_after_close=$survivedAfterClose (expected False today - this IS bug 5: no way exists yet to keep a wanted member alive across job-handle close)" -ForegroundColor DarkGray
        Assert (-not $survivedAfterClose) 'Scenario B (pre-fix, RED): with no detach primitive available, the tunnel-stand-in process is ALSO killed on job-handle close, even though this scenario represents keepTunnelForEditor=true wanting it to survive - this IS Bug 5'
    }
} finally {
    foreach ($p in @($memberB, $siblingB)) {
        if ($p -and -not $p.HasExited) { try { $p.Kill() } catch {} }
    }
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
