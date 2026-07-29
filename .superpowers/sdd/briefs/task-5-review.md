# Task 5 Review: Sync soft-health — zombie keep-alive time-box

**Reviewer:** task reviewer (subagent)  
**Date:** 2026-07-29  
**Artifacts:** `task-5-brief.md`, `task-5-report.md`, `task-5-diff.txt` (BASE `af4d34b` → HEAD `95cb7ea` / impl `1ed3939`), live `git-mode.ps1` / `git-mode.sh` / tests  
**Re-run:** `test-tunnel-no-proc-keepalive.ps1` → ALL CHECKS PASSED

---

## Verdict

**Spec PASS · Quality Approved**

---

## HARD verify

| Check | Result | Evidence |
|---|---|---|
| First `soft_fail_exhausted_keep_alive` arm has **no** `Release-StaleTunnelPort` before age gate (S5/D6) | PASS | Win slice to first `return $true` after keep_alive: no Release / no `return $false`; Mac 280-char keep slice: `return 0`, no `return 1` / no `release_stale` |
| `soft_fail_exhausted_zombie_drop` + **120** Win+Mac (S2/S3) | PASS | Win `NoProcZombieSec=120` + zombie_drop after keep gate; Mac `NO_PROC_ZOMBIE_SEC=120` + same token |
| Behavioral age=119 keep / age=120 drop (+ auth+banner keep) | PASS | Suite: 119 NOT auth keep+no Release; 120 NOT auth drop+Release+zombie_drop; 120 auth+banner keep |
| Old keepalive asserts preserved | PASS | All pre-Task-5 asserts still present and green (markers, no_proc arm, Mac return 0, runtime sim no Release) |
| No HealBlackhole / version sneak-in | PASS | Commit `1ed3939` files: git-mode.ps1/sh, keepalive + multi-agent tests, report only |

---

## Spec checklist

| Check | Result |
|---|---|
| D6 first-exhaust keep-alive (no Release-Stale) | PASS |
| D7 age >= 120 + (NOT auth OR NOT banner) → drop | PASS (`Test-NoProcShouldKeepAlive` / `_no_proc_should_keep`) |
| Separate age gate after duration tracking | PASS (keep log → age helper → zombie_drop+Release) |
| Reset Since on healthy reattach | PASS (Win `Try-Reattach`; Mac healthy PID / probe_up) |
| Owner health update on Sync `$false` | PASS (zombie_drop path Win+Mac) |
| S4 static + behavioral counters + throw-on-fail | PASS |
| Suite in `run-all.ps1` | PASS (`tunnel-no-proc-keepalive` already registered) |

---

## Quality

**Approved.** TDD extension keeps dual-UI contract; age gate is a distinct branch; Win Sync behavioral with injectable clock + Release counter; Mac token/threshold parity.

### Important (non-blocking)

1. **Mac keep-alive slice assert still 280-char** — ends mid-comment before zombie_drop; still correct today, but Win-style `keepEnd`-to-first-return would be tighter if Mac arm grows.
2. **Mac zombie_drop calls `update_cursor_proxy_owner_service_health` without an is-owner gate** — Win gates on `Test-IsCursorProxyOwner`; asymmetry is acceptable if Update is no-op when not owner.

### Critical

None.

---

## Files in commit (as reviewed)

| File | Role |
|---|---|
| `scripts/client/git-mode.ps1` | `NoProcZombieSec=120`, `Test-NoProcShouldKeepAlive`, zombie_drop+Release, reattach reset |
| `scripts/client/git-mode.sh` | Mac parity `_no_proc_should_keep` / `soft_fail_exhausted_zombie_drop` |
| `scripts/client/tests/test-tunnel-no-proc-keepalive.ps1` | Old asserts kept + static 120/zombie_drop + behavioral 119/120 |
| `scripts/client/tests/test-hard-multi-agent-regressions.ps1` | Coexistence tokens |
| `.superpowers/sdd/briefs/task-5-report.md` | Report |

---

## One-line return

**Spec PASS · Quality Approved · Critical: none · Important: Mac 280-slice fragility; Mac Update ungated**
