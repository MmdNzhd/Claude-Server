# test-sidecar-boot-reap-live.ps1 - LIVE: proves the real Invoke-CursorProxySidecarBootReap
# (scripts/client/windows/cursor-proxy-sidecar.ps1) correctly distinguishes a lease file
# pointing at a genuinely-still-running process (must NOT reap) from one pointing at a
# genuinely-dead PID (must reap) - using REAL spawned/killed processes and a REAL lease file,
# while a local stub shadows Stop-CursorProxySidecarWatchdog so the real production watchdog
# (and its real lease file, once restored) is never actually touched.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Sidecar boot reap orphan-detection (LIVE) ===' -ForegroundColor Cyan

# --- Safety #1: snapshot the REAL lease file before this test ever touches that path -------
$leasePath = Join-Path $env:TEMP 'claude-connect-sidecar-watchdog.lease'
$leaseExistedBefore = Test-Path -LiteralPath $leasePath
$leaseBackupPath = $null
if ($leaseExistedBefore) {
    $stamp = Get-Date -Format 'yyyyMMddHHmmssfff'
    $leaseBackupPath = "$leasePath.bak-$stamp"
    Copy-Item -LiteralPath $leasePath -Destination $leaseBackupPath -Force
    Write-Host "  [safety] real lease existed - backed up to $leaseBackupPath before any write" -ForegroundColor DarkYellow
} else {
    Write-Host '  [safety] no real lease file present - will ensure it stays absent afterward' -ForegroundColor DarkYellow
}

$decoyAPid = $null
$decoyBPid = $null

try {
    # --- Safety #2: define OUR OWN stub for Stop-CursorProxySidecarWatchdog BEFORE loading
    # the real Invoke-CursorProxySidecarBootReap source. The real function resolves this by
    # bare name at call time (see sanity check below), so whichever definition exists in this
    # process's scope is what actually runs - never the real kill/mutex/TEMP-cleanup logic.
    $script:StopWatchdogCallCount = 0
    function Stop-CursorProxySidecarWatchdog {
        $script:StopWatchdogCallCount++
        Write-Host "  [stub] Stop-CursorProxySidecarWatchdog invoked (call #$script:StopWatchdogCallCount) - real watchdog NOT touched" -ForegroundColor DarkGray
    }

    $content = Get-Content (Get-ClientFile 'windows\cursor-proxy-sidecar.ps1') -Raw
    $funcName = 'Invoke-CursorProxySidecarBootReap'
    $funcSrc = Get-FunctionSource -Content $content -Name $funcName
    if (-not $funcSrc) {
        Write-Host "  FAIL  could not extract $funcName - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }

    # Verify (before relying on it) that the real function calls Stop-CursorProxySidecarWatchdog
    # by bare name, Get-Command-gated - not via a module-qualified path or a compiled cmdlet -
    # which is exactly what makes our local stub shadow it safely.
    $bareCallOk = $funcSrc -match 'Get-Command\s+Stop-CursorProxySidecarWatchdog\s+-ErrorAction\s+SilentlyContinue[\s\S]*?try\s*\{\s*Stop-CursorProxySidecarWatchdog\s*\}\s*catch'
    Assert $bareCallOk 'Invoke-CursorProxySidecarBootReap calls Stop-CursorProxySidecarWatchdog by bare, Get-Command-gated name (safe to shadow with a local stub)'
    if (-not $bareCallOk) {
        Write-Host '  FAIL  bare-name call could not be confirmed - refusing to proceed (would risk touching the real watchdog)' -ForegroundColor Red
        exit 1
    }

    # Load ONLY the one extracted function - the real Stop-CursorProxySidecarWatchdog body is
    # never extracted, never dot-sourced, and never defined anywhere in this process.
    . ([scriptblock]::Create($funcSrc))
    Assert (Get-Command Invoke-CursorProxySidecarBootReap -ErrorAction SilentlyContinue) 'real Invoke-CursorProxySidecarBootReap loaded standalone from source'

    # === Case A: lease points at a genuinely-still-running real process -> must NOT reap =====
    $procA = Start-Process powershell -ArgumentList '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 60' -WindowStyle Hidden -PassThru
    $decoyAPid = $procA.Id
    Start-Sleep -Milliseconds 300
    Assert ([bool](Get-Process -Id $decoyAPid -ErrorAction SilentlyContinue)) "decoy A (pid=$decoyAPid) is a real, running process"

    ("{0}|{1}" -f $decoyAPid, (Get-Date -Format o)) | Set-Content -LiteralPath $leasePath -Encoding ASCII
    Assert (Test-Path -LiteralPath $leasePath) 'real lease file written for case A (live-running pid)'

    $resultA = Invoke-CursorProxySidecarBootReap
    Assert (-not $resultA) 'case A: still-running lease pid -> Invoke-CursorProxySidecarBootReap does NOT report a reap/orphan condition'
    Assert ($script:StopWatchdogCallCount -eq 0) 'case A: stub Stop-CursorProxySidecarWatchdog was NOT called (call count still 0)'

    try { Stop-Process -Id $decoyAPid -Force -ErrorAction SilentlyContinue } catch {}
    $decoyAPid = $null

    # === Case B: lease points at a genuinely-dead real pid -> must reap ======================
    $procB = Start-Process powershell -ArgumentList '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 60' -WindowStyle Hidden -PassThru
    $decoyBPid = $procB.Id
    Start-Sleep -Milliseconds 300
    Assert ([bool](Get-Process -Id $decoyBPid -ErrorAction SilentlyContinue)) "decoy B (pid=$decoyBPid) is a real, running process before being killed"

    Stop-Process -Id $decoyBPid -Force -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(5)
    $trulyDead = $false
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Id $decoyBPid -ErrorAction SilentlyContinue)) { $trulyDead = $true; break }
        Start-Sleep -Milliseconds 150
    }
    Assert $trulyDead "decoy B (pid=$decoyBPid) confirmed truly gone via Get-Process before writing the dead-pid lease"

    ("{0}|{1}" -f $decoyBPid, (Get-Date -Format o)) | Set-Content -LiteralPath $leasePath -Encoding ASCII
    Assert (Test-Path -LiteralPath $leasePath) 'real lease file (re)written for case B (dead pid)'

    $resultB = Invoke-CursorProxySidecarBootReap
    Assert ($resultB -eq $true) 'case B: dead lease pid -> Invoke-CursorProxySidecarBootReap DOES report/act on the orphan condition'
    Assert ($script:StopWatchdogCallCount -eq 1) 'case B: stub Stop-CursorProxySidecarWatchdog was called exactly once (real watchdog kill/mutex/TEMP logic never ran)'
    $decoyBPid = $null
} finally {
    foreach ($p in @($decoyAPid, $decoyBPid)) {
        if ($p) { try { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } catch {} }
    }
    # Restore the real lease file (or its absence) exactly as found - even if an assertion threw.
    if ($leaseExistedBefore -and $leaseBackupPath -and (Test-Path -LiteralPath $leaseBackupPath)) {
        Copy-Item -LiteralPath $leaseBackupPath -Destination $leasePath -Force
        Remove-Item -LiteralPath $leaseBackupPath -Force -ErrorAction SilentlyContinue
        Write-Host '  [safety] real lease file restored to its original pre-test content' -ForegroundColor DarkYellow
    } elseif (-not $leaseExistedBefore) {
        if (Test-Path -LiteralPath $leasePath) { Remove-Item -LiteralPath $leasePath -Force -ErrorAction SilentlyContinue }
        Write-Host '  [safety] real lease file left absent (matches pre-test state)' -ForegroundColor DarkYellow
    }
}

if ($fail -eq 0) { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
