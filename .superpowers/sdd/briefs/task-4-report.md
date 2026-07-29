# Task 4 Report: Owner/service coupling — release empty lease

**Status:** DONE  
**Branch:** `fix/zombie-owner-reseed-gap`  
**Commit:** `713ec57` — `fix(connect): release proxy owner lease on service_dead after 60s`

## Summary

Owner with backends down + xray expected (`SessionEverHadProxyLegs`) now starts a timer and releases with `reason=service_dead` at **>=60s**. Health update runs from **Complete and Sync** so zombies free without Ensure churn. Intentional `xray_closed` (EverHad=false) never `service_dead`. Mac `_process_alive` filters zombie `Z`.

## Changes

| File | Change |
|---|---|
| `scripts/client/git-mode.ps1` | `Update-CursorProxyOwnerServiceHealth`, `ServiceDeadSec=60`, Release `-Reason`, EverHad on `-L`/busy_healthy, Complete+Sync call sites |
| `scripts/client/git-mode.sh` | Mac parity + `SERVICE_DEAD_SEC=60` + Z filter in `_process_alive` |
| `scripts/client/tests/test-proxy-owner-service-coupling.ps1` | Static + behavioral t=59/t=60 + xray_closed negative + Sync invoke + Claim `stale_non_connect` |

## Contracts

- **D5:** release within 60s timer (+5s slack wall) — behavioral clock inject
- **S2:** `reason=service_dead` + `stale_non_connect` Win+Mac
- **S3:** `ServiceDeadSec` / `SERVICE_DEAD_SEC=60` locked
- **Matrix #4:** self owner backends dead >=60s + xray expected => release
- **Matrix #10:** intentional xray_closed => never `service_dead`
- **HARD:** Sync-tick path (not Complete-only)

## Tests

| Suite | Result |
|---|---|
| `test-proxy-owner-service-coupling.ps1` | PASS (38 asserts) |
| `test-reseed-canbindl-gate.ps1` | PASS (26 asserts) |
| `test-tunnel-no-proc-keepalive.ps1` | PASS (first-exhaust keep-alive intact) |

## Scope

No HealBlackhole, no version bump, no `run-all` registration (Task 7). `test-cursor-proxy-lifetime.ps1` unchanged (does not forbid non-clear release).
