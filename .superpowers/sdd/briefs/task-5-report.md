# Task 5 Report: Sync soft-health - time-box zombie keep-alive

**Status:** DONE  
**Branch:** `fix/zombie-owner-reseed-gap`  
**Commit:** `1ed3939` - `fix(connect): time-box no_proc keep-alive with zombie_drop at 120s`

## Summary

First-budget `soft_fail_exhausted_keep_alive` still returns keep-alive with **no** `Release-StaleTunnelPort` (D6/S5). A separate age gate (`NO_PROC_ZOMBIE_SEC=120`) drops with `soft_fail_exhausted_zombie_drop` + Release when age >= 120 and (NOT auth OR NOT Windows banner). Auth+banner at age >= 120 still keeps the session (dual-UI).

## Changes

| File | Change |
|---|---|
| `scripts/client/git-mode.ps1` | `NoProcZombieSec=120`, `NoProcKeepAliveSince`, `Test-NoProcShouldKeepAlive`, zombie_drop arm, reattach reset, Sync-false owner health update |
| `scripts/client/git-mode.sh` | Mac parity: `NO_PROC_ZOMBIE_SEC=120`, `_no_proc_should_keep`, `soft_fail_exhausted_zombie_drop`, reset on healthy PID |
| `scripts/client/tests/test-tunnel-no-proc-keepalive.ps1` | Kept all old asserts; added zombie_drop/120 static + behavioral age=119/120 cases |
| `scripts/client/tests/test-hard-multi-agent-regressions.ps1` | Coexistence: keep-alive + zombie_drop tokens |

## Contracts

- **D6:** first exhaust keep-alive arm has no `Release-Stale` (S5)
- **D7:** age >= 120 + (NOT auth OR NOT banner) => drop
- **S2:** `soft_fail_exhausted_zombie_drop` Win+Mac
- **S3:** `NoProcZombieSec` / `NO_PROC_ZOMBIE_SEC=120` locked
- **Behavioral:** age=119 NOT auth keep; age=120 NOT auth drop+Release; age=120 auth+banner keep

## Tests

| Suite | Result |
|---|---|
| `test-tunnel-no-proc-keepalive.ps1` | PASS |
| `test-proxy-owner-service-coupling.ps1` | PASS (38) |
| `test-reseed-canbindl-gate.ps1` | PASS (26) |
| `test-hard-multi-agent-regressions.ps1` | PASS (117) |

## Scope

No HealBlackhole, no version bump, no deploy. Unrelated dirty tree left unstaged.
