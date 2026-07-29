# Task 3 Report: Stale forward Mac `i=0` + refuse spawn when still busy

**Status:** DONE  
**Branch:** `fix/zombie-owner-reseed-gap`  
**Commit:** `405b4c1` — `fix(connect): refuse spawn on still-busy stale forward within 15s`

## Summary

Mac `clear_server_stale_tunnel_forward` now initializes `local i=0` before the wait loop. Win Clear sets `LastStaleForwardStillBusyPort`/`At` on still-busy and clears them on release. Ensure (Win+Mac) refuses spawn with `reason=stale_port_busy` when still-busy within **15s**, TCP open, and no local `-R` — never WARN-then-spawn same port.

## Changes

| File | Change |
|---|---|
| `scripts/client/git-mode.ps1` | Clear LastStale*; `Test-StaleForwardStillBusyAbort`; Ensure refuse before `Start-Process` |
| `scripts/client/git-mode.sh` | `local i=0`; still-busy markers; `stale_forward_still_busy_abort`; ensure refuse |
| `scripts/client/tests/test-stale-forward-wait-init.ps1` | Static + behavioral spawn_count=0 |

## Contracts

- **D4:** still-busy + empty local PIDs => `spawn_count=0` on busy port
- **S2:** `stale_port_busy` on Win Ensure + Mac ensure
- **S3:** `StillBusyWindowSec` / `STILL_BUSY_WINDOW_SEC=15` locked in test
- **S5:** Mac `local i=0` before while

## Tests

| Suite | Result |
|---|---|
| `test-stale-forward-wait-init.ps1` | PASS (24 asserts) |
| `test-wait-local-r-ownership.ps1` | PASS (15 asserts) |
| `test-reseed-canbindl-gate.ps1` | PASS (26 asserts) |

## Scope

No HealBlackhole, no version bump, no `run-all` registration (Task 7). Commit limited to Clear/Ensure still-busy + Mac clear + new test.
