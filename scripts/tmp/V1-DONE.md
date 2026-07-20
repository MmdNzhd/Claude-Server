# V1 Done: connect-ui.ps1 session log + silent update

Date: 2026-07-20
File: scripts/client/connect-ui.ps1 only
Deploy: NO

## Added

### Session ID helpers (near Initialize-ConnectLog)
- `$script:ConnectSessionId = ''` script variable
- `Get-ConnectSessionIndexPath` -> `~/.config/claude-connect/logs/sessions.index`
- `Get-ConnectSessionId` - always non-empty; prefers env `CLAUDE_CONNECT_RUN_ID` (>=8 chars), else new 12-hex GUID; sets `$env:CLAUDE_CONNECT_RUN_ID`
- `Write-ConnectSessionIndex` - appends TSV line: `ts\tsid\tpid\tuser\thost\tversion\tphase` (unix epoch ts, ASCII)

### Initialize-ConnectLog
- Calls `Get-ConnectSessionId` and exports `$env:CLAUDE_CONNECT_RUN_ID`
- Logs `SESSION_START` with host/os/user/elevated/pid/version/script_dir/log_path
- Logs `SESSION_FILTER grep=[sid] tip=filter day log by bracketed session id`
- Calls `Write-ConnectSessionIndex -Phase start -Version $Version` on session open
- Keeps existing `======== session start ...` banner and `[sid]` log line format

### Write-ConnectLog / sync paths
- All log lines use `Get-ConnectSessionId` instead of `-` fallback (format unchanged: `[ts] [LEVEL] [sid] msg`)

### Write-ConnectSessionContext
- Appends `Write-ConnectSessionIndex -Phase $Phase -Version $script:ConnectVersion` after context dump

### Silent update (after Close-ConnectLog)
- `Get-ConnectLastUpdateCheckPath` -> `$env:USERPROFILE\.config\claude-connect\.last-update-check`
- `Invoke-ConnectSilentUpdateCheck`:
  - Throttle: if age < 1800s -> `UPDATE_SILENT skip reason=throttle age_min=N` DEBUG; no stamp
  - Else runs `connect-update.ps1 -Quiet -ScriptDir` (from param / `$script:ConnectScriptDir` / `$PSScriptRoot`)
  - Stamps epoch seconds after every attempt (including unreachable)
  - Logs `UPDATE_SILENT age_min= result=ok|fail|applied|unreachable exit= pending_restart=0|1`
  - Exit 2 -> `result=applied pending_restart=1` WARN; no relaunch
- Moved from mid-file (was before Write-ConnectSessionOpenSummary) to after Close-ConnectLog

## Unchanged
- Existing Write-ConnectLog bracket format and sync behavior
- No deploy, no commit
- ASCII only in PS1
