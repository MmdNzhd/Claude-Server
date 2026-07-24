# test-window-kill-staleness-live.ps1 - Bug 14 LIVE: proves Launch-RemoteEditor's post-exhaustion
# $preservedOpenWindows guard (~editor-launch.ps1:2297) now uses the FRESH $mainCount signal
# (re-queried right before this decision) instead of the STALE $hasProfileWindow signal (captured
# once at function entry, before this call's own up-to-4 attempts and up to ~40s of retries).
#
# Live incident this reproduces (2026-07-24): a genuinely open, unrelated project's Cursor window
# (real main pid, alive continuously) was NOT protected because entry-time $hasProfileWindow no
# longer reflected current reality by the time the kill decision ran - Stop-CursorServerProfileTree
# then destroyed that real window's whole process tree just to cold-launch a different project.
#
# This test compiles and launches a REAL decoy process (Name=Cursor.exe, matching the CIM filter
# production code uses) with a command line that is a genuine "main profile process" (contains the
# fake profile dir, no --type= flag) - representing "Window A, still alive right now". It then
# extracts the REAL production $preservedOpenWindows formula line (source-drift-allergic, same
# technique as test-launch-recovery-reachable-live.ps1) and evaluates it twice against the SAME
# live decoy: once with a stale $hasProfileWindow=$false (simulating what the entry-time read
# could have been) and once with the real, freshly-queried $mainCount - proving only the fresh
# signal correctly protects the real, still-open decoy window.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}
Write-Host ''
Write-Host '=== Window-kill staleness guard (Bug 14) LIVE ===' -ForegroundColor Cyan

$content = Get-Content (Get-ClientFile 'editor-launch.ps1') -Raw
foreach ($n in @(
    'Test-LaunchPerfEnabled', 'Write-LaunchPerfLog', 'Write-EditorLaunchLog',
    'Invoke-CimEditorProcessQuery', 'Invoke-CimCursorProcessQuery',
    'Get-CursorProfileProcesses', 'Get-CursorMainProfileProcesses', 'Clear-CursorProcessCache'
)) {
    $src = Get-FunctionSource -Content $content -Name $n
    if (-not $src) {
        Write-Host "  FAIL  could not extract $n - live test cannot run (source drifted)" -ForegroundColor Red
        exit 1
    }
    . ([scriptblock]::Create($src))
}

# Never touch the real shared golden Cursor profile - stub the resolver to a fake test dir.
$script:FakeProfileDir = $null
function Get-CursorRemoteProfileDir { return $script:FakeProfileDir }

$script:EditorCimCache = @{}
$script:EditorCimCacheTtlSec = 2
$script:LaunchCimCallCount = 0

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cc-winkill-live-{0}" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$script:FakeProfileDir = Join-Path $tmp 'FakeCursorProfile'
New-Item -ItemType Directory -Force -Path $script:FakeProfileDir | Out-Null

$stubExe = Join-Path $tmp 'Cursor.exe'
$stubSrc = @'
using System.Threading;
class WindowKillStalenessStub { static void Main(string[] args) { Thread.Sleep(Timeout.Infinite); } }
'@
try {
    Add-Type -Language CSharp -TypeDefinition $stubSrc -OutputType ConsoleApplication -OutputAssembly $stubExe -ErrorAction Stop
} catch {
    Write-Host "  FAIL  could not compile decoy Cursor.exe: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Real "Window A" decoy: main profile process shape (user-data-dir = fake profile, no --type=),
# exactly what Get-CursorMainProfileProcesses filters for.
$argsA = "--user-data-dir=`"$($script:FakeProfileDir)`" --classic --folder-uri=`"vscode-remote://ssh-remote+unit-test-alias/home/testuser/window-a-project`""

$pA = $null
try {
    $pA = Start-Process -FilePath $stubExe -ArgumentList $argsA -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 600
    Assert (-not $pA.HasExited) 'decoy "Window A" (real, still-open main profile process) is actually running'

    $mainCount = @(Get-CursorMainProfileProcesses).Count
    Assert ($mainCount -ge 1) "real Get-CursorMainProfileProcesses (fresh CIM query) counts the live decoy: mainCount=$mainCount"

    # Extract the real production formula text (allergic to source drift, same technique as
    # test-launch-recovery-reachable-live.ps1).
    $formulaLine = ($content -split "`r?`n") | Where-Object { $_ -match '\$preservedOpenWindows\s*=' } | Select-Object -First 1
    Assert ($null -ne $formulaLine -and $formulaLine.Trim()) 'production $preservedOpenWindows formula line found in source (not silently missing)'
    $formulaExpr = $formulaLine.Trim()
    Write-Host "  live-extracted formula: $formulaExpr" -ForegroundColor DarkGray
    Assert ($formulaExpr -notmatch '\$hasProfileWindow') 'FIXED: formula no longer references the stale entry-time $hasProfileWindow at all'
    Assert ($formulaExpr -match '\$mainCount') 'FIXED: formula now references the fresh $mainCount signal'

    # Scenario: simulate the exact live incident - the stale entry-time read says "no window"
    # (as it did in the real repro, taken before Window A''s existence/aliveness was accounted
    # for), but the real decoy is genuinely alive RIGHT NOW. $mainCount is the fresh, real count.
    $EditorCmd = 'cursor'
    $agentHome = $false
    $hasProfileWindow = $false          # stale/wrong entry-time snapshot (as in the real incident)
    $profileProcCount = $mainCount      # real live count of ALL profile processes (>= main count)
    Invoke-Expression $formulaExpr
    Assert ($preservedOpenWindows -eq $true) 'FIXED: preservedOpenWindows is TRUE using the fresh $mainCount, even though the stale $hasProfileWindow would have said false - Window A is protected'

    # Prove the OLD (buggy) formula, evaluated against the exact same stale snapshot, would have
    # wrongly failed to protect the real, still-open decoy - this is the regression this test guards.
    $oldFormulaResult = ($EditorCmd -eq 'cursor' -and ($agentHome -or $hasProfileWindow) -and ($profileProcCount -gt 0))
    Assert ($oldFormulaResult -eq $false) 'REGRESSION CONFIRMED (old formula): using stale $hasProfileWindow alone would have returned FALSE here - Stop-CursorServerProfileTree would have killed the real, still-open Window A'

    $recoverySkipFires = ($EditorCmd -eq 'cursor' -and $profileProcCount -gt 0 -and $preservedOpenWindows)
    Assert ($recoverySkipFires -eq $true) 'FIXED: LAUNCH_RECOVERY_SKIP correctly fires (return before Stop-CursorServerProfileTree) - the real live decoy would NOT have been killed'
} finally {
    if ($pA) {
        try {
            $stillAlive = Get-Process -Id $pA.Id -ErrorAction SilentlyContinue
            if ($stillAlive) { Stop-Process -Id $pA.Id -Force -ErrorAction SilentlyContinue }
        } catch { }
    }
    Start-Sleep -Milliseconds 300
    $pAGone = $true
    if ($pA) { $pAGone = -not (Get-Process -Id $pA.Id -ErrorAction SilentlyContinue) }
    Assert $pAGone 'decoy "Window A" PID confirmed gone after the run (cleaned up in finally)'
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($fail -eq 0) { Write-Host 'ALL PASS (GREEN): Bug 14 is FIXED - the kill-safety guard now reads a fresh process count instead of a stale entry-time snapshot, so a real, still-open window from a different project is correctly protected.' -ForegroundColor Green; exit 0 }
Write-Host "$fail FAIL" -ForegroundColor Red
exit 1
