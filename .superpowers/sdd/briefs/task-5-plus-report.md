# Task 5+ Report — Preflight skip + firewall cache + live Admit

**STATUS:** DONE  
**ADMIT:** **FAIL** — click→menu **8444 ms** (was 15024 ms; target ≤5000 ms)  
**Suite exit:** **0** (`run-all.ps1`)

---

## 1. Changes shipped (A–E)

### A) Skip Quiet update when bootstrap already current
- `connect-bootstrap.ps1` writes `%TEMP%\claude-connect-preflight.ok` on `skip canon already current` with `SKIP_UPDATE=1`, `REMOTE_VER`, `LOCAL_VER`, and `SKIP_HEAL=1` when `$Here` is healthy.
- `connect-preflight.ps1` reads handoff via `Read-PreflightHandoff`; skips `connect-update.ps1` when `SKIP_UPDATE=1` + `Test-HealthyDeploy`.
- `connect.bat` reads handoff after preflight (same pattern as `claude-connect-run-id.txt`) and sets `CLAUDE_CONNECT_SKIP_UPDATE` / `CLAUDE_CONNECT_SKIP_HEAL` for connect-boot.

### B) Skip heal on healthy current deploy
- Preflight skips heal spawn when handoff `SKIP_HEAL=1` and `Test-HealthyDeploy` passes (connect.bat + connect.ps1 + connect-boot.ps1 + sidecar + version match).
- Heal still runs on bootstrap pull/force, missing files, OUTDATED, exit-2 redirects.

### C) Firewall disk cache (~2s Ensure#1 cut)
- `connect.ps1`: `Test-LaptopFirewallDiskCacheOk` / `Set-LaptopFirewallDiskCacheOk` / `Clear-LaptopFirewallDiskCache` using `%TEMP%\claude-connect-fw-ok.txt` (24h TTL).
- `Test-LaptopSshReady` skips `Get-NetFirewallRule` when sshd Running + cache fresh; invalidates on sshd down, Ensure failure, AdminFix/firewall repair.

### D) Tests (TDD)
- **New:** `test-connect-preflight-skip-update.ps1` — handoff writer/reader contracts.
- **Extended:** `test-connect-preflight-skip-heal.ps1` — handoff skip-heal + bat read order.
- **Extended:** `test-connect-pipeline.ps1` — disk firewall cache contracts.
- Added all three to `run-all.ps1`.

### E) Version + deploy + live Admit
- Bumped to **`20260726.02`** (win/mac connect.ps1/sh, connect-version.txt, drift test fixture).
- Published: `publish.ps1 -SmartOnly -SkipVersionBump` → exit **0**, Desktop\Claude-Connect v20260726.02, server bundle deployed.

---

## 2. Test suite

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\client\tests\run-all.ps1
```

- **Exit: 0** (~159 s wall)
- Focused suites all pass: `test-connect-preflight-skip-update`, `test-connect-preflight-skip-heal`, `test-connect-pipeline`, `test-connect-update-script-only-drift`
- `audit-local-connect.ps1`: all copies **SAFE v20260726.02**

---

## 3. Live Admit (session `3a693c00b402`)

| Metric | Before (v01) | After (v02) | Target | Result |
|--------|--------------|-------------|--------|--------|
| **click → menu** | 15024 ms | **8444 ms** | ≤5000 | FAIL |
| **BOOTSTRAP → menu** | 14129 ms | **7894 ms** | ≤5000 | FAIL |
| session start → menu | 6752 ms | **4505 ms** | — | (informational) |

Launch: `Desktop\Claude-Connect\connect.bat` pid=44696 at **10:21:12.240**  
Menu: **10:21:20.684**

### Log contracts (session `3a693c00b402`)

| Check | Result | Evidence |
|-------|--------|----------|
| No UPDATE spawn on healthy path | **PASS** | No `UPDATE:` lines in session block |
| Bootstrap skip pull | **PASS** | `BOOTSTRAP_PULL: skip canon already current ver=20260726.02` |
| No pre-menu tunnel/sidecar | **PASS** | `PROXY: enabled=0 source=none` only |
| Version match | **PASS** | `CONNECT_VERSION=20260726.02` |

### Key log excerpt

```
[10:21:12.790] BOOTSTRAP: connect.bat start
[10:21:13.860] BOOTSTRAP_PULL: skip canon already current ver=20260726.02 remote=20260726.02
[10:21:16.116] MULTI_INSTANCE: acquired via=connect-boot slot=0
[10:21:16.179] session start v20260726.02
[10:21:17.833] STEP begin: Server setup
[10:21:20.590] STEP end: Server setup ok ms=2755
[10:21:20.684] INTERACTIVE: project_menu_shown mounts=17
```

### Remaining largest spans (honest)

| Span | ms | Notes |
|------|-----|-------|
| connect-boot cold start (skip pull → MULTI_INSTANCE) | ~2256 | PowerShell `-File connect-boot.ps1` + slot gate; no update/heal anymore |
| **Server setup** | **2755** | Down from 4378 (fw cache helped ~1.6s); still 3 SSH hops (key 576, port batch 662, push conf 625) |
| Bootstrap SSH version cat | ~630 | Required cold-path version check |
| Bat/minimized launcher overhead | ~550 | Inner cmd re-exec |

**Estimated savings this task:** ~6560 ms click→menu (15024 → 8444). Preflight heal+update skip (~5.4s) and firewall cache (~1.6s on Server setup) confirmed in logs.

---

## 4. Files changed

| File | Change |
|------|--------|
| `scripts/client/windows/connect-bootstrap.ps1` | Preflight handoff write/clear |
| `scripts/client/windows/connect-preflight.ps1` | Read handoff; skip heal/update on healthy current |
| `scripts/client/windows/connect.bat` | Read preflight handoff for skip flags |
| `scripts/client/windows/connect.ps1` | Disk firewall cache; v20260726.02 |
| `scripts/client/windows/connect-version.txt` | 20260726.02 |
| `scripts/client/mac/connect.sh` | CONNECT_VERSION 20260726.02 |
| `scripts/client/mac/connect-version.txt` | 20260726.02 |
| `scripts/client/tests/test-connect-preflight-skip-update.ps1` | **New** |
| `scripts/client/tests/test-connect-preflight-skip-heal.ps1` | Extended |
| `scripts/client/tests/test-connect-pipeline.ps1` | Firewall cache asserts |
| `scripts/client/tests/test-connect-update-script-only-drift.ps1` | Fixture ver |
| `scripts/client/tests/run-all.ps1` | Register new suites |
| `scripts/client/tests/_live-admit-measure.ps1` | **New** (local measure helper; not in run-all) |

No commit. No push.

---

## 5. Concerns / next cuts

1. **Still ~3.4 s over target** — Server setup SSH batching (merge port acquire + push conf?) and connect-boot startup latency are the next targets.
2. **Bootstrap SSH is still mandatory** for version gate on cold start — acceptable per brief; cannot skip without another check path.
3. **Firewall cache 24h TTL** — safe when sshd stays Running; invalidated on Ensure/AdminFix failure and sshd stop.
4. **Handoff file is session-global in TEMP** — cleared at bootstrap start; bat reads immediately after preflight (same run id correlation).

---

## Return summary

| Field | Value |
|-------|-------|
| STATUS | DONE |
| ADMIT | FAIL |
| measured ms (click→menu) | **8444** |
| measured ms (BOOTSTRAP→menu) | **7894** |
| suite exit | **0** |
