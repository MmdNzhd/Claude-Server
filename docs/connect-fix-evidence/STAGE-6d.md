# STAGE-6d Evidence Pack

## ID
- Stage: 6d (Chat freeze — PROXY_CLEAR_SKIP + AUTH db_too_large)
- CONNECT_VERSION: `20260722.40` (unchanged; no bump)
- Timestamp: 2026-07-22T19:20Z approx
- deploy_ran=no

## VERIFY
- `Clear-CursorProxySettingsSidecar` could clear `settings.json` proxy keys while server-profile Cursor windows were open (call sites in editor-launch / git-mode / connect / sidecar heartbeat) — freezes chat when 18998 dies mid-session.
- `Test-MayClearCursorProxySettings` already skipped Clear-CursorProxySettings when windows open; sidecar path bypassed that gate.
- Mid-session `Sync-CursorGoldenAuth` always attempted merge regardless of `state.vscdb` size (WAL/merge risk on huge DBs).
- Stage 6 `auto_relaunch_skip reason=cursor_settings` still present (must not regress).
- still_live=pending_reconnect for CLEAR_SKIP / AUTH_SYNC_SKIP signatures.

## RESEARCH
1. https://www2.sqlite.org/wal.html — WAL / large transactions; avoid heavy writes under long-lived readers.
2. https://sqlite.org/lang_vacuum.html — competing locks while app holds DB open.
3. https://github.com/microsoft/vscode/issues/235684 — large state.vscdb operational risk; reclaim only when closed.

What this changes:
- Sidecar Clear + editor-launch call site: CURSOR_PROXY_CLEAR_SKIP reason=windows_open action=repair_sidecar_only
- Mid-session AUTH (!Force): AUTH_SYNC_SKIP reason=db_too_large when db_bytes > 524288000; no merge
- Keep auto_relaunch Settings gate

What we will NOT do:
- Deploy; ForceUnfreeze; kill Cursor; bump version.

## RED_TEST
```
test-chat-freeze-skip-paths.ps1 → missing pre-patch (file created in IMPLEMENT)
Static VERIFY: sidecar Clear lacked windows_open CLEAR_SKIP; auth lacked db_too_large.
```

## IMPLEMENT
- `scripts/client/windows/cursor-proxy-sidecar.ps1`: Clear gated + repair-only when windows open
- `scripts/client/editor-launch.ps1`: call site CLEAR_SKIP + repair before sidecar clear
- `scripts/client/cursor-auth-laptop.ps1`: AUTH_SYNC_SKIP db_too_large mid-session
- `scripts/client/tests/test-chat-freeze-skip-paths.ps1` + run-all
- drive_by=none

## GREEN_TEST
```
test-chat-freeze-skip-paths.ps1 → Passed: 13 Failed: 0
CONNECT_VERSION still 20260722.40
deploy_ran=no
```

## LIVE_GATE
- `signature_absent=pending_reconnect` reason=`need client relaunch; expect CURSOR_PROXY_CLEAR_SKIP reason=windows_open action=repair_sidecar_only when profile open; AUTH_SYNC_SKIP reason=db_too_large when mid-session db>500MiB`

## GATE
`STAGE_6d_DONE` 2026-07-22T19:20Z `deploy_ran=no` N+1 unlocked (Stage 7)
