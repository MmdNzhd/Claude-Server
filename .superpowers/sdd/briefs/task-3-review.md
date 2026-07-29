# Task 3 Review: Stale forward Mac `i=0` + refuse spawn when still busy

**Reviewer:** task reviewer (subagent)  
**Date:** 2026-07-29  
**Artifacts:** `task-3-brief.md`, `task-3-report.md`, `task-3-diff.txt` (BASE `64f2271` → HEAD `405b4c1`), live `git-mode.ps1` / `git-mode.sh` / test

---

## Verdict

**Spec PASS · Quality Approved**

---

## Spec checklist

| Check | Result | Evidence |
|---|---|---|
| Mac `local i=0` before while (S5) | PASS | `git-mode.sh` L2012–2013: `local i=0` then `while [ "$i" -lt 8 ]` |
| S2 `stale_port_busy` Win+Mac | PASS | Win Ensure L3415; Mac ensure L1942; both `refuse_spawn reason=stale_port_busy` |
| S3 window = 15 | PASS | Win `StillBusyWindowSec = 15`; Mac `STILL_BUSY_WINDOW_SEC=15`; test locks literal + age 1s/16s |
| Refuse before spawn (D4) | PASS | Abort immediately before `Start-Process ssh` / `ssh -N`; test `spawn_count=0` on busy port |
| Clear markers on release / set on still-busy | PASS | Win Clear L510–516; Mac clear L2021–2027 |
| No HealBlackhole / version sneak-in | PASS | Diff STAT: 3 files only (`git-mode.ps1`, `git-mode.sh`, new test); no version/HealBlackhole strings |

Refuse-only (no rebind) satisfies D4 / S1 (“refuse **or** rebind”).

---

## Quality

**Approved.** Diff is scoped; test has static + behavioral negative (`spawn_count=0`) + positive control + throw-on-fail. Call-order asserts StillBusyAbort before Start-Process.

### Important (non-blocking)

1. **`run-all.ps1` not registered** — S4 would reject; Task 3 notes defer to Task 7. Track there; not a Task 3 Spec fail.
2. **Mac abort behavioral is static-only** — Win Ensure exercised with counters; Mac parity is token/order static. Acceptable for shell helper under this wave’s PS harness.

### Critical

None.

---

## Files in commit (as reviewed)

| File | Role |
|---|---|
| `scripts/client/git-mode.ps1` | LastStale*; `Test-StaleForwardStillBusyAbort`; Ensure refuse |
| `scripts/client/git-mode.sh` | `local i=0`; markers; `stale_forward_still_busy_abort`; ensure refuse |
| `scripts/client/tests/test-stale-forward-wait-init.ps1` | Static + behavioral D4 |

---

## One-line return

**Spec PASS · Quality Approved · Critical: none · Important: run-all defer (Task 7); Mac behavioral static-only**
