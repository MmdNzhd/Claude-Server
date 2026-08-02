#Requires -Version 5.1
# test-launch-success-confirm-unify.ps1 - P0.4: Launch/Confirm success bar + fail message + orphan reap
# Covers:
#   1) Launch-RemoteEditor and Confirm-RemoteEditorLaunchVisible share on_folder-only success
#   2) Get-RemoteEditorLaunchFailMessage reflects elevated vs non-elevated (no hardcoded lie)
#   3) Losing-strategy orphan reaping helper exists and is wired after LAUNCH_OK
#   4) Warm handoff has a cascade fallback (remote-classic) without folder-uri
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
$pass = 0

function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Launch success / Confirm unify (P0.4) ===' -ForegroundColor Cyan
Write-Host ''

. (Get-ClientFile 'editor-launch.ps1')
$elSrc = Get-Content -LiteralPath (Get-ClientFile 'editor-launch.ps1') -Raw
$winSrc = Get-Content -LiteralPath (Get-ClientFile 'windows\connect.ps1') -Raw

# --- 1) Helpers present ---------------------------------------------------------------------------
Assert ((Get-Command Confirm-RemoteEditorLaunchVisible -ErrorAction SilentlyContinue) -ne $null) `
    'Confirm-RemoteEditorLaunchVisible defined'
Assert ((Get-Command Get-RemoteEditorLaunchFailMessage -ErrorAction SilentlyContinue) -ne $null) `
    'Get-RemoteEditorLaunchFailMessage defined'
Assert ((Get-Command Stop-EditorLaunchAttemptOrphans -ErrorAction SilentlyContinue) -ne $null) `
    'Stop-EditorLaunchAttemptOrphans defined'

# --- 2) Unified success bar: Launch must NOT return true on window_count alone --------------------
$launchFn = Get-FunctionSource -Content $elSrc -Name 'Launch-RemoteEditor'
Assert ($launchFn -match 'reason=on_folder') 'Launch-RemoteEditor LAUNCH_OK uses reason=on_folder'
Assert ($launchFn -match 'LAUNCH_PROMISING') 'Launch-RemoteEditor logs LAUNCH_PROMISING for window-count'
Assert ($launchFn -notmatch '\$okReason = ''window_count_increased_no_title_match''') `
    'Launch-RemoteEditor does not treat window_count as LAUNCH_OK reason'
Assert ($launchFn -notmatch 'elseif \(\$windowCountIncreased -and -not \$afterAgent\) \{ \$launchOk = \$true') `
    'Launch-RemoteEditor no longer returns true on window_count_increased alone'

$confirmFn = Get-FunctionSource -Content $elSrc -Name 'Confirm-RemoteEditorLaunchVisible'
Assert ($confirmFn -match 'Test-RemoteEditorOnCorrectFolder') 'Confirm still requires on_folder'
Assert ($confirmFn -notmatch 'window_count|windowCountIncreased|MainWindowHandle -ne \[IntPtr\]::Zero') `
    'Confirm does not accept window-count / any-MainWindowHandle as success'
Assert ($confirmFn -match 'MUST match Launch-RemoteEditor|Unified success bar|on_folder only') `
    'Confirm documents on_folder-only bar shared with Launch'

# Structural: both functions' success path is Test-RemoteEditorOnCorrectFolder (no alternate bar)
Assert (
    ([regex]::Matches($launchFn, 'Test-RemoteEditorOnCorrectFolder').Count -ge 1) -and
    ([regex]::Matches($confirmFn, 'Test-RemoteEditorOnCorrectFolder').Count -ge 1)
) 'Launch and Confirm both gate success on Test-RemoteEditorOnCorrectFolder'

# --- 3) Fail message: elevated vs non-elevated ----------------------------------------------------
$msgFn = Get-FunctionSource -Content $elSrc -Name 'Get-RemoteEditorLaunchFailMessage'
Assert ($msgFn -match 'Test-IsElevatedShell') 'fail message consults Test-IsElevatedShell'
Assert ($msgFn -match 'elevated launch failed') 'elevated branch still mentions elevated when true'
Assert ($msgFn -match 'launch did not show the project folder window') 'non-elevated branch is accurate'
Assert ($msgFn -match 'if \(\$elevated\)') 'fail message branches on elevation'

# Live call under current shell (this test process is almost always non-elevated)
$isElev = $false
try { $isElev = [bool](Test-IsElevatedShell) } catch { $isElev = $false }
$liveMsg = Get-RemoteEditorLaunchFailMessage -EditorName 'Cursor'
if ($isElev) {
    Assert ($liveMsg -match '^elevated launch failed') 'elevated shell: message says elevated launch failed'
    Assert ($liveMsg -match 'try non-elevated Connect') 'elevated shell: message suggests non-elevated Connect'
} else {
    Assert ($liveMsg -notmatch 'elevated launch failed') 'non-elevated shell: message does NOT say elevated launch failed'
    Assert ($liveMsg -match 'launch did not show the project folder window') 'non-elevated shell: accurate failure text'
}

# connect.ps1 must use the helper (both Opening and O-retry Confirm fail paths)
Assert ($winSrc -match 'Get-RemoteEditorLaunchFailMessage') 'connect.ps1 calls Get-RemoteEditorLaunchFailMessage'
Assert ($winSrc -notmatch 'StepFail "elevated launch failed - no \$EditorName window \(try non-elevated') `
    'connect.ps1 no longer hardcodes elevated launch failed on Confirm fail'

# --- 4) Orphan reaping ---------------------------------------------------------------------------
$reapFn = Get-FunctionSource -Content $elSrc -Name 'Stop-EditorLaunchAttemptOrphans'
Assert ($reapFn -match 'LAUNCH_REAP_ORPHAN') 'reap helper logs LAUNCH_REAP_ORPHAN'
Assert ($reapFn -match 'KeepPids') 'reap helper respects KeepPids'
Assert ($reapFn -match 'CandidatePids') 'reap helper takes CandidatePids'
Assert ($launchFn -match 'Stop-EditorLaunchAttemptOrphans') 'Launch-RemoteEditor calls orphan reap on success'
Assert ($launchFn -match 'failedAttemptPids') 'Launch-RemoteEditor tracks failedAttemptPids across strategies'
Assert ($launchFn -match 'LastEditorStartPid') 'Launch tracks LastEditorStartPid for orphan candidates'

# Unit: KeepPids protects candidates (no process kill of keep list; empty candidates = 0)
$reapedNone = Stop-EditorLaunchAttemptOrphans -KeepPids @(1, 2) -CandidatePids @()
Assert ($reapedNone -eq 0) 'Stop-EditorLaunchAttemptOrphans returns 0 for empty candidates'

# Unit: candidate equal to keep is skipped (do not need a real process)
$reapedKeep = Stop-EditorLaunchAttemptOrphans -KeepPids @(999001) -CandidatePids @(999001)
Assert ($reapedKeep -eq 0) 'Stop-EditorLaunchAttemptOrphans skips PIDs in KeepPids'

# --- 5) Warm handoff cascade (no folder-uri) ------------------------------------------------------
$alias = 'claude-server'
$path = '/home/smart/mounts/ai'
$uri = Get-RemoteFolderUri -Alias $alias -RemotePath $path
$warm = @(Get-RemoteEditorLaunchStrategies -EditorCmd 'cursor' -Alias $alias -RemotePath $path -Uri $uri -NewWindow -WarmHandoff)
Assert ($warm.Count -ge 2) 'warm handoff has at least one fallback strategy'
Assert ($warm[0].Name -eq 'remote') 'warm first is remote'
Assert ($warm[1].Name -eq 'remote-classic') 'warm second is remote-classic'
Assert (@($warm | Where-Object { $_.Name -like 'folder-uri*' }).Count -eq 0) 'warm never includes folder-uri*'

# --- 6) Cold poll budget widened (root cause of premature 4-strategy cascade on Aug 2) ------------
Assert ($launchFn -match 'elseif \(\$attempt -eq 1\) \{ 48 \}') 'cold attempt-1 poll is 48 ticks (12s)'
Assert ($elSrc -match 'Order decision 2026-08-02') 'strategy-order decision documented in source'

Write-Host ''
Write-Host "Passed: $pass  Failed: $fail" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { exit 1 }
exit 0
