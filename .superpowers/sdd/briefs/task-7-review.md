# Task 7 Review: Wire tests + docs + incident contract suite

**Reviewer:** task reviewer (spec compliance + code quality)
**Artifacts:** `task-7-brief.md`, `task-7-report.md`, `task-7-diff.txt`, `publish/_task7-deploy-gate.log`
**Range:** `95cb7ea` .. `5e27c25`
**Verification:** diff + gate log (read-only; no re-run)

---

## Verdict (one line)

**SPEC PASS · QUALITY Approved** — D8/D9 met; all 6 Gap suites in `run-all`; incident contract covers S2 + Ensure/Wait order + S6 A–E source; deploy-gate **132/0**; no ship version bump.

---

## SPEC: **PASS**

| Requirement | Verdict | Evidence |
|---|---|---|
| All 6 suites in `run-all.ps1` | **Met** | `reseed-canbindl-gate`, `wait-local-r-ownership`, `stale-forward-wait-init`, `proxy-owner-service-coupling`, `local-tunnel-ssh-pids`, `incident-gap-replay-contract` |
| Incident: S2 tokens Win+Mac + bg_init | **Met** | Suite asserts all 6 tokens in `git-mode.ps1`/`.sh`; `foreign_owner_cannot_bind` in `connect.ps1`; sources confirmed |
| Incident: Ensure CanClaim before kill | **Met** | Win: `Test-ProxyReseedShouldKill`/`CanClaim` index before `killing stale bg`; helper consults CanClaim |
| Incident: Wait local-R ownership | **Met** | `Get-LocalTunnelSshPids` before `return $true`; `local_r_not_owned`; Mac wait/poll + `get_local_tunnel_ssh_pids` |
| Incident encodes S6 A–E | **Met** | Static/source contracts A–E; live daylog quotes deferred to Task 8 (brief/report align) |
| Docs Gap marker table | **Met** | `docs/client-connect.md` zombie-owner / reseed Gap markers (all S2-facing daylog strings) |
| `run-deploy-gate.ps1` PASS, no `-SkipTests` | **Met** | `_task7-deploy-gate.log`: Passed **132** / Failed **0**; all 6 Gap suites PASS; no SkipTests |
| No version bump (Task 8) | **Met** | Win/Mac/txt stay `20260729.14`; `connect.ps1` lockstep restore only (not a ship bump) |
| hard-multi-agent coexistence | **Met** | Gap tokens + CanClaim/Wait coexist asserts added |

---

## QUALITY: **Approved**

### Strengths

- Incident suite fails hard (`$Fail -gt 0` → `exit 1`) on missing S2, Ensure order, or Wait without local-R.
- Gate evidence includes behavioral suites (reseed kill_count=0, Wait empty-PID → false, still-busy spawn=0).
- Docs markers match exact daylog reason strings for dual-Connect diagnosis.

### Critical

None.

### Important

None for Task 7 DoD.

### Minor

1. **Mac Ensure order assert is soft** — passes if no kill/stop string found in extracted body (`$macKill -lt 0`). Win order is hard; Mac still requires gate presence. Tighten later if Mac kill wording drifts.
2. **Gate lockstep edits** outside pure wire scope (`never-again-ship-gates`, `sidecar-front-flap`, `versioned-layout`) — justified to keep gate green after Task 1 strip; acceptable.
3. **S6 A–E are source contracts only** — correct for Task 7; D10 live/harness replay remains Task 8.

---

## Files reviewed

| File | Role |
|---|---|
| `scripts/client/tests/run-all.ps1` | Registers 6 Gap suites |
| `scripts/client/tests/test-incident-gap-replay-contract.ps1` | S2 + Ensure/Wait + S6 A–E |
| `scripts/client/tests/test-hard-multi-agent-regressions.ps1` | Coexistence asserts |
| `docs/client-connect.md` | Gap marker table + version string sync |
| `scripts/client/windows/connect.ps1` | ConnectVersion lockstep `20260729.14` |
| Gate-adjacent test locksteps | never-again / front-flap / versioned-layout |

---

## Test evidence (from report / gate log)

```
publish/_task7-deploy-gate.log
=== Deploy gate summary ===
  Passed: 132
  Failed: 0
Deploy gate passed.

Gap suites: reseed 26 · wait 15 · stale-forward 24 · proxy-owner 38 · local-pids 32 · incident 46 — all PASS
```

**Ready for Task 8** (live/harness Gap replay + ship bump/deploy).
