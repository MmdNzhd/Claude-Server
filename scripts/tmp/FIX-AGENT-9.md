# FIX-AGENT-9 — Resource + leftover parity

Date: 2026-07-20  
Scope: laptop-exec only (`-p claude-code-server`). **No deploy. No commit.**  
Coordinate: Agent 5 owns watermark correctness — chunked reads advance offset only after successful remote append.

## Fixed slugs

| # | Slug | Fix |
|---|------|-----|
| 15 | `log-sync-readallbytes-full-file` | Win: `Read-ConnectLogFileChunk` FileStream seek/read (512KB). Update ship path streams too. Mac: Agent 5 already `dd` chunked; kept success-only advance. |
| 47 | `heartbeat-explain-log-growth` | HEARTBEAT logs short `editor=… profile_mains=N`; full `Get-RemoteEditorStateExplain` only if `CLAUDE_CONNECT_VERBOSE_LAUNCH=1`. |
| 48 | `session-cim-cache-no-ttl` | `EditorCimCache` entries are `{At,Procs}` with **2s TTL**. |
| 49 | `log-sync-ssh-kill-orphans` | `Invoke-ConnectLogProcTimed` / `Invoke-SshTimed`: `taskkill /T /F` + WaitForExit. Mac: `_scp_connect_log_chunk` uses `timeout 20` + `pkill` on 124. |
| 50 | `start-job-scp-orphan-on-timeout` | `Prepare-ServerSessionParallel`: `Start-Process scp` + tree kill (no `Start-Job`/`Stop-Job`). |
| 51 | `tunnel-softfail-cim-reattach-storm` | `Get-TunnelSshProcess` 2s CIM cache; cleared with banner cache. |
| 60 | `session-double-onfolder-check` | `Get-RemoteEditorSessionPresence` single-pass; session loop uses it. |
| 61 | `local-day-log-no-size-cap` | Win/Mac rotate at **8MB** → `.prev`, reset watermark. |
| 73 | `warn-sync-storm-amplifies-ram` | WARN sync debounced **5s** (ERROR still immediate/`-Force`). |
| 57 | `controlmaster-asymmetry` | Mac `sshx`: on exit **255**, `ssh -O exit`, unlink ControlPath, retry once (`SSH_MUX_STALE`). |
| 59 | `post-disconnect-layout-parity` | Soft note + explicit ignore of non-`m/c/x` in `read_post_disconnect_key` (Mac TTY has no VK; Win keeps useVk). |

## Files touched

- `scripts/client/connect-ui.ps1` — chunk read, kill tree, 8MB rotate, WARN debounce, HEARTBEAT summary
- `scripts/client/connect-ui.sh` — rotate, WARN debounce, `_scp_connect_log_chunk` (Agent 5 watermark/dd preserved)
- `scripts/client/editor-launch.ps1` — CIM TTL + `Get-RemoteEditorSessionPresence`
- `scripts/client/windows/connect.ps1` — session loop uses presence helper
- `scripts/client/git-mode.ps1` — tunnel ssh CIM cache; scp Start-Process kill
- `scripts/client/git-mode.sh` — Bug 59 post-disconnect ASCII-only note
- `scripts/client/mac/connect.sh` — ControlMaster stale soft-fix
- `scripts/client/windows/connect-update.ps1` — stream day-log ship; taskkill tree

## Leftover risks

- **#59**: Mac still cannot map Persian physical keys to M/C/X (no ConsoleKey). Users must type Latin or wait for default. Full VK parity needs UX/OS-level input, not bash `read -n 1`.
- **#51**: Cache TTL 2s may briefly delay reattach after kill; banner-cache clear invalidates.
- **#15/#73**: Debounced WARN may delay shipping WARN lines up to 5s during flaps (ERROR/`-Force` still immediate).
- **Agent 5 overlap**: Mac sync already chunked + success-only; we did not weaken watermark gates.
- Tunnel DROP budget logic intentionally untouched (Agents 3/4).

## Verify

- PowerShell `Parser::ParseFile` OK: connect-ui/editor-launch/git-mode/connect/connect-update
- `bash -n` OK: connect-ui.sh, mac/connect.sh, git-mode.sh
