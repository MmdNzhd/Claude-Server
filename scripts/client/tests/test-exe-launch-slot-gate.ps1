#Requires -Version 5.1
# test-exe-launch-slot-gate.ps1 - Stage 6f: EXE setup only blocks when 10 slots full
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$Pass = 0; $Fail = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS $Msg" -ForegroundColor Green; $script:Pass++ }
    else { Write-Host "  FAIL $Msg" -ForegroundColor Red; $script:Fail++ }
}

Write-Host ""
Write-Host "=== EXE launch slot gate (Stage 6f) ==="
Write-Host ""

$bodyPath = Join-Path $RepoRoot 'publish\_setup-launch-body.ps1'
Assert (Test-Path -LiteralPath $bodyPath) '_setup-launch-body.ps1 exists'
$body = Get-Content -LiteralPath $bodyPath -Raw

# Worker: the slow update + boot + the ClaudeConnectExeLaunch double-launch gate now live in the
# detached worker so setup-launch.ps1 can exit fast and release wextract's single-instance mutex.
$workerPath = Join-Path $RepoRoot 'publish\_setup-worker-body.ps1'
Assert (Test-Path -LiteralPath $workerPath) '_setup-worker-body.ps1 exists'
$worker = Get-Content -LiteralPath $workerPath -Raw

Assert ($body -match 'function Test-ConnectUiOpen') 'defines Test-ConnectUiOpen'
Assert ($body -match 'Global\\ClaudeConnect#') 'probes Global\ClaudeConnect# slots'
Assert ($worker -match 'ClaudeConnectExeLaunch') 'ExeLaunch double-launch gate lives in the detached worker'
Assert ($body -match '10 Claude Connect') 'MessageBox/text mentions 10 Claude Connect'
Assert ($body -match 'already open') 'MessageBox/text mentions already open'

# setup-launch.ps1 must exit fast: spawn the detached worker, and NOT run the update inline.
Assert ($body -match 'setup-worker\.ps1') 'setup-launch spawns the detached setup-worker.ps1'
Assert ($body -match '`"\$workerDest`"' -or $body -match '\$workerDest`""') 'setup-launch quotes -File worker path (spaces-safe)'
Assert ($worker -match '`"\$boot`"' -or $worker -match '\$boot`""') 'worker quotes -File boot path (spaces-safe)'
Assert ($body -match 'Copy-Item -LiteralPath \$workerSrc -Destination \$workerDest -Force') 'setup-launch refreshes worker on first install/repair'
Assert ($body -match 'fast_path direct_boot') 'setup-launch fast path boots without worker'
Assert (-not ($body -match '&\s+\$upd\b')) 'setup-launch does NOT run the update inline (moved to worker - keeps wextract mutex hold short)'
Assert (-not ($body -match 'Start-Sleep')) 'setup-launch has no debounce sleep (would hold wextract mutex) - debounce moved to worker'
Assert ($worker -match 'preboot update skipped reason=manual_only') 'worker skips pre-boot update (manual menu u only)'
Assert ($worker -notmatch 'CLAUDE_CONNECT_UPDATE_YES\s*=\s*''1''') 'worker does NOT set UPDATE_YES (no EXE auto-update)'
Assert ($worker -match 'after_preboot_update=0 manual_only=1') 'worker boots UI without auto-update'
Assert ($worker -match 'manual_only') 'worker documents manual-only update policy'
Assert ($worker -match 'Test-ConnectBootPresent') 'worker never boots a folder without connect-boot.ps1'
Assert ($worker -match 'connect-boot\.ps1') 'worker starts connect-boot.ps1'

# Must NOT gate on connect.ps1/connect-boot.ps1 process CommandLine (false single-instance).
# Win32_Process is OK for portable EXE path resolve (Resolve-ConnectLaunchExe), not for UI gate.
Assert (-not ($body -match "(?i)CommandLine -match '\(\?i\)connect-boot")) 'no connect-boot CommandLine process gate'
Assert (-not ($body -match "(?i)CommandLine -match '\(\?i\)connect\.ps1")) 'no connect.ps1 CommandLine process gate'
Assert (($body -match 'Resolve-ConnectLaunchExe') -or ($body -match 'Resolve-VersionedTree')) 'portable/versioned install resolves beside double-clicked EXE'
Assert ($body -match 'function Test-ConnectUiOpen') 'UI-open gate is still a dedicated function (mutex slots)'

# Block only when zero free slots (return true iff all 10 held)
Assert ($body -match '(?i)free|slot') 'slot/free vocabulary present'
Assert (
    ($body -match 'return \(\$free -eq 0\)') -or
    ($body -match 'return \(\$freeCount -eq 0\)') -or
    ($body -match 'if \(\$free -gt 0\) \{ return \$false \}') -or
    ($body -match 'zero free') -or
    ($body -match '\$freeSlots')
) 'blocks only when zero free slots (explicit free-count gate)'

# Old false-positive MessageBox must be gone
Assert (-not ($body -match "'Claude Connect is already open\.'")) 'old single-instance MessageBox text removed'

Write-Host ""
if ($Fail -eq 0) {
    Write-Host ("All {0} contracts passed." -f $Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("{0} failed, {1} passed." -f $Fail, $Pass) -ForegroundColor Red
exit 1
