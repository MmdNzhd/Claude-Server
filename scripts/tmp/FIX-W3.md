# FIX-W3 — Logging error flush (durable server logs)

**Agent:** W3  
**Date:** 2026-07-20  
**Deploy:** NO

## Pain

Errors with **no durable server logs** (`~/.claude/logs/`). Watermarks advanced after masked remote append (`; true`), so ERROR lines never landed on the server.

## Must-fix checklist

| # | Requirement | Result |
|---|-------------|--------|
| 1 | Watermark only on successful remote append (no `; true` on log-append SSH) | **DONE** — `$cat` / Mac append use `exit $ec`; gate `$appendOk`/`$scpOk`/`cat_ok`. pkill/ssh-keygen `; true` untouched. |
| 2 | Mac: no advance after scp if cat failed | **DONE** — `cat_ok` gate in `sync_connect_log_to_server`. |
| 3 | trap/Unexpected: ERROR then force flush before exit | **DONE** — Win trap `Write-ConnectLog ERROR` + `Sync -Force`. Mac `die` ERROR+flush; EXIT nonzero → UNHANDLED ERROR + flush; ERR trap retained. |
| 4 | ERROR/WARN trigger sync (not stuck on TRACE flush) | **DONE** — writer Flush then `Sync -Force` for ERROR and WARN (Win+Mac `force`). |
| 5 | Midnight: flush previous day first | **DONE** — Win `Sync -Force -LogPath $prevPath`; Mac `sync_connect_log_to_server force` before path switch. |
| 6 | Chunked day-log read (no full-file `ReadAllBytes`) | **DONE** — `connect-ui.ps1` Sync + Force drain; `connect-update.ps1` ship path. |

## Files touched

- `scripts/client/connect-ui.ps1`
- `scripts/client/connect-ui.sh`
- `scripts/client/windows/connect-update.ps1`
- `scripts/client/mac/connect.sh`
- `scripts/tmp/FIX-W3.md`

## Verification (no deploy)

```text
test-error-flush-contract.ps1  → pass=16 fail=0 CONTRACT OK
test-log-sync-contracts.ps1    → fail=0 VERDICT: PASS
```

## Notes

- Peer agents already landed fail-closed append, Mac `dd` chunks, sync locks, traps; W3 finished chunked Win reads, WARN `-Force`, midnight `force`, EXIT ERROR-on-nonzero.
- `$mk` cleanup may still end with best-effort find; **append** path is fail-closed (the bug that ate server logs).
