# FIX-AGENT-5 — Logging + error flush

Date: 2026-07-20  
Scope: bugs **11, 12, 36, 37, 38, 72** + cross-cutting Unexpected/trap/ERROR → day log + sync  
Deploy: **none** | Commit: **none**

## Fixed slugs

| # | Slug | Fix |
|---|------|-----|
| 11 | `ssh-trailing-true-masks-append-fail` | Remote append now `ec=$?; …; exit $ec` (no trailing `true`). Watermark advances only when SSH exit=0 after cat. |
| 12 | `mac-scp-ok-without-cat-advances-watermark` | Mac only advances after successful `sshx`/`ssh` cat append (`cat_ok=1`). |
| 36 | `trace-debug-skip-sync-trigger` | `TUNNEL_*` TRACE can trigger sync (soft_fail/DROP/EXIT or every 25); ERROR always `-Force` / `force` sync. |
| 37 | `midnight-rollover-abandons-unsynced-day` | Before switching day path, flush previous day (`Sync -Force -LogPath` / `sync_connect_log_to_server`). |
| 38 | `mac-tail-cmdsubst-wc-watermark-loss` | Replaced `chunk="$(tail …)"` with `dd` → chunk file; advance by chunk byte count (`off+take`), not full-file `wc`. |
| 72 | `concurrent-watermark-server-duplication` | Win: exclusive `.sync-lock` FileStream + in-process flag; re-read watermark under lock. Mac: `flock` on `.sync-lock`; re-read offset under lock. |

### Error-flush (cross-cutting)

- **Win** `connect.ps1` trap: `Write-ConnectLog … ERROR` then `Sync-ConnectLogToServer -Force`.
- **Win** `Write-ConnectLog` ERROR → Force sync; Close/Wait-ConnectExit → Force.
- **Mac** `die()`: log ERROR + `flush_connect_log_to_server`.
- **Mac** ERR trap: log `UNHANDLED` ERROR + force flush (note: script uses `set -uo pipefail` **without** `-e`, so ERR fires only when a failing command is under `set -e` / explicit ERR contexts; EXIT flush still covers normal exit).
- TEMP cleanup failures in log-sync helper log `TEMP_CLEANUP_FAIL` WARN (durable) instead of silent `SilentlyContinue`.

## Files touched

| File | Changes |
|------|---------|
| `scripts/client/connect-ui.ps1` | Sync lock, no trailing true, Force/LogPath, midnight flush, TUNNEL TRACE sync, ERROR Force, TEMP_CLEANUP_FAIL |
| `scripts/client/connect-ui.sh` | Same semantics: flock, dd chunks, cat_ok watermark, midnight flush, TUNNEL TRACE, force drain |
| `scripts/client/windows/connect.ps1` | Unexpected trap Force sync after ERROR |
| `scripts/client/mac/connect.sh` | `die()` ERROR+flush; ERR trap UNHANDLED+flush |
| `scripts/client/windows/connect-update.ps1` | Same cat `exit $ec` (bug 11 parity; Agent 6 owns update broadly) |

## Agent 9 coordination

- **Did not** replace `ReadAllBytes` with streaming/chunks for RAM.
- Kept `ReadAllBytes` + 512KB outbound chunk for watermark correctness.
- Agent 9 may switch to streaming reads; preserve: re-read watermark under lock, advance only after successful append, never trailing `true`.

## Leftover risks

1. **Mac ERR without `set -e`**: Unexpected failures may not hit ERR trap; rely on `die()` / EXIT flush. Consider `set -e` carefully or call flush on known fail paths.
2. **Mac `dd bs=1`**: Correct but slow for large remaining tails; Agent 9 / follow-up can use larger block `dd`/`tail -c`→file without cmdsubst.
3. **Force drain** capped at 64 chunks (~32MB) per Force call — huge day logs may need another Close/Force.
4. **Designer / connect-design** forks not updated (Agent 8) — if they vendor copy log sync, they still have old bugs.
5. **mkdir remote still ends with `; true`** (intentional — cleanup best-effort); only **cat append** must not mask failures.

## Verify (manual)

```bash
# After a soft_fail / Unexpected, server day log should contain ERROR/WARN and preceding TUNNEL_* TRACE.
# Fail a remote append (e.g. fill disk) → local .sync-offset must NOT advance.
```
