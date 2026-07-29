# Task 4 Review: Owner/service coupling — `service_dead`

**Reviewer:** task reviewer (subagent)  
**Date:** 2026-07-29  
**Artifacts:** `task-4-brief.md`, `task-4-report.md`, `task-4-diff.txt` (BASE `405b4c1` → HEAD `af4d34b`), live `git-mode.ps1` / `git-mode.sh` / test  
**Re-run:** `test-proxy-owner-service-coupling.ps1` → 38/38 PASS; `test-tunnel-no-proc-keepalive.ps1` → ALL CHECKS PASSED

---

## Verdict

**Spec PASS · Quality Approved**

---

## Spec checklist

| Check | Result | Evidence |
|---|---|---|
| S2 `reason=service_dead` Win+Mac | PASS | Win `Release-CursorProxyOwner` log literal; Mac `release_cursor_proxy_owner service_dead` |
| S2 `stale_non_connect` Win+Mac | PASS | Pre-existing Claim/claim adopt paths; test behavioral Claim adopt + static both trees |
| Health update from Sync **and** Complete | PASS | Win `Sync-SessionTunnelProcess` + `Complete-CursorProxyAfterTunnel` (entry+exit); Mac `sync_session_tunnel_forward` + `complete_cursor_proxy_after_tunnel` |
| S3 `SERVICE_DEAD_SEC` / `ServiceDeadSec` = **60** | PASS | Mac `SERVICE_DEAD_SEC=60`; Win default 60; test locks literal + age compare |
| Behavioral t=59 no release / t=60 release | PASS | Clock inject via `CursorProxyHealthNow`; release_count + `reason=service_dead` |
| Matrix #10: `xray_closed` never `service_dead` | PASS | `SessionEverHadProxyLegs=$false` → no release at 120s |
| `SessionEverHadProxyLegs` on `-L` / `busy_healthy` | PASS | Ensure Win+Mac set EverHad on both paths |
| MUST NOT on intentional `xray_closed` | PASS | Update gates on EverHad; early Complete tick clears dead-since when EverHad false |
| No HealBlackhole / version sneak-in | PASS | Diff STAT: 4 files only (ps1/sh/test/report); no version / HealBlackhole |
| First-exhaust keepalive intact (D6) | PASS | Soft-fail keep-alive arm unchanged (no `Release-Stale`); keepalive suite PASS |
| D5 Sync-tick (no Ensure churn) | PASS | Behavioral: `Sync-SessionTunnelProcess` invokes Update |

Mac Step 3 zombie filter: `_process_alive` rejects `Z*` — PASS.

---

## Quality

**Approved.** Scoped fix; TDD suite has static contracts + behavioral timer counters + negative xray_closed + Sync invoke + Claim adopt; throw-on-fail.

### Important (non-blocking)

1. **`run-all.ps1` not registered** — S4 would reject; plan Task 7 wires `proxy-owner-service-coupling`. Same deferral as Task 3; not a Task 4 Spec fail.
2. **Mac Complete ticks Update only at entry** — Win also ticks at exit. D5 is covered by Sync; asymmetry is acceptable.

### Critical

None.

---

## Files in commit (as reviewed)

| File | Role |
|---|---|
| `scripts/client/git-mode.ps1` | `Update-CursorProxyOwnerServiceHealth`, Complete+Sync call sites, EverHad, Release `-Reason` |
| `scripts/client/git-mode.sh` | Mac parity + `SERVICE_DEAD_SEC=60` + `_process_alive` Z filter |
| `scripts/client/tests/test-proxy-owner-service-coupling.ps1` | Static + behavioral 59/60 + negatives |
| `.superpowers/sdd/briefs/task-4-report.md` | Report |

`test-cursor-proxy-lifetime.ps1` correctly left unchanged (does not forbid non-clear release).

---

## One-line return

**Spec PASS · Quality Approved · Critical: none · Important: run-all defer (Task 7); Mac Complete entry-only tick**
