# test-launch-recovery-reachable-live.ps1 - Bug 8 / B11 LIVE: proves Get-CursorLaunchWindowPlan's
# UseNewWindow = AgentHome -or HasProfileWindow ONLY (orphanHelpers alone => UseNewWindow=false).
# The $preservedOpenWindows guard reproduced from editor-launch.ps1's real current formula
# (~line 2237: `$preservedOpenWindows = ($EditorCmd -eq 'cursor' -and ($agentHome -or
# $useNewWindow) -and ($profileProcCount -gt 0))`) is evaluated against the REAL returned
# .UseNewWindow. B11: orphan-helpers-only must NOT request --new-window (litter fix).
# This test calls the REAL extracted Get-CursorLaunchWindowPlan function (dot-sourced verbatim out
# of editor-launch.ps1 via Get-FunctionSource - not a re-implementation) across all 12 real
# (AgentHome, HasProfileWindow, ProfileProcCount) combinations, then algebraically reconstructs
# $preservedOpenWindows from each REAL returned .UseNewWindow using production's exact formula.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Launch-recovery reachability (Bug 8 / B11) #P2 (LIVE) ===' -ForegroundColor Cyan

$editorLaunchFile = Get-ClientFile 'editor-launch.ps1'
$content = Get-Content $editorLaunchFile -Raw
$fnName = 'Get-CursorLaunchWindowPlan'
$src = Get-FunctionSource -Content $content -Name $fnName
if (-not $src) {
    Write-Host "  FAIL  could not extract $fnName from editor-launch.ps1 - live test cannot run (source drifted)" -ForegroundColor Red
    exit 1
}
. ([scriptblock]::Create($src))
Write-Host "  extracted real $fnName from $editorLaunchFile (byte length $($src.Length))" -ForegroundColor DarkGray

# Bug 8 GREEN-phase update: rather than hardcoding either the OLD (buggy, $useNewWindow-based)
# or NEW (fixed, $hasProfileWindow-based) formula text, extract whatever the current production
# $preservedOpenWindows line actually says and Invoke-Expression it per combination, with every
# variable name that formula could reference already in scope ($EditorCmd, $agentHome,
# $hasProfileWindow, $useNewWindow, $profileProcCount). This keeps the test allergic to source
# drift (still fails loudly if the line disappears) without needing hand-maintenance every time a
# legitimate fix reformulates the guard - exactly the same principle already used elsewhere in
# this test suite (test-window-title-site-tag-live.ps1 extracts its regex needle the same way).
$preservedFormulaLine = ($content -split "`r?`n") | Where-Object { $_ -match '\$preservedOpenWindows\s*=' } | Select-Object -First 1
Assert ($null -ne $preservedFormulaLine -and $preservedFormulaLine.Trim()) 'production $preservedOpenWindows formula line found in source (not silently missing)'
$preservedFormulaExpr = $preservedFormulaLine.Trim()
Write-Host "  live-extracted `$preservedOpenWindows formula: $preservedFormulaExpr" -ForegroundColor DarkGray

# Real 12 calls: full (AgentHome, HasProfileWindow) x2x2 crossed with ProfileProcCount in {0,1,5}.
$bools = @($false, $true)
$counts = @(0, 1, 5)
$results = @()
foreach ($agentHome in $bools) {
    foreach ($hasProfileWindow in $bools) {
        foreach ($profileProcCount in $counts) {
            $plan = Get-CursorLaunchWindowPlan -AgentHome $agentHome -HasProfileWindow $hasProfileWindow -ProfileProcCount $profileProcCount
            $EditorCmd = 'cursor'
            $useNewWindow = $plan.UseNewWindow
            # Bug 14 fix (2026-07-24): production now gates on a freshly-queried $mainCount
            # instead of the stale entry-time $hasProfileWindow. For this algebraic sweep (no
            # real process is spawned here - that live proof is test-window-kill-staleness-live.ps1),
            # $mainCount stands in for "a fresh re-check would currently find" and is deliberately
            # set equal to $hasProfileWindow's own boolean-as-count, since this test's purpose is
            # bug 8's reachability matrix, not bug 14's freshness - do not conflate the two.
            $mainCount = if ($hasProfileWindow) { 1 } else { 0 }
            Invoke-Expression $preservedFormulaExpr
            $recoverySkipFires = ($EditorCmd -eq 'cursor' -and $profileProcCount -gt 0 -and $preservedOpenWindows)
            $recoveryBlockGuard = ($EditorCmd -eq 'cursor' -and $profileProcCount -gt 0)
            $results += [pscustomobject]@{
                AgentHome            = $agentHome
                HasProfileWindow     = $hasProfileWindow
                ProfileProcCount     = $profileProcCount
                UseNewWindow         = $plan.UseNewWindow
                OrphanHelpers        = $plan.OrphanHelpers
                Reason               = $plan.Reason
                PreservedOpenWindows = $preservedOpenWindows
                RecoverySkipFires    = $recoverySkipFires
                RecoveryBlockGuard   = $recoveryBlockGuard
            }
        }
    }
}

Write-Host ''
Write-Host '--- 12 real Get-CursorLaunchWindowPlan calls + reconstructed guard state ---' -ForegroundColor Cyan
$results | Format-Table AgentHome, HasProfileWindow, ProfileProcCount, UseNewWindow, OrphanHelpers, Reason, PreservedOpenWindows, RecoverySkipFires -AutoSize | Out-String | Write-Host

Write-Host '--- Algebraic proof: UseNewWindow true only when AgentHome or HasProfileWindow; orphan-only is false ---' -ForegroundColor Cyan
$positiveCountRows = $results | Where-Object { $_.ProfileProcCount -gt 0 }
Assert ($positiveCountRows.Count -eq 8) "8 of 12 real calls have ProfileProcCount -gt 0 (2x2x2 counts {1,5}), got $($positiveCountRows.Count)"
foreach ($r in $positiveCountRows) {
    $expectedUseNew = ($r.AgentHome -or $r.HasProfileWindow)
    Assert ($r.UseNewWindow -eq $expectedUseNew) ("REAL call UseNewWindow=$($r.UseNewWindow) expected=$expectedUseNew AgentHome=$($r.AgentHome) HasProfileWindow=$($r.HasProfileWindow) ProfileProcCount=$($r.ProfileProcCount) reason=$($r.Reason)")
}

Write-Host ''
Write-Host '--- Bug 8 fix proof: recovery-skip must fire ONLY for a real visible window/agent-home, never for orphan-helpers-only ---' -ForegroundColor Cyan
foreach ($r in $positiveCountRows) {
    # Correct semantics: only an ACTUAL visible open window (HasProfileWindow) or agent-home
    # justifies protecting it from the cold-launch recovery kill - orphan helpers alone (no
    # window) must NOT be protected, or the recovery path designed for exactly that case can
    # never run (this was the bug: it used the broader UseNewWindow, contaminated by
    # OrphanHelpers, instead of the narrower HasProfileWindow/AgentHome signal).
    $expectedPreserved = ($r.AgentHome -or $r.HasProfileWindow)
    Assert ($r.PreservedOpenWindows -eq $expectedPreserved) "REAL-derived preservedOpenWindows=$($r.PreservedOpenWindows) is correct ($expectedPreserved expected: agentHome=$($r.AgentHome) OR hasProfileWindow=$($r.HasProfileWindow)) for AgentHome=$($r.AgentHome) HasProfileWindow=$($r.HasProfileWindow) ProfileProcCount=$($r.ProfileProcCount)"
    if ($expectedPreserved) {
        Assert ($r.RecoverySkipFires -eq $true) "recovery-skip correctly FIRES (a real open window or agent-home exists to protect) for AgentHome=$($r.AgentHome) HasProfileWindow=$($r.HasProfileWindow) ProfileProcCount=$($r.ProfileProcCount)"
    } else {
        Assert ($r.RecoverySkipFires -eq $false) "recovery-skip correctly does NOT fire (orphan helpers only - nothing visible to protect) -> soft_stop_profile/cold_launch recovery block is now REACHABLE for AgentHome=$($r.AgentHome) HasProfileWindow=$($r.HasProfileWindow) ProfileProcCount=$($r.ProfileProcCount)"
    }
}

Write-Host ''
Write-Host '--- Crux case: AgentHome=false HasProfileWindow=false ProfileProcCount=5 (orphan helpers only) ---' -ForegroundColor Cyan
$cruxRow = $results | Where-Object { $_.AgentHome -eq $false -and $_.HasProfileWindow -eq $false -and $_.ProfileProcCount -eq 5 } | Select-Object -First 1
Assert ($null -ne $cruxRow) 'crux row present among the 12 real results'
Assert ($cruxRow.OrphanHelpers -eq $true) 'crux case: OrphanHelpers=true'
Assert ($cruxRow.UseNewWindow -eq $false) 'crux case B11: UseNewWindow=false for orphan-helpers-only'
Assert ($cruxRow.PreservedOpenWindows -eq $false) 'crux case: preservedOpenWindows=false'
Assert ($cruxRow.RecoverySkipFires -eq $false) 'crux case: recovery-skip does not fire (cold-launch reachable)'

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'ALL PASS (B11): UseNewWindow = AgentHome -or HasProfileWindow ONLY; orphan-helpers-only yields UseNewWindow=false; recovery-skip protects real windows/agent-home only.' -ForegroundColor Green
    exit 0
}
Write-Host "$fail FAIL (unexpected - re-verify against current source; if the formula legitimately changed again, confirm the new semantics before assuming regression)" -ForegroundColor Red
exit 1
