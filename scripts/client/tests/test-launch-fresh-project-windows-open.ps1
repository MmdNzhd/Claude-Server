# test-launch-fresh-project-windows-open.ps1 - a fresh project pick must open even when other
# server-profile windows are already open and auth just re-synced.
# Callers: scripts/client/tests/run-all.ps1
#
# Live repro 2026-07-25 (project=deploy): with ~25 [Claude Server] profile windows already open
# from earlier picks, selecting a NEW project while auth was re-synced (daily golden refresh set
# $authRelaunch) hit the "preserve windows after tunnel recovery" branch and SKIPPED the launch
# entirely - no STEP begin: Opening Cursor, no LAUNCH_ATTEMPT - so the session ended in
# CURSOR_NOT_OPEN even though the user explicitly picked a project.
#
# Root cause: the skip fired on ($authRelaunch -and $profileAlreadyOpen) regardless of whether the
# TARGET folder was open, and the actual launch block was gated behind (-not $profileAlreadyOpen),
# so a fresh pick while windows were open could never launch. Fix: the preserve-skip must require
# $onCorrectFolder (nothing new to open); otherwise fall through and open the picked project in a
# --new-window (Launch-RemoteEditor never kills on AuthRelaunch, so other windows are undisturbed).
# This test guards the source shape on Windows and the Mac parity path in connect.sh.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_paths.ps1')
$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  PASS  $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:fail++ }
}

Write-Host ''
Write-Host '=== Fresh project launch with windows open ===' -ForegroundColor Cyan
Write-Host ''

$win = Get-Content (Get-ClientFile 'windows\connect.ps1') -Raw
$mac = Get-Content (Get-ClientFile 'mac\connect.sh') -Raw

# --- Windows -------------------------------------------------------------------------------
# Preserve-skip is gated on being ON the target folder.
Assert ($win -match '\$skipForPreserve\s*=\s*\(\$authRelaunch\s+-and\s+\$profileAlreadyOpen\s+-and\s+\$onCorrectFolder\)') `
    'skip-for-preserve requires $onCorrectFolder (Win)'
# The launch block is gated behind (-not $skipForPreserve), NOT the old (-not $profileAlreadyOpen).
Assert ($win -match 'if\s*\(\(-not\s+\$skipForPreserve\)\s+-and\s+\(\$authRelaunch\s+-or') `
    'launch block gated on -not $skipForPreserve (Win)'
Assert (-not ($win -match 'if\s*\(\(-not\s+\$profileAlreadyOpen\)\s+-and\s+\(\$authRelaunch')) `
    'old buggy (-not $profileAlreadyOpen) launch gate is gone (Win)'
Assert ($win -match 'EDITOR_LAUNCH new_project_new_window despite_profile_windows_open') `
    'logs the fresh-project new-window path (Win)'
# The preserve-skip must no longer be the unconditional ($authRelaunch -and $profileAlreadyOpen) form.
Assert (-not ($win -match 'if\s*\(\$authRelaunch\s+-and\s+\$profileAlreadyOpen\)\s*\{')) `
    'no unconditional preserve-skip on (authRelaunch -and profileAlreadyOpen) (Win)'

# --- Mac parity ----------------------------------------------------------------------------
Assert ($mac -match '_skip_for_preserve=0') '_skip_for_preserve introduced (Mac)'
Assert ($mac -match '\[ "\$_auth_relaunch" -eq 1 \] && \[ "\$_profile_already_open" -eq 1 \] && \[ "\$_on_folder" -eq 1 \]') `
    'preserve-skip requires _on_folder -eq 1 (Mac)'
Assert ($mac -match 'if \[ "\$_skip_for_preserve" -eq 1 \]; then') 'launch branch keys off _skip_for_preserve (Mac)'
Assert ($mac -match 'EDITOR_LAUNCH new_project_new_window despite_profile_windows_open') `
    'logs the fresh-project new-window path (Mac)'

Write-Host ''
if ($fail -eq 0) { Write-Host 'All tests passed.' -ForegroundColor Green; exit 0 }
Write-Host "$fail test(s) failed." -ForegroundColor Red; exit 1
