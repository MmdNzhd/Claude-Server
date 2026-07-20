# Agent2: Mac Session ID Parity

Date: 2026-07-20
Spec: `scripts/tmp/SPEC-SESSION-LOG-UPDATE-20260720.md`
Deploy: NO

## Summary

Mac connect now mirrors Windows: a stable 12-hex `CLAUDE_CONNECT_RUN_ID` is created **before** `connect-update.sh`, exported to children, reused by `init_connect_log`, stamped on UPDATE file lines, and indexed in `sessions.index`.

## Files changed

| File | Change |
|------|--------|
| `scripts/client/mac/connect.sh` | Generate/export `CLAUDE_CONNECT_RUN_ID` + BOOTSTRAP day-log line before update |
| `scripts/client/connect-ui.sh` | `connect_session_id()` helper; `init_connect_log` reuses env id; `sessions.index` TSV; SESSION_FILTER tip |
| `scripts/client/mac/connect-update.sh` | `[sid]` on every `_update_file_log`; `CLAUDE_CONNECT_UPDATE_QUIET=1` suppresses user printf via `_update_msg` |

## Session ID flow (Mac)

```
connect.sh
  -> CLAUDE_CONNECT_RUN_ID (12 hex, exported)
  -> BOOTSTRAP line in connect-YYYYMMDD.log
  -> connect-update.sh (inherits sid; UPDATE: lines stamped)
  -> source connect-ui.sh
  -> init_connect_log (reuses sid; sets CONNECT_SESSION_ID; sessions.index row)
  -> all connect_log lines use CONNECT_SESSION_ID == CLAUDE_CONNECT_RUN_ID
```

## Key behaviors

1. **No overwrite**: If `CLAUDE_CONNECT_RUN_ID` is already set with length >= 8, `init_connect_log` keeps it (no more `date-$$` replacement).
2. **sessions.index** (`~/.config/claude-connect/logs/sessions.index`):
   - Columns: `ts`, `session_id`, `pid`, `user`, `host`, `version`, `project_or_-`
   - Tab-separated, one row per session start.
3. **SESSION_FILTER** INFO line tells operators how to grep one session from the day log.
4. **Quiet update**: `CLAUDE_CONNECT_UPDATE_QUIET=1 bash connect-update.sh` still writes `_update_file_log` lines with sid; `_update_msg` skips terminal output.
5. **step_ok**: Parent fix for nested `ensure_openssh_mux_limits` left intact (function ends before `step_ok()`).

## Verification

```bash
bash -n scripts/client/mac/connect.sh
bash -n scripts/client/connect-ui.sh
bash -n scripts/client/mac/connect-update.sh
```

Manual smoke (Mac):

```bash
unset CLAUDE_CONNECT_RUN_ID
bash scripts/client/mac/connect.sh --setup   # or normal run
grep BOOTSTRAP ~/.config/claude-connect/logs/connect-$(date +%Y%m%d).log | tail -1
grep 'UPDATE:' ~/.config/claude-connect/logs/connect-$(date +%Y%m%d).log | tail -3
tail -1 ~/.config/claude-connect/logs/sessions.index
```

Expect same 12-hex id in BOOTSTRAP, UPDATE, session start, and sessions.index row.

## Not done (other agents / user)

- Deploy / commit
- Windows `sessions.index` (Agent1)
- Silent update-on-drop wiring (Agent4)
- Pipeline test asserts (Agent5)
