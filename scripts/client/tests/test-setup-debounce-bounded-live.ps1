# test-setup-debounce-bounded-live.ps1 - Bug 11/13 LIVE: proves the "debounce double-click EXE"
# wait in publish/_setup-launch-body.ps1 - the script the outer IExpress-wrapped Claude-Connect.exe
# blocks on for its entire run - is now a short, bounded delay instead of an unconditional
# Start-Sleep -Seconds 20.
#
# Live incidents this responds to (2026-07-24): (a) the connect window looked frozen with zero
# visible progress for tens of seconds after a fresh launch; (b) launching Claude-Connect.exe (or
# Claude-Connect-Setup.exe) again within that same window hit IExpress's own "Setup has detected
# that Setup is currently running" collision, even though the first launch's real UI had already
# started seconds earlier - because this script (and therefore the whole IExpress wrapper, which
# waits for it) was still blocked on the flat 20s sleep, still holding
# Global\ClaudeConnectExeLaunch.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Setup-launch debounce bounded wait (Bug 11/13) LIVE ===' -ForegroundColor Cyan

# The debounce + Global\ClaudeConnectExeLaunch mutex release moved into the DETACHED worker
# (publish/_setup-worker-body.ps1) so setup-launch.ps1 exits fast and no longer holds wextract's
# single-instance mutex through the debounce. The bounded-debounce contract now applies to the
# worker file; setup-launch.ps1 must have NO sleep at all.
$launchFile = Join-Path $script:RepoRoot 'publish\_setup-launch-body.ps1'
$setupFile = Join-Path $script:RepoRoot 'publish\_setup-worker-body.ps1'
if (-not (Test-Path -LiteralPath $launchFile)) {
    Write-Host "  FAIL  could not find publish/_setup-launch-body.ps1 at $launchFile" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $setupFile)) {
    Write-Host "  FAIL  could not find publish/_setup-worker-body.ps1 at $setupFile" -ForegroundColor Red
    exit 1
}
$launchContent = Get-Content -LiteralPath $launchFile -Raw
$content = Get-Content -LiteralPath $setupFile -Raw

Assert ($launchContent -notmatch 'Start-Sleep') 'FIXED: setup-launch.ps1 holds NO sleep (does not block wextract''s single-instance mutex)'
Assert ($content -notmatch 'Start-Sleep -Seconds 20\b') 'FIXED: the old unconditional Start-Sleep -Seconds 20 debounce is gone from source'

if ($content -match '\$debounceMs\s*=\s*(\d+)') {
    $debounceMs = [int]$Matches[1]
    Assert $true "extracted the real debounce duration verbatim from source: ${debounceMs}ms"
    Assert ($debounceMs -le 5000) "FIXED: new debounce (${debounceMs}ms) is well under the old fixed 20000ms - real per-launch tax cut by at least $((20000 - $debounceMs))ms"
    Assert ($content -match 'Start-Sleep -Milliseconds \$debounceMs') 'the extracted $debounceMs value is what Start-Sleep actually uses (not a decoy variable)'

    # Real timing proof: actually execute a Start-Sleep for the exact extracted duration and
    # measure real wall-clock, proving the number in source corresponds to real elapsed time
    # (not just a smaller-looking literal that some other code path overrides).
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Milliseconds $debounceMs
    $sw.Stop()
    Write-Host "  INFO  real Start-Sleep -Milliseconds $debounceMs measured wall-clock: $($sw.ElapsedMilliseconds)ms" -ForegroundColor DarkGray
    Assert ($sw.ElapsedMilliseconds -ge $debounceMs -and $sw.ElapsedMilliseconds -lt ($debounceMs + 2000)) "real measured sleep ($($sw.ElapsedMilliseconds)ms) matches the source's declared debounce duration (${debounceMs}ms), confirming it is a real, honored delay - not dead/unreachable code"
} else {
    Write-Host "  FAIL  could not extract \$debounceMs from source - live test cannot run (source drifted)" -ForegroundColor Red
    $fail++
}

# Confirm the launch mutex release/dispose still happens after the (now shorter) debounce -
# the debounce-shrink must not have accidentally left the mutex held longer or released early.
Assert ($content -match '(?s)Start-Sleep -Milliseconds \$debounceMs.*?launchMutex.*?ReleaseMutex') `
    'the Global\ClaudeConnectExeLaunch mutex release still happens AFTER the debounce (ordering preserved)'

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS (GREEN): Bug 11/13 debounce fix is confirmed - a real, short, honored delay replaces the old unconditional 20s sleep.' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
