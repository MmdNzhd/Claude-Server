# Spec: Complete logs + Session ID + Silent update-on-drop

Date: 2026-07-20
Deploy: NO until user OK

## User intent (exact)

1. Logs must be COMPLETE enough that reading them alone diagnoses any failure.
2. Every app run has a stable Session ID stamped on EVERY log line (user often has 4 sessions open).
3. On connection drop: silently check for client update if >= 30 minutes since last check — do NOT tell the user; DO log everything with session id.
4. Multi-agent implementation.

## Session ID contract

- Env: `CLAUDE_CONNECT_RUN_ID` (12 hex chars preferred).
- Win: already created in `connect.bat` before BOOTSTRAP/UPDATE; `Initialize-ConnectLog` reuses it.
- Mac: MUST create/export BEFORE `connect-update.sh` and keep same id in `init_connect_log` (today Mac overwrites with `date-$$` — fix).
- Every log line format (already mostly true):
  `[yyyy-MM-dd HH:mm:ss.fff] [LEVEL] [SESSION_ID] message`
- Also write one index line per session start:
  `~/.config/claude-connect/logs/sessions.index`
  `ts\tsession_id\tpid\tuser\thost\tversion\tproject_or_-`
- Export `CLAUDE_CONNECT_RUN_ID` so children (update, diagnostic helpers) inherit.
- Helper: `Get-ConnectSessionId` / `connect_session_id` always returns non-empty.

## Completeness events (must log with sid)

On session start / context / drop / recover / ensure / update:
- SESSION_START (host, os, user, elevated, pid, version, script_dir, log_path)
- CONTEXT phase=* (existing)
- TUNNEL_DROP reason=... soft_fail=... tcp=... banner=... editor_open=... project=...
- RECOVERY trigger=auto|manual ...
- ENSURE action=... result=...
- UPDATE_SILENT age_min=... result=skip|ok|fail|applied pending_restart=0|1
- SESSION_END

When auto-drop: include enough fields to answer "why" without guessing.

## Silent update-on-drop (30 min)

- State file: `~/.config/claude-connect/.last-update-check` (unix epoch or ISO)
- Hook: auto reconnect path only (`Begin-ConnectRecovery -Trigger auto` / `begin_connect_recovery auto`)
- If last check age < 30 min → log `UPDATE_SILENT skip reason=throttle age_min=N` DEBUG; return
- Else → run update Quiet (no Write-Host about update to user)
  - Win: `& connect-update.ps1 -ScriptDir ... -Quiet`
  - Mac: `CLAUDE_CONNECT_UPDATE_QUIET=1 bash connect-update.sh` (add quiet mode)
- Always stamp last-check time after attempt (even unreachable)
- Exit codes:
  - 0: log UPDATE_SILENT result=ok_or_unreachable
  - 1: log UPDATE_SILENT result=fail ERROR + Force sync
  - 2: files updated on disk; log UPDATE_SILENT result=applied pending_restart=1 WARN
    - Do NOT auto-relaunch mid-session (would kill open work). Next bat/sh start picks new files.
- Never toast / Write-Host update messages on this path.

## Agents

1. Win session-id export + index + ensure all Write-UpdateFileLog / helpers use env
2. Mac session-id before update + init_connect_log reuse + quiet update flag
3. Rich TUNNEL_DROP / recovery diagnostic fields (Win+Mac)
4. Silent update helper + wire into Begin-ConnectRecovery / begin_connect_recovery
5. Tests: pipeline asserts for sid format, sessions.index, UPDATE_SILENT, Quiet flag, Mac bootstrap id

## Gate

- test-connect-pipeline.ps1
- test-git-mode-deep.ps1 (if touched)
- New/extended contract asserts
- ASCII-only in PS1 (no curly quotes)
- No deploy
