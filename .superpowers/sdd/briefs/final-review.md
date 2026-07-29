# Final Whole-Branch Review — Zombie-Owner / Reseed Gap / Tunnel-Ready

**Reviewer:** final whole-branch reviewer (read-only)  
**Date:** 2026-07-29  
**Branch:** `fix/zombie-owner-reseed-gap`  
**Range:** `2bcc983` .. `9f16c3a` (HEAD)  
**Ship version:** `20260729.15` (policy `latest` lockstep)  
**Plan:** `docs/superpowers/plans/2026-07-29-zombie-owner-reseed-tunnel-ready.md`  
**Artifacts:** `progress.md` (all tasks complete), `reviews/final-branch-diff.txt`, task 1–8 reports/reviews, Task 8 harness transcript + deploy log

---

## Verdict

**Merge-ready: YES** for plan goals D1–D10.

No Critical / blocking defects. Residual items are Important/Minor quality debt already triaged in task reviews; none reopen the Gap or fail S0 ship abort criteria.

---

## D1–D10 scorecard

| ID | Requirement | Verdict | Evidence |
|---|---|---|---|
| D1 | Gap Ensure never kills for proxy reseed | **PASS** | Task 1 + harness: `Ensure-SessionTunnel` → `kill_count=0`, `foreign_owner_cannot_bind` |
| D2 | Gap bg_init never keeps `needReseed` | **PASS** | `connect.ps1` clears needReseed + `bg_init_reseed_skip`; suite + incident contract |
| D3 | Wait success only if spawn owns local `-R` | **PASS** | `test-wait-local-r-ownership`; empty local PIDs → `$false` + `local_r_not_owned` |
| D4 | Still-busy + no local `-R` → no spawn on that port | **PASS** | `test-stale-forward-wait-init`; `refuse_spawn reason=stale_port_busy`, spawn=0 |
| D5 | Owner backends-down + xray → release ≤65s | **PASS** | `test-proxy-owner-service-coupling`; clock inject t=60 → `released reason=service_dead` |
| D6 | First no_proc exhaust keep-alive (no Release-Stale) | **PASS** | Keepalive suite + S5 arm inspection Win/Mac |
| D7 | ≥120s no_proc + (NOT auth OR NOT banner) → drop | **PASS** | Age 119 keep / 120 drop behavioral; `soft_fail_exhausted_zombie_drop` |
| D8 | Identical S2 reason tokens Win+Mac | **PASS** | Incident contract asserts all 6 tokens in `git-mode.ps1`/`.sh` (+ bg_init) |
| D9 | Deploy-gate PASS, zero skipped new suites | **PASS** | Task 7 gate **132/0**; Task 8 ship deploy **130/0**, no `-SkipTests` |
| D10 | Gap replay checklist (live or harness 2b) | **PASS** | Step 2b harness + transcript quotes S6 A–E; live dual-UI skipped with documented zombie lease mitigation |

---

## STRICT contract spot-check

| Gate | Result |
|---|---|
| S2 tokens present both trees | PASS (`foreign_owner_cannot_bind`, `local_r_not_owned`, `stale_port_busy`, `reason=service_dead`, `stale_non_connect`, `soft_fail_exhausted_zombie_drop`) |
| S3 thresholds locked | PASS (`ServiceDeadSec`/`SERVICE_DEAD_SEC`=60, `NoProcZombieSec`/`NO_PROC_ZOMBIE_SEC`=120, `StillBusyWindowSec`=15) |
| S4 Gap suites behavioral + in `run-all.ps1` | PASS (reseed, wait, stale-forward, proxy-owner, local-pids, incident-contract, incident-harness) |
| S5 forbidden patterns (Gap kill ungated / Wait banner-alone / first keep Release) | PASS per task reviews + incident order asserts |
| Version / policy ship | PASS Win+Mac `20260729.15`, `client-update-policy.json` `latest` match; scripts-only EXE md5 reused (no SFX lie) |
| Mac timeout WARN parity (Task 2 quality hold) | Cleared by `64f2271` |

---

## Triage of named residual findings

| Finding | Source | Blocking? | Disposition |
|---|---|---|---|
| Mac Update on `zombie_drop` less gated than Win | Task 5 Important | **No** | Mac calls `update_cursor_proxy_owner_service_health` without outer `test_is_cursor_proxy_owner`; function body already `test_is_cursor_proxy_owner \|\| return 0` → no-op when not owner. Cosmetic asymmetry only. |
| S6-E healthy `proxy_leg=-L` partly synthetic | Task 8 Important | **No** | Harness writes `healthy_control=1` marker + `Assert ($true)`; real Gap Ensure still logs `proxy_leg=-L` behaviorally; source contract asserts `-L` path. Plan allows Step 2b. Tighten with dedicated healthy Ensure sim or live dual-UI later. |
| `run-all` registration deferred to Task 7 | Task 2 Minor | **No** | Resolved: all Gap suites + harness registered; Task 7/8 gates green. |

---

## Other non-blocking residuals

1. **Docs version lag:** `docs/client-connect.md` still advertises **`20260729.14`** while ship is **`.15`** (Gap marker table itself is present and correct). Follow-up doc bump only.
2. **Live dual-UI Gap replay not run:** zombie owner pid 54996 still held at Task 8; harness 2b accepted by plan. Production daylog confirmation after users close zombie windows remains best-effort.
3. **Mac Ensure kill-order assert soft** (Task 7 Minor): passes if no kill string in extracted body; Win order is hard.
4. **bg_init Gap line in harness is transcript/sim**, not full `connect.ps1` execution — D2 still covered by static + inline sim (plan-allowed).

---

## Risk summary (merge awareness)

| Risk | Severity | Notes |
|---|---|---|
| Dual-Connect Gap reopen | **Low** | CanBindL chokepoint + kill counters locked; incident order asserts |
| False Wait on sticky zombie port | **Low** | Gate A ownership required before success |
| Owner lease stuck forever | **Low** | `service_dead` @60s + `zombie_drop` @120s; live lease may linger until owner Connect exits/adopts |
| Over-skip healthy `-L` | **Low–Med** | S6-E control weak (synthetic); source + Gap-path `-L` still present — watch first post-ship healthy single-window daylogs for `proxy_leg=-L` |
| Mac Sync Update call asymmetry | **Negligible** | Inner owner check makes Update fail-open/no-op |

---

## Merge recommendation

**Approve / merge-ready YES.**

Ship abort criteria (D1–D9 fail, static-only Tasks 1–5, token mismatch, keepalive regression, `-SkipTests`) are **not** triggered. D10 met via plan-allowed harness replay with quoted transcript markers. Optional post-merge polish: bump docs version strings to `.15`, strengthen S6-E healthy Ensure behavioral case, and confirm one live dual-UI daylog when zombie lease is clear.
