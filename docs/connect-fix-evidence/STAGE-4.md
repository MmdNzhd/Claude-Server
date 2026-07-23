# STAGE-4 Evidence Pack

## ID
- Stage: 4 (auto-recovery CLEAR_MOUNT uses presence API)
- CONNECT_VERSION: `20260722.40`
- Timestamp: 2026-07-22T18:05Z approx
- deploy_ran=no

## VERIFY
- Code dead path: `Test-RemoteEditorWindowOpen` (`editor-launch.ps1`) returns false unless on-folder; auto-recovery in `connect.ps1` called it after `Test-RemoteEditorOnCorrectFolder` failed → `editor_window_open_not_on_folder` unreachable.
- Poll loop already used `Get-RemoteEditorSessionPresence` (WindowOpen without on-folder); recovery did not → parity bug.
- Live: day log has frequent `CLEAR_MOUNT` / recovery churn historically (`RECOVERY_*` counts in Stage 0 timeline); wrong clear when window open not-on-folder is the structural risk.
- still_live=yes as structural bug until relaunch with patched recovery.

## RESEARCH
1. https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.mainwindowhandle — window handle ≠ folder match
2. https://code.visualstudio.com/docs/remote/ssh — Remote-SSH folder URI vs Agent/home drift
3. https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_logical_operators?view=powershell-7.6 — decision matrix OnFolder vs WindowOpen

What this changes:
- Auto-recovery uses `Get-RemoteEditorSessionPresence` for skip-clear decisions
- OnFolder → skip clear + editorOpened; WindowOpen-only → skip clear + log `editor_window_open_not_on_folder`; neither → allow CLEAR auto_recovery
- Manual R and auth gates unchanged

What we will NOT do:
- Change `Test-RemoteEditorWindowOpen` auth semantics; no Stage 5 MountOk edits in this pack; no deploy

## RED_TEST
```
test-auto-recovery-skip-clear-mount-matrix.ps1 → Failed: 4 (no presence in recovery; WindowOpen gate)
test-editor-presence-recovery-parity.ps1 → Failed: 2
```

## IMPLEMENT
- `scripts/client/windows/connect.ps1`: auto-recovery skip-clear block → presence API
- Tests: `test-auto-recovery-skip-clear-mount-matrix.ps1`, `test-editor-presence-recovery-parity.ps1` + run-all registration
- drive_by=none

## GREEN_TEST
```
test-auto-recovery-skip-clear-mount-matrix.ps1 → Passed: 12 Failed: 0
test-editor-presence-recovery-parity.ps1 → Passed: 5 Failed: 0
PARSE_OK connect.ps1
```

## LIVE_GATE
- `signature_absent=pending_reconnect` reason=`need tunnel-drop recovery with Cursor window open not-on-folder; expect RECOVERY_SKIP_CLEAR_MOUNT reason=editor_window_open_not_on_folder instead of CLEAR_MOUNT reason=auto_recovery`

## GATE
`STAGE_4_DONE` 2026-07-22T18:05Z `deploy_ran=no` N+1 unlocked (Stage 5)
