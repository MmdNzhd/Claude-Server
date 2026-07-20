# FIX-AGENT-SESSION-TESTS (Agent5)

Date: 2026-07-20  
Spec: `scripts/tmp/SPEC-SESSION-LOG-UPDATE-20260720.md`  
Deploy: NO | Commit: NO

## Summary

Added session-log contract regression tests and wired them into the connect pipeline test suite.

## Files changed

| File | Change |
|------|--------|
| `scripts/client/tests/test-session-log-contracts.ps1` | **New** — source-level asserts for Session ID + silent update-on-drop (V9) |
| `scripts/client/tests/test-connect-pipeline.ps1` | Dot-sources `test-session-log-contracts.ps1` at end |

## Test run

```text
laptop-exec run -p claude-code-server -- powershell -NoProfile -File scripts/client/tests/test-connect-pipeline.ps1
```

| Run | Result | Notes |
|-----|--------|-------|
| 1 | **FAIL** (5) | Win `sessions.index` / `SESSION_FILTER` missing; Mac RUN_ID not yet exported; auto-recovery assert looked at call site not function body |
| 2 | **FAIL** (4) | Other agents landed Mac RUN_ID + silent update; Win index/filter still missing |
| 3 | **PASS** | All pipeline + session contract asserts green after Win parity + auto-branch assert fix |

**Final: PASS** — 91 pipeline asserts + 25 session contract asserts, 0 failures.

## Contract coverage (required asserts)

### Windows
- [x] `connect.bat` sets / creates `CLAUDE_CONNECT_RUN_ID`
- [x] `connect-ui.ps1` `Write-ConnectLog` `[$sid]` + `ConnectSessionId` / `Get-ConnectSessionId`
- [x] `connect-ui.ps1` `sessions.index` writer
- [x] `connect-ui.ps1` `SESSION_FILTER` log string
- [x] `Invoke-ConnectSilentUpdateCheck` / `UPDATE_SILENT`
- [x] `connect-update.ps1` `-Quiet` / `CLAUDE_CONNECT_UPDATE_QUIET`
- [x] `Begin-ConnectRecovery` auto branch calls silent update; manual branch does not

### Mac
- [x] `connect.sh` exports `CLAUDE_CONNECT_RUN_ID` before `connect-update.sh`
- [x] `init_connect_log` reuses via `connect_session_id` / `CLAUDE_CONNECT_RUN_ID`
- [x] `connect-update.sh` quiet mode (`CLAUDE_CONNECT_UPDATE_QUIET`)
- [x] `begin_connect_recovery` + `invoke_connect_silent_update_check` / `UPDATE_SILENT`
- [x] `connect-ui.sh` `sessions.index` + `SESSION_FILTER`

### Cross-cutting (added in V9 merge)
- [x] `git-mode.ps1` / `git-mode.sh` `TUNNEL_DROP`
- [x] `connect-ui.ps1` / `connect-ui.sh` force sync on `TUNNEL_DROP`

## Remaining gaps

None at final run. Mid-run failures were resolved by parallel agents (Win `sessions.index`, `Get-ConnectSessionId`) and by fixing the auto-recovery assert to inspect `Begin-ConnectRecovery` function body instead of the `-Trigger 'auto'` call-site block.
