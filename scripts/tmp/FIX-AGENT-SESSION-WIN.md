# FIX-AGENT-SESSION-WIN (Agent1)

Date: 2026-07-20
Deploy: NO
Commit: NO

## Goal

Make Windows connect Session ID complete and filterable when the user has 4 concurrent sessions open.

## Files changed

| File | Changes |
|------|---------|
| `scripts/client/connect-ui.ps1` | `Get-ConnectSessionId`, `Write-ConnectSessionIndex`, env export, SESSION_FILTER hint, index on start/project_selected/session_end, all log paths use non-empty sid |
| `scripts/client/windows/connect.bat` | REM documenting setlocal env inheritance to child PowerShell (RUN_ID already created before BOOTSTRAP/UPDATE) |
| `scripts/client/windows/connect-update.ps1` | `Ensure-ConnectRunId` generates/exports 12-hex sid when env empty; `Write-UpdateFileLog` always stamps sid |

## Session ID contract

- Env: `CLAUDE_CONNECT_RUN_ID` (12 hex chars)
- Win flow: `connect.bat` sets RUN_ID -> BOOTSTRAP log -> `connect-update.ps1` (Ensure-ConnectRunId) -> `connect.ps1` / `Initialize-ConnectLog` (Get-ConnectSessionId reuses env)
- Every connect log line: `[yyyy-MM-dd HH:mm:ss.fff] [LEVEL] [SESSION_ID] message`
- Index file: `%USERPROFILE%\.config\claude-connect\logs\sessions.index`
  - TSV columns: `ts`, `session_id`, `pid`, `user`, `host`, `version`, `phase`
  - Phases written: `start`, `project_selected`, `session_end`

## How to filter 4 concurrent sessions

### 1. Find session ids (index)

```powershell
Get-Content "$env:USERPROFILE\.config\claude-connect\logs\sessions.index"
```

Each open connect run appends a `start` line with a unique 12-hex `session_id`. Match `pid` or time to the window you care about.

### 2. Filter the day log by bracketed session id

```powershell
$day = Get-Date -Format yyyyMMdd
$log = "$env:USERPROFILE\.config\claude-connect\logs\connect-$day.log"
$sid = 'abc123def456'   # from sessions.index or SESSION_FILTER line in log
Select-String -Path $log -Pattern "\[$sid\]"
```

Or one-liner after copying sid from index:

```powershell
findstr /C:"[abc123def456]" "%USERPROFILE%\.config\claude-connect\logs\connect-20260720.log"
```

### 3. SESSION_FILTER hint in log

At session start each run writes:

```
SESSION_FILTER grep=[abc123def456] tip=filter day log by bracketed session id
```

Search for `SESSION_FILTER` to list all active session ids in today's log:

```powershell
Select-String -Path $log -Pattern 'SESSION_FILTER grep=\['
```

### 4. Server copy (when synced)

Same bracket filter on `~/.claude/logs/connect-YYYYMMDD.log` on the server.

## Verification (manual)

1. Start connect twice (or note two existing sessions).
2. Confirm two distinct ids in `sessions.index` and two `SESSION_FILTER` lines in today's log.
3. Confirm `Select-String` with one sid returns only that session's lines (BOOTSTRAP/UPDATE/share same RUN_ID per bat launch; connect.ps1 session continues same id).

## Not in scope (this agent)

- Mac parity (Agent2)
- TUNNEL_DROP rich fields / silent update-on-drop (Agents 3-4)
- Pipeline tests (Agent 5)
