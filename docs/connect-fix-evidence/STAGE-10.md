# STAGE-10 Evidence Pack

## ID
- Stage: 10 (cursor-profile-db-tool.ps1 manual report/prune)
- CONNECT_VERSION: `20260722.40` (unchanged; no bump)
- Timestamp: 2026-07-22T19:00Z approx
- deploy_ran=no

## VERIFY
- No `cursor-profile-db-tool.ps1` existed; chat/agent DB growth had only `_diag-cursor-chat.ps1` (read-only).
- Connect auto path must never prune/VACUUM while Cursor holds `state.vscdb` open.
- still_live=n/a (manual tool; not on connect path).

## RESEARCH
1. https://sqlite.org/lang_vacuum.html — VACUUM requires no competing write lock; unsafe while app open.
2. https://github.com/microsoft/vscode/issues/235684 — large `state.vscdb` / vacuum only when IDE closed.
3. https://github.com/microsoft/vscode/issues/189352 — VS Code does not auto-VACUUM; manual reclaim after close.

What this changes:
- New manual `scripts/client/cursor-profile-db-tool.ps1`: `-Report`; `-PruneChatAgent -Force` only if profile Cursor closed.
- Never wired into connect.bat/ps1/boot.

What we will NOT do:
- Auto-prune from connect; kill Cursor; deploy.

## RED_TEST
```
Pre-patch: tool path absent (Test-Path would FAIL).
```

## IMPLEMENT
- `scripts/client/cursor-profile-db-tool.ps1` (NEW)
- `scripts/client/tests/test-cursor-profile-db-tool.ps1` + run-all registration
- drive_by=none

## GREEN_TEST
```
test-cursor-profile-db-tool.ps1 → Passed: 18 Failed: 0
CONNECT_VERSION still 20260722.40
deploy_ran=no
```

## LIVE_GATE
- `signature_absent=n/a` reason=`manual tool only; connect path unchanged`

## GATE
`STAGE_10_DONE` 2026-07-22T19:00Z `deploy_ran=no` N+1 unlocked (Stage 6d)
