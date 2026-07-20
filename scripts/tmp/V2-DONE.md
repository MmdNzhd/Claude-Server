# V2 DONE - connect-ui.sh session log + silent update

Agent: V2
File: scripts/client/connect-ui.sh ONLY
Deploy: NO

## Implemented

### 1. connect_session_id helper
- Returns CLAUDE_CONNECT_RUN_ID if length >= 8
- Else returns CONNECT_SESSION_ID if length >= 8
- Else generates 12-char hex via python3 uuid (fallback: epoch+pid)
- Always non-empty

### 2. init_connect_log session id reuse
- Reuses CLAUDE_CONNECT_RUN_ID when >= 8 chars (no date-$$ overwrite)
- Syncs CONNECT_SESSION_ID and CLAUDE_CONNECT_RUN_ID both ways
- export CLAUDE_CONNECT_RUN_ID and export CONNECT_SESSION_ID

### 3. sessions.index TSV append
- Path: ~/.config/claude-connect/logs/sessions.index
- Columns: ts, session_id, pid, user, host, version, project_or_-

### 4. SESSION_FILTER tip line
- Logged at session start (INFO):
  SESSION_FILTER: grep "[session_id]" connect-YYYYMMDD.log (index: .../sessions.index)

### 5. invoke_connect_silent_update_check
- State: ~/.config/claude-connect/.last-update-check (unix epoch)
- Throttle: 30 min (1800s); logs UPDATE_SILENT skip reason=throttle
- Runs: CLAUDE_CONNECT_UPDATE_QUIET=1 bash connect-update.sh
- Script resolution: CONNECT_SCRIPT_DIR / SCRIPT_DIR / dirname(connect-ui) / mac/connect-update.sh fallbacks
- Stamps .last-update-check after attempt
- Exit 2: result=applied pending_restart=1 WARN; no exec/relaunch (mid-session safe)
- No user-facing output on this path

### 6. connect_log [sid] format preserved
- Format: [ts] [LEVEL] [SESSION_ID] message
- flush_connect_log_to_server uses same [sid] bracket

## Verification
- bash -n scripts/client/connect-ui.sh: OK
- ASCII-only: OK
- Contract symbols present for test-session-log-contracts.ps1 Mac asserts

## Out of scope (other agents)
- mac/connect.sh CLAUDE_CONNECT_RUN_ID bootstrap before connect-update.sh (V2 brief; user scoped connect-ui.sh only)
- git-mode.sh begin_connect_recovery wiring (V7)
- connect-update.sh CLAUDE_CONNECT_UPDATE_QUIET behavior (V6)
