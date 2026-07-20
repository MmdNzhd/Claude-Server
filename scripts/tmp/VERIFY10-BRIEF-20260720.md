# 10-agent verify+fix brief (session log + silent update)

Deploy: NO. ASCII only. laptop-exec -p claude-code-server only.

## Must be TRUE after wave

1. Every run has CLAUDE_CONNECT_RUN_ID (12 hex preferred) before UPDATE and reused in session log.
2. Every log line: `[ts] [LEVEL] [SESSION_ID] msg`
3. sessions.index TSV on start; SESSION_FILTER tip line
4. TUNNEL_DROP structured on auto reconnect (Win+Mac)
5. On auto recovery only: silent update if age>=30min; UPDATE_SILENT logged; no user chatter; exit2 => pending_restart=1 no mid-session relaunch
6. Quiet update modes work
7. No nested-function corruption; no curly quotes in PS1
8. Tests assert the above

## File ownership (DO NOT edit outside your files)

| Agent | Owns |
|-------|------|
| V1 | connect-ui.ps1 (session id/index/filter/Get-ConnectSessionId/export env ONLY - leave silent-update region markers for V4) |
| V2 | connect-ui.sh + mac/connect.sh TOP bootstrap RUN_ID only |
| V3 | windows/connect.ps1 TUNNEL_DROP + Begin-ConnectRecovery hook call only |
| V4 | Silent update functions: add Invoke-ConnectSilentUpdateCheck to connect-ui.ps1 AND invoke_connect_silent_update_check to connect-ui.sh; wire already called from V3/V7 |
| V5 | windows/connect-update.ps1 Quiet + sid |
| V6 | mac/connect-update.sh Quiet + sid |
| V7 | git-mode.sh begin_connect_recovery auto->silent; Mac TUNNEL_DROP helper if needed |
| V8 | git-mode.ps1 TUNNEL_DROP field richness |
| V9 | tests/test-connect-pipeline.ps1 + test-session-log-contracts.ps1 |
| V10 | Scrub curly in touched clients; write SCOREBOARD-VERIFY10.md; run pipeline once at end |

## Markers for shared files
If editing connect-ui.ps1 for session vs silent: V1 puts session helpers near Initialize-ConnectLog; V4 puts silent update AFTER Close-ConnectLog block (or before Begin would be in connect.ps1). Avoid overlapping line ranges.
