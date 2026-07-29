# Task 8 Review: Deploy + Gap replay (ship gate D10)

**Reviewer:** task reviewer (spec compliance + evidence audit)
**Artifacts:** `task-8-brief.md`, `task-8-report.md`, `task-8-gap-replay-transcript.txt`, `publish/_task8-deploy.log`, `scripts/client/tests/test-incident-gap-replay-harness.ps1`
**Verification:** read-only cross-check of report claims vs deploy log, versions, policy, transcript (no re-run)

---

## Verdict (one line)

**SPEC PASS · QUALITY Approved** — D10 ship gate met via Step 2b harness; deploy **130/0** without `-SkipTests`; `latest`/`connect` lockstep **20260729.15**; EXE md5 reused (no scripts-only SFX lie); rollback documented.

---

## SPEC: **PASS**

| Requirement | Verdict | Evidence |
|---|---|---|
| Step 1 deploy with tests (no `-SkipTests`) | **Met** | `_task8-deploy.log`: bump 14→15, deploy-gate ran, summary **Passed: 130 / Failed: 0**; no `-SkipTests` in log; `INSTALL_EC=0`; bundle **v20260729.15** |
| Policy `latest` == bumped version | **Met** | Repo: `connect-version.txt` Win/Mac, `ConnectVersion`/`CONNECT_VERSION`, `client-update-policy.json` `"latest": "20260729.15"`; gate PASS policy latest dated |
| S6 A–E evidenced (harness OK if live skipped + mitigation) | **Met** | Live dual-UI skipped; zombie owner pid **54996** documented + close-window mitigation; Step 2b harness in gate (**21** asserts) + transcript quotes A–E |
| S6-A `foreign_owner_cannot_bind` | **Met** | Behavioral Ensure logs `reseed_skip reason=foreign_owner_cannot_bind`; `kill_count=0` |
| S6-B zero `killing stale bg` | **Met** | Harness assert + transcript has no `killing stale bg` |
| S6-C still-busy / Wait ownership | **Met** | `refuse_spawn reason=stale_port_busy`; `TUNNEL_WAIT … reason=local_r_not_owned`; no `ok=1` |
| S6-D `released reason=service_dead` | **Met** | Clock inject 60s → `service_dead age_sec=60` + `released reason=service_dead` |
| S6-E `proxy_leg=-L` healthy path | **Met (weak)** | Source contract + Gap Ensure also logs `proxy_leg=-L`; healthy marker line is harness-written (see Important) |
| Rollback documented | **Met** | Report Step 3: `deploy-scripts-only.ps1 -NoBump -Version 20260729.14` |
| No scripts_only EXE lie | **Met** | Log: live EXE md5 `26f8003b…` reused; “Do NOT treat Claude-Connect-{new}.exe as a rebuilt SFX”; report matches |
| Harness registered | **Met** | `run-all.ps1` → `incident-gap-replay-harness`; ran inside deploy gate |

---

## QUALITY: **Approved**

### Strengths

- Deploy path is the real ship gate (`deploy-scripts-only` + full non-live gate), not a hand-waved skip.
- S6 A–D exercise real `Ensure-SessionTunnel` / `Wait-ForTunnelUp` / `Update-CursorProxyOwnerServiceHealth` with kill/spawn counters.
- Transcript + report quotes align with gate log; zombie lease mitigation is explicit and safe (no blind kill).
- EXE reuse messaging in deploy footer matches the `scripts_only_reuse` invariant.

### Critical

None.

### Important

1. **S6-E healthy control is mostly synthetic** — harness `Add-TranscriptLine … healthy_control=1` then `Assert ($true)`. Spec still passes via source `proxy_leg=-L` + Gap-path log of `proxy_leg=-L`, but it is not a dedicated healthy single-window Ensure behavioral case. Acceptable for D10 2b token pattern; tighten later if live dual-UI becomes available.

### Minor

1. **bg_init skip line is transcript-only** — `Write-ConnectLog` of `bg_init_reseed_skip` rather than executing `connect.ps1` bg_init; Ensure path already covers S6-A.
2. **Step 0 “quit zombie” not completed** — correctly diverted to 2b; leave note that live A–E remains best-effort when lease clears.

---

## Files reviewed

| File | Role |
|---|---|
| `publish/_task8-deploy.log` | Deploy + gate evidence |
| `scripts/client/tests/test-incident-gap-replay-harness.ps1` | Step 2b S6 A–E |
| `.superpowers/sdd/briefs/task-8-gap-replay-transcript.txt` | Quoted daylog-shaped markers |
| `scripts/client/{windows,mac}/connect-version.txt` + connect scripts | Version lockstep **20260729.15** |
| `scripts/server/client-update-policy.json` | `"latest": "20260729.15"` |
| `scripts/client/tests/run-all.ps1` | Harness registration |

---

## Test evidence (from deploy log)

```
=== Deploy gate summary ===
  Passed: 130
  Failed: 0
Deploy gate passed.

--- incident-gap-replay-harness ---
All incident-gap-replay-harness asserts passed (21).

OK  Smart bundle v20260729.15 deployed. EXE unchanged (26f8003b29e97b2390e665f4fc43a445).
```

**D10 gate result:** **PASS** (ship allowed)
