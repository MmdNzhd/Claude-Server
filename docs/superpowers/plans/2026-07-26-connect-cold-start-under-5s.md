# Connect Cold-Start Under 5s Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `scripts/server/skills/parallel-phased-execution/SKILL.md` (waves per step; same-file writes serialize; TDD RED then GREEN; Coordinator→Workers→Verifier). Also use task review after each Task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Commits:** Only when the user authorizes — do not commit until asked. Bump client version once per shippable slice that changes connect behavior.
>
> **Related prior plan:** `docs/superpowers/plans/2026-07-25-connect-speed-stability-logging.md` (mount BG / logging integrity). This plan is **pre-menu cold-start only** — do not reopen mount-BG honesty work unless a regression appears.

**Goal:** Cut Windows Claude Connect click-to-project-menu wall time from ~23–24s to **≤5s** on a healthy Smart laptop (script-first `Desktop\Claude-Connect`, versions already match, sshd/firewall already OK).

**Architecture:** Fix false EXE content-drift that forces Quiet update SSH+checksum work; collapse redundant preflight heal; stop paying a second firewall probe and stop pre-warming reverse tunnel+sidecar before the project menu (Mac already defers tunnel until after pick). Keep port acquire + key install + forward SSH for mounts before menu. Measure with day-log timestamps (`BOOTSTRAP` → `SESSION` → `project_menu_shown`).

**Tech Stack:** PowerShell 5.1 (`connect.ps1`, `connect-preflight.ps1`, `connect-bootstrap.ps1`, `connect-update.ps1`, `git-mode.ps1`, `cursor-proxy-sidecar.ps1`), `connect.bat`, client tests under `scripts/client/tests/`, publish via `publish/publish.ps1`.

## Evidence refs

| Item | Value |
|------|--------|
| Session | `2c9c5515be48` (2026-07-26), client `20260725.41`, slot 0 / port 20020 |
| Day log | `%USERPROFILE%\.config\claude-connect\logs\connect-YYYYMMDD.log` |
| Measured | BOOTSTRAP → session start ~8.7s; session start → `project_menu_shown` ~14.7s; **click→menu ~23–24s** |
| Smoking gun | `local_exe_missing drift=1` / `drift_gate=exe_mismatch` while script versions match — publish strips `Claude-Connect.exe` from live folder; versioned `Desktop\Claude-Connect-{VER}.exe` not in `Get-LocalConnectExePath` |
| Firewall | `Get-NetFirewallRule` ~0.9–1.6s × Ensure#1 + Ensure#2 ≈ ~2s |
| Tunnel | `Initialize-SessionBgTunnel` at connect.ps1:1849 before menu; Mac defers until after project pick (`connect.sh` ~795) |
| Snapshot commit | `5003b45` (pushed to `MmdNzhd/main`) |

## Global Constraints

- Client version at plan write: `20260725.41`. Bump `$script:ConnectVersion` / `CONNECT_VERSION` / `connect-version.txt` / `connect.bat` guard together when shipping behavior change.
- No Persian in `*.ps1` / `*.bat` / `*.sh`.
- Project hooks stay `{"version":1,"hooks":{}}`.
- Agents: Windows-MCP FileSystem/PowerShell first when ready; `laptop-exec` for git/rg.
- Prefer ≤4 parallel `laptop-exec`; ~8 parallel windows-mcp when hybrid.
- Never store passwords/tokens in plan or logs.
- Hotspot single-writer files (never parallel-write): `windows/connect.ps1`, `git-mode.ps1`, `connect-update.ps1`.
- Designer forks: out of scope unless a shared helper change forces a one-line sync.
- Do **not** re-split `Get-Mounts` into parallel SSH (already one batched call; cache hit ~37ms).

## Anti-patterns / hard rejects

- Treating missing local EXE as drift when deploy is **script-first** (publish intentionally omits EXE from `Desktop\Claude-Connect\`).
- Removing `Acquire-TunnelPort` / `Install-ServerKey` / Ensure#1 hard-fail from Server setup.
- Pre-warming tunnel again “in background at menu shown” if that still blocks `project_menu_shown` — defer must be **after** menu is interactive (or true fire-and-forget that never gates the menu Step).
- Skipping Quiet update entirely forever without a version check (stale clients must still repair).
- Parallel writers into the same hotspot file in one wave.

## Admit criteria (plan-level)

1. Automated: new/updated tests GREEN; full `scripts\client\tests\run-all.bat` exit 0 (or document any pre-existing unrelated flake with evidence).
2. Live Smart laptop: one clean Connect run; day log shows:
   - no `local_exe_missing drift=1` when versions match and script-first deploy
   - no second `Ensure-LaptopSshReady` / duplicate firewall query between Ready and menu
   - no `Initialize-SessionBgTunnel` / sidecar / `PROXY_HEALTH` **before** `INTERACTIVE: project_menu_shown`
   - wall: `BOOTSTRAP`/`SESSION` markers → `project_menu_shown` **≤5s** on healthy machine (document measured ms)
3. After project pick: tunnel+sidecar still start (log shows Preparing tunnel / PROXY_HEALTH); editor path unchanged.

## File map

| File | Responsibility |
|------|----------------|
| `scripts/client/windows/connect-update.ps1` | EXE candidates; script-first no-drift; optional up-to-date cache; skip checksum SSH when safe |
| `scripts/client/windows/connect-preflight.ps1` | Set `SKIP_HEAL` after successful heal; optional remote-ver handoff |
| `scripts/client/windows/connect-bootstrap.ps1` | Export `CLAUDE_CONNECT_REMOTE_VER` when already fetched |
| `scripts/client/windows/connect.ps1` | Remove Ensure#2; set `LaptopFirewallOk` after Ensure#1; remove pre-menu `Initialize-SessionBgTunnel`; firewall cache in `Test-LaptopSshReady` |
| `scripts/client/git-mode.ps1` | Only if tunnel helpers need “first tunnel after pick” comments/guards |
| `scripts/client/tests/*` | RED→GREEN contracts |
| `publish/publish.ps1` | Optional script-only marker — only if Task 1 chooses marker approach |
| `docs/client-connect.md` | One short note: tunnel after project pick (Mac parity) |

## Trade-offs

1. **Script-first EXE drift**
   - **A (chosen):** If no local EXE in candidate paths **and** local `connect-version.txt` equals remote version, treat EXE gate as **N/A** (`$null` / skip checksum SSH) — log `drift_gate=script_only_ok`. Still fetch checksums / repair when version newer OR when a local EXE **exists** and hashes mismatch.
   - **B:** Add versioned `Desktop\Claude-Connect-{VER}.exe` to `Get-LocalConnectExePath` and hash it.
   - **Why A:** Matches publish intent (folder is scripts-only; versioned EXE is distribution artifact). B still pays checksum SSH every cold start.
2. **Tunnel deferral**
   - **A (chosen):** Delete pre-menu warm at connect.ps1:1849; first tunnel at existing post-pick path ~1996 (Mac parity).
   - **B:** Start tunnel async at menu shown without awaiting.
   - **Why A:** Simpler; menu never waits; Mac already A. Cost: first pick shows “Preparing tunnel” (acceptable).
3. **Ensure#2**
   - **A (chosen):** Remove Ensure#2; set `$script:LaptopFirewallOk=$true` when Ensure#1 in Server setup succeeds.
   - **B:** Keep Ensure#2 but cache firewall rule for session.
   - **Why A+light cache:** Remove duplicate call entirely; still add short session cache inside `Test-LaptopSshReady` for session-loop / reverse-ssh paths.

## Target timing budget (healthy path)

| Phase | Today (approx) | Target |
|-------|----------------|--------|
| Preflight (bootstrap+heal+update nested PS + SSH) | ~8.7s | ≤2.0s |
| Server setup (port/key/Ensure#1) | ~4–6s | ≤2.5s (no Ensure#2) |
| Tunnel+sidecar before menu | ~7.5s | **0** (deferred) |
| Load mounts + menu | ~0.5–1s | ≤0.5s |
| **Click → menu** | **~23–24s** | **≤5s** |

---

### Task 1: Script-first EXE drift = no contentDrift (P0)

**Files:**
- Modify: `scripts/client/windows/connect-update.ps1` (`Get-LocalConnectExePath` 706–717, `Test-LocalExeMatchesRemoteHash` 733–754, drift gate ~1020–1054)
- Create: `scripts/client/tests/test-connect-update-script-only-drift.ps1`
- Optional: `publish/publish.ps1` only if adding marker file

**Interfaces:**
- Consumes: remote version string, local `connect-version.txt`, optional local EXE path
- Produces: `Test-LocalExeMatchesRemoteHash` returns `$null` (N/A) when script-only + versions equal; log `drift_gate=script_only_ok`; no `checksums.txt` SSH when gate short-circuits before fetch

**Write-set:** `connect-update.ps1`, new test file (disjoint from Task 2/3 until Task 4 version bump)

- [ ] **Step 1: Write the failing test**

Create `scripts/client/tests/test-connect-update-script-only-drift.ps1` that:
1. Dot-sources or extracts/parses `Get-LocalConnectExePath` + `Test-LocalExeMatchesRemoteHash` + the drift-gate decision (prefer testing via a small exported helper if needed — if helpers are script-private, assert by running update in a temp `$ScriptDir` with mocked SSH).
2. Fixture: temp dir with `connect-version.txt` = `20260725.41`, Windows scripts present, **no** `Claude-Connect.exe`.
3. Mock remote version = same; mock remote checksums containing `Claude-Connect.exe` hash.
4. Assert: exit path is `up_to_date` / `contentDrift` stays `$false`; log must **not** contain `local_exe_missing drift=1` as a reason that forces repair; must contain `drift_gate=script_only_ok` (or equivalent after GREEN).

Minimal expected assertion shape after GREEN:

```powershell
# After implement: script-only + version match must not set contentDrift
Assert ($log -match 'drift_gate=script_only_ok') 'script-only deploy must skip EXE drift'
Assert ($log -notmatch 'drift_gate=exe_mismatch') 'must not treat missing EXE as mismatch when versions equal'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell -NoProfile -File scripts\client\tests\test-connect-update-script-only-drift.ps1`
Expected: FAIL (today: `local_exe_missing drift=1` / `exe_mismatch`)

- [ ] **Step 3: Write minimal implementation**

In `connect-update.ps1`, change drift gate so that when `-not $versionNewer`:

1. If `Get-LocalConnectExePath` returns `$null` **and** local version equals remote version → set `$contentDrift = $false`, log `drift_gate=script_only_ok`, **do not** call `Invoke-SshCat … checksums.txt` (or call only if a local EXE exists).
2. If local EXE exists → keep current hash compare via `Test-LocalExeMatchesRemoteHash`.
3. If version newer → unchanged repair path.

Also update `Test-LocalExeMatchesRemoteHash`: when `$local` is null, return `$null` (N/A) instead of `$false` **only when** caller already knows versions match — **or** keep function strict and put script-only short-circuit entirely in the drift gate before calling it. Prefer gate-level short-circuit (clearer).

```powershell
# Drift gate sketch (replace the version-match checksum block)
if (-not $versionNewer) {
    $localExe = Get-LocalConnectExePath
    if (-not $localExe) {
        $contentDrift = $false
        Write-UpdateFileLog 'drift_gate=script_only_ok'
    } else {
        $remoteSums = Invoke-SshCat -Target $ep.Target -RemotePath "$RemoteBundle/checksums.txt"
        # ... existing exeMatch / legacy full compare using $localExe ...
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell -NoProfile -File scripts\client\tests\test-connect-update-script-only-drift.ps1`
Expected: PASS

- [ ] **Step 5: Commit** (only if user authorized)

```bash
git add scripts/client/windows/connect-update.ps1 scripts/client/tests/test-connect-update-script-only-drift.ps1
git commit -m "fix(connect): treat script-only deploy as no EXE content drift"
```

---

### Task 2: Skip duplicate heal after preflight success (P0)

**Files:**
- Modify: `scripts/client/windows/connect-preflight.ps1` (~74–77)
- Modify: `scripts/client/tests/test-connect-bat-max-ps-starts.ps1` (if contract needs env assert) **or** add `test-connect-preflight-skip-heal.ps1`

**Interfaces:**
- Consumes: heal exit code from `Invoke-PreflightScript`
- Produces: `$env:CLAUDE_CONNECT_SKIP_HEAL = '1'` after heal exit 0 so `connect.ps1` second heal is skipped

**Write-set:** `connect-preflight.ps1` + one test file

- [ ] **Step 1: Write failing test** asserting preflight sets `SKIP_HEAL` after heal success (parse source or run preflight with stubs).

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

```powershell
# After successful heal in connect-preflight.ps1
if ($healExit -eq 0 -or $null -eq $healExit) {
    $env:CLAUDE_CONNECT_SKIP_HEAL = '1'
}
# If heal was skipped because already set, leave as-is.
# If healPath missing, do not force-skip forever incorrectly — only set after actual success or when heal was not needed because SKIP already 1.
```

Prefer: set `SKIP_HEAL=1` only when heal ran and exited 0, **or** when heal was skipped because env already 1. Do not set when heal exited 2 (redirect).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit** (if authorized)

```bash
git commit -m "perf(connect): skip duplicate heal after preflight success"
```

---

### Task 3: Defer tunnel+sidecar until after project pick (P0)

**Files:**
- Modify: `scripts/client/windows/connect.ps1` (remove/gate line ~1849; keep ~1996)
- Modify: `scripts/client/tests/test-connect-pipeline.ps1` (line ~46 assertion)
- Modify: `scripts/client/tests/test-git-mode-deep.ps1` (~234 if asserts pre-warm)
- Optional docs: `docs/client-connect.md` one sentence Mac parity

**Interfaces:**
- Consumes: `$Alias`, `$sshCfg`, post-pick `$script:SessionBgTunnel`
- Produces: no `Initialize-SessionBgTunnel` between Ready and `project_menu_shown`; first call on project pick path

**Write-set:** `connect.ps1` + tests (serialize vs Task 4 if both touch connect.ps1 — **merge Tasks 3+4 into one wave serialized on connect.ps1**)

- [ ] **Step 1: RED** — flip pipeline test expectation:

```powershell
# test-connect-pipeline.ps1
Assert ($src -match 'Initialize-SessionBgTunnel') "$rel still defines/uses session bg tunnel"
# Replace pre-warm-after-Ready assert with:
Assert ($src -notmatch '(?s)Mark-BootstrapDone.*?Initialize-SessionBgTunnel.*?menuLoop') `
  "$rel must not pre-warm tunnel between Ready and menuLoop"
# Or simpler structural: Ready block must not call Initialize-SessionBgTunnel before :menuLoop
```

Write a precise regex that matches today’s buggy order (Ready → Ensure → Initialize-SessionBgTunnel → menuLoop) and fails when that order remains.

- [ ] **Step 2: Run pipeline test — expect FAIL on new assert once written against desired contract…**  
  Actually: write assert for **desired** contract; run against current tree → FAIL; then implement.

- [ ] **Step 3: GREEN** — delete or comment-remove:

```powershell
# REMOVE from pre-menu boot (connect.ps1 ~1849):
# $null = Initialize-SessionBgTunnel -Alias $Alias -SshCfgPath $sshCfg -Quiet

# KEEP post-pick (~1996) and recovery/M-key sites.
```

Ensure `$script:SessionBgTunnel = $null` remains so post-pick path always starts tunnel.

- [ ] **Step 4: Run** `test-connect-pipeline.ps1` + `test-git-mode-deep.ps1` — PASS

- [ ] **Step 5: Commit** (if authorized)

```bash
git commit -m "perf(connect): defer reverse tunnel until after project pick"
```

---

### Task 4: Remove Ensure#2 + session firewall cache (P1)

**Files:**
- Modify: `scripts/client/windows/connect.ps1` (`Test-LaptopSshReady` ~629–668, Ensure#1 ~858, Ensure#2 ~1833–1843)
- Modify: `scripts/client/tests/test-live-ssh-ready.ps1` and/or `test-hard-multi-agent-regressions.ps1` if they require Ensure#2 / `FAIL LAPTOP_SSH_BOOT` at boot

**Interfaces:**
- Consumes: Ensure#1 result in `Initialize-ServerSession`
- Produces: `$script:LaptopFirewallOk = $true` on Ensure#1 success; session cache skip for `Get-NetFirewallRule`; no Ensure#2 before menu

**Write-set:** `connect.ps1` — **same hotspot as Task 3 → execute in same Worker after Task 3 or single Worker owns both**

- [ ] **Step 1: RED** — test that source has at most one `Ensure-LaptopSshReady` call between Server setup and `:menuLoop` (or that Ready block does not call it).

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: GREEN**

```powershell
# In Initialize-ServerSession after Ensure#1 success (~858):
$script:LaptopFirewallOk = $true

# In Test-LaptopSshReady: if $script:LaptopFirewallCheckedOk -eq $true, skip Get-NetFirewallRule

# Remove Ensure#2 block (~1833-1843) entirely (or no-op if LaptopFirewallOk already true — prefer remove).
```

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit** (if authorized)

```bash
git commit -m "perf(connect): drop duplicate laptop SSH ensure before menu"
```

---

### Task 5: Optional preflight version SSH dedupe (P1)

**Files:**
- Modify: `connect-bootstrap.ps1`, `connect-preflight.ps1`, `connect-update.ps1`
- Test: extend Task 1 test or add `test-connect-preflight-ver-handoff.ps1`

**Interfaces:**
- Produces: `$env:CLAUDE_CONNECT_REMOTE_VER` set by bootstrap; update uses it when present to skip second `cat connect-version.txt`

**Write-set:** bootstrap + preflight + update — wave after Tasks 1–4 stable, or parallel only if Task 1 already landed update.ps1 changes (serialize update.ps1)

- [ ] Steps: RED → implement env handoff → GREEN → commit if authorized

Skip this task if live Admit already ≤5s after Tasks 1–4.

---

### Task 6: Version bump + live Admit (P0 gate)

**Files:**
- `scripts/client/windows/connect.ps1` (`$script:ConnectVersion`)
- `scripts/client/mac/connect.sh` (`CONNECT_VERSION`)
- `scripts/client/windows/connect-version.txt`, `mac/connect-version.txt`
- `scripts/client/windows/connect.bat` version guard
- Deploy: `publish\publish.bat` with `-SmartOnly` (or project’s standard Smart-only flags)

**Admit:**
1. `scripts\client\tests\run-all.bat` → exit 0
2. Kill stray Connect; launch `Desktop\Claude-Connect\connect.bat`
3. Parse day log for session id; compute ms to `project_menu_shown`; confirm ≤5000ms
4. Pick a project; confirm tunnel+sidecar logs appear **after** menu
5. Record numbers in wrap-up

- [ ] **Step 1:** Bump version (e.g. `20260726.01` — use next sequential per repo convention)
- [ ] **Step 2:** Publish/deploy Smart client to Desktop
- [ ] **Step 3:** Live measure + document
- [ ] **Step 4:** Commit version bump if authorized

---

## Wave plan (Stage 4)

| Wave | Workers | Owns (write-set) | Gate |
|------|---------|------------------|------|
| W1 | Worker A | Task 1: `connect-update.ps1` + new drift test | Drift test PASS |
| W1 | Worker B | Task 2: `connect-preflight.ps1` + skip-heal test | Skip-heal test PASS |
| W2 | Worker C (single) | Tasks 3+4: `connect.ps1` + pipeline/ssh-ready tests | Pipeline + ssh-ready PASS |
| W3 | Worker D (optional) | Task 5 if still >5s | Handoff test PASS |
| W4 | Parent / Worker E | Task 6 version + full suite + live Admit | ≤5s + suite green |

Verifier after each wave: re-run that wave’s tests; do not advance on “Worker DONE” alone.

## Out of scope

- Parallelizing folder/`Get-Mounts` SSH
- socks∥http sidecar parallelism (P2 — only if still over budget after W2)
- PROXY_HEALTH defer beyond tunnel defer (comes free with Task 3)
- Mac cold-start rewrite (already deferred tunnel)
- Designer connect

## Self-review

1. **Spec coverage:** EXE drift, SKIP_HEAL, tunnel defer, Ensure#2/firewall, optional SSH dedupe, live Admit — each has a Task.
2. **Placeholders:** none intentional; Task 5 explicitly skippable with Admit criterion.
3. **Type consistency:** `LaptopFirewallOk`, `SessionBgTunnel`, `CLAUDE_CONNECT_SKIP_HEAL`, `drift_gate=script_only_ok` used consistently.
