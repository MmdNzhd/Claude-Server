# Connect Windows UX + Perf Fix Implementation Plan

> **For agentic workers:** REQUIRED: `~/.cursor/skills/parallel-phased-execution/SKILL.md` (waves per step; same-file writes serialize; TDD RED then GREEN; Coordinator→Workers→Verifier). Also use task review after each Task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Commits:** Authorized for this execution run — commit after each Task gate passes (do not amend baseline `6675d76`).

**Goal:** Make Windows Claude Connect start fast, quiet, and non-admin by default: kill the long pre-UAC wait, stop flash CMD/PS windows, stop mount-check double-timeouts (~56s), stop launching Cursor as Administrator, and stop sticky wrong `REMOTE_USER` / console noise.

**Architecture:** Keep Connect’s ability to elevate *when needed* (sshd / firewall / `administrators_authorized_keys`), but stop elevating the whole UI on every launch. Collapse bat bootstrap into one hidden preflight. Make mount health checks fail-fast (no 12s×2×2). De-elevate Cursor reliably. Harden `connect.conf` username edits. Redirect Cursor stderr away from the Connect console.

**Tech Stack:** PowerShell 5.1 (`connect.bat` / `connect.ps1` / `connect-ui.ps1` / `git-mode.ps1` / `editor-launch.ps1`), bash `claude-mount.sh`, client regression tests under `scripts/client/tests/`, publish via `publish/publish.bat`.

**Evidence session:** laptop day log `connect-20260723.log` sessions `a197489f0997` + `4defd864287f` (18:55–19:02); server `~/.claude/logs/connect-20260723.log` (~2.7MB, forbid_shrink flood). Client version `20260723.12`.

## Global Constraints

- Client version bump when shipping: bump `$script:ConnectVersion` / `CONNECT_VERSION` and `connect.bat` guard together (current `20260723.12`).
- No Persian in `*.ps1` / `*.bat` / `*.sh` (English only).
- Do not break designer forks unless a shared helper changes; mirror critical patterns if shared.
- Prefer ≤4 parallel `laptop-exec` when agents implement; project hooks stay empty.
- Never store passwords/tokens in plan or logs.
- Publish client ZIPs from smart Windows laptop after client changes (`publish\publish.bat`); server `claude-mount.sh` needs `sudo claude-server install` (or deploy path that installs mount).

## Problem inventory (from logs + code)

| ID | Sev | Symptom (user) | Root cause | Evidence |
|----|-----|----------------|------------|----------|
| P0-A | P0 | Takes too long after project select | Double `claude-mount check` with `timeout 12` + SshX retry-on-124; then **redundant** second check for `skipRemount` while FUSE ls hangs on stale SSHFS | `4defd864`: 19:00:25–19:01:28, ~56s of exit=124; tunnel banner OK on 20021 |
| P0-B | P0 | PowerShell/UAC appears late | Always-elevate at `connect.ps1` start **after** long unelevated bat chain (bootstrap/heal/update) + unelevated boot then RunAs | `connect.ps1` ~44–86; `connect.bat` multi-PS; `elevated=yes` |
| P0-C | P0 | Multiple unnecessary CMD windows flash | Bat `/MIN cmd` self-reexec + many `powershell` without `-WindowStyle Hidden` + unelevated→elevated double boot; `connect-preflight.ps1` **missing** so Stage-6 fast path never runs | `connect.bat` 5–9, 57–143, 269–272; preflight absent |
| P0-D | P0 | Cursor Admin / mutex / updates disabled | `NonElevatedLauncher` fails `win32=5` → `elevated_direct_fallback`; Cursor inherits admin token → mutex + “running as Admin in user setup” | `PROC_START_FAIL … win32=5` then `elevated_direct_fallback`; window title `[Administrator]` |
| P1-A | P1 | auth failed / password / testsmart | Sticky `REMOTE_USER=testsmart` in shared `connect.conf`; config save **wipes** other keys; no username validation | `a197489f0997` FAIL `remote_user=testsmart`; save at connect.ps1 ~1270/1311 |
| P1-B | P1 | Syncing Cursor auth is slow even when skipped | Skip path still enumerates many Cursor processes (`personal_cursor_dominant`); 16 personal + 9 profile | auth step ~6.8–9.6s; AUTH_WARN |
| P1-C | P1 | Noisy LOG_SYNC_SKIP log spam | `forbid_shrink` by design when local≪remote; INFO spam + remote stat tax; server log bloated | 16+ skips in one session; remote ~2.7MB vs local ~0.5MB |
| P1-D | P1 | Extra console noise from Cursor stderr | Cursor Electron stderr (punycode, disable-http2 warn, mutex, TracingService) inherits Connect console — no redirect on Cursor Start-Process | User paste after “Opening Cursor” |
| P2-A | P2 | Reconnect ~15s | Static bootstrap hint, not measured | `Write-BootstrapHint` |
| P2-B | P2 | SSH tax ~500ms×N | No ControlMaster on Windows SshX; many one-shot remotes | expected; reduce N via P0-A |
| P2-C | P2 | UPDATE connect-version.txt missing / exe promote fail | Server missing `/usr/local/share/claude-client/connect-version.txt`; Desktop exe locked | `449f07deaaed` WARN; separate ops fix |

**Out of scope for this plan:** ControlMaster on Windows SshX; redesign of log sync merge algorithm beyond demoting noise; fixing personal vs profile Cursor policy (user can keep personal open); Sepidz-only packaging beyond shared client.

## File map

| File | Responsibility |
|------|----------------|
| `scripts/client/windows/connect-preflight.ps1` | **NEW** — single hidden PS: run-id, day-log bootstrap, bootstrap/heal/update orchestration; exit codes for bat |
| `scripts/client/windows/connect.bat` | Prefer preflight path; hide remaining helper starts; optional early elevate messaging |
| `scripts/client/windows/connect.ps1` | Defer always-elevate; reuse recover health; skip SshX retry for mount check; conf username save without wipe; quieter auth skip |
| `scripts/client/git-mode.ps1` | Fail-fast mount check / optional no-retry flag; recover returns health clearly |
| `scripts/server/claude-mount.sh` | Harder kill on hung `ls` (`timeout -k`); treat stuck mount as not healthy quickly |
| `scripts/client/editor-launch.ps1` | Prefer NE launch; redirect Cursor stdout/stderr; shorten dead-wait before fallback; log why win32=5 |
| `scripts/client/connect-ui.ps1` | Demote forbid_shrink to DEBUG / rate-limit; optional quieter CONTEXT sync |
| `scripts/client/tests/*.ps1` | Regression: elevation policy, mount-check no double timeout, conf save, bat preflight |
| `CLAUDE.md` / `docs/client-connect.md` | Update “always elevate at start” invariant → elevate-when-needed |

## Trade-offs

1. **Elevation policy**
   - **A (chosen):** UI unelevated by default; `Invoke-LaptopAdminOps` / explicit RunAs only when sshd/firewall/keys need it.
   - **B:** Keep always-elevate but hide bat + restore preflight only.
   - **Why A:** User’s top pain is UAC delay every start; laptop SSH often already healthy. Risk: mid-session UAC if repair needed — acceptable and rarer.
2. **Mount check on 124**
   - Treat as unhealthy immediately (no SshX retry) vs keep retry.
   - **Chosen:** no retry for `check` / health probes; still retry generic SSH once for other cmds.
3. **Cursor stderr**
   - Redirect to log file under `%USERPROFILE%\.config\claude-connect\logs\` vs `NUL`.
   - **Chosen:** redirect to `cursor-launch-YYYYMMDD.log` (debugable) + do not show on Connect console.

---

### Task 1: Fail-fast mount health (biggest session delay)

**Files:**
- Modify: `scripts/client/git-mode.ps1` (`Test-ProjectMountHealthy`, `Invoke-RecoverIfNeeded`)
- Modify: `scripts/client/windows/connect.ps1` (session loop skipRemount / SshX)
- Modify: `scripts/server/claude-mount.sh` (`_is_mounted` / `cmd_check`)
- Test: `scripts/client/tests/test-git-mode-deep.ps1` (or new focused test)

- [ ] **Step 1: Write failing test** — assert that when first `check` returns exit 124 / unhealthy, connect path does **not** issue a second identical `timeout 12 … check` before recover/up; assert `skipRemount` reuses prior `recoverCheckOk` / unhealthy result.

- [ ] **Step 2: Run test — expect fail**

- [ ] **Step 3: Implement**
  - Add `-NoRetryOnTimeout` (or cmd-class) to SshX path used by mount check only.
  - After `Invoke-RecoverIfNeeded`, if check already failed, set `$skipRemount = $false` **without** calling `Test-ProjectMountHealthy` again.
  - In `claude-mount.sh` `_is_mounted`: use `timeout -k 1 2 ls` (or skip ls when mount’s tunnel port ≠ current `TUNNEL_PORT` / prefer recover).
  - Optionally shorten outer check timeout from 12→6 once `-k` works.

- [ ] **Step 4: Run test — expect pass**

- [ ] **Step 5: Deploy mount script** — `sudo claude-server install` (or targeted deploy) so server `~/.local/bin/claude-mount` picks up `-k`.

- [ ] **Step 6: Commit** after gate passes with message focusing on fail-fast stale SSHFS checks.

---

### Task 2: Restore `connect-preflight.ps1` + quiet bat (extra CMD windows)

**Files:**
- Create: `scripts/client/windows/connect-preflight.ps1`
- Modify: `scripts/client/windows/connect.bat`
- Test: bat/invariant tests under `scripts/client/tests/`

- [ ] **Step 1: Spec exit codes** for preflight (document in file header): 0=ok continue boot, non-zero=abort with message; update path may relaunch bat once.

- [ ] **Step 2: Implement preflight** — fold run-id, day-log bootstrap, `connect-bootstrap.ps1`, heal, `connect-update.ps1` into **one** `-WindowStyle Hidden` powershell invoked by bat when file exists (bat already has `if exist` Stage 6 branch ~17–21).

- [ ] **Step 3: Bat cleanup** — for legacy fallback path, add `-WindowStyle Hidden` to helper powershell starts; keep main `connect-boot` visible. Consider replacing `/MIN cmd` self-reexec with a quieter pattern if tests allow.

- [ ] **Step 4: Test** — `scripts\client\tests\run-all.bat` (or targeted) proves preflight path taken when file present; no regression on version guards.

- [ ] **Step 5: Commit** after gate passes.

---

### Task 3: Elevate-when-needed (UAC delay)

**Files:**
- Modify: `scripts/client/windows/connect.ps1` (top elevation block ~44–86; `Invoke-LaptopAdminOps`)
- Modify: `CLAUDE.md` client invariant row + `docs/client-connect.md`
- Test: elevation / AdminFix tests

- [ ] **Step 1: Write failing test** — cold start without admin does **not** immediately RunAs; RunAs only when `Ensure-LaptopSshReady` / AdminFix path requires it.

- [ ] **Step 2: Implement**
  - Remove/gate “Always elevate the main connect UI” so normal path stays unelevated.
  - Keep `-AdminFix` child with `-Wait` for repairs.
  - Ensure single-instance mutex still works across unelevated UI.
  - windows-mcp ensure must not assume parent is elevated (already documents inherit — verify).

- [ ] **Step 3: Update docs** — replace “Always elevate at start” invariant with “Elevate only for sshd/firewall/authorized_keys repair”.

- [ ] **Step 4: Manual check list** — fresh non-admin double-click: no UAC if sshd OK; UAC only when repair needed.

- [ ] **Step 5: Commit** after gate passes.

---

### Task 4: Cursor must not run as Admin + silence stderr

**Files:**
- Modify: `scripts/client/editor-launch.ps1` (`Start-ProcessAsInteractiveUser`, launch args)

- [ ] **Step 1: Diagnose win32=5** — log token/session details when `NonElevatedLauncher` fails; prefer schtasks `/RL LIMITED` before elevated fallback; reduce dead-wait (already comments ~8–10s).

- [ ] **Step 2: Never attach Cursor to Connect console** — Start-Process with redirected stdout/stderr to `logs\cursor-launch-YYYYMMDD.log` (or `CreateNoWindow` where applicable). Confirm punycode/mutex/TracingService no longer appear in Connect UI.

- [ ] **Step 3: Assert** — process snapshot after launch: profile Cursor `elevated=False` / title without `[Administrator]` when NE path works.

- [ ] **Step 4: Commit** after gate passes.

---

### Task 5: Sticky `REMOTE_USER` + conf wipe

**Files:**
- Modify: `scripts/client/windows/connect.ps1` (config menu save ~1267–1335, ~1534)

- [ ] **Step 1: Failing test** — changing username updates `REMOTE_USER` but **preserves** other `connect.conf` keys; invalid/empty rejected.

- [ ] **Step 2: Implement** — read-modify-write conf map; do not `Set-Content` with only two keys. Optional: warn if username looks like a laptop Windows user (`testsmart`) vs known server users — soft warn only.

- [ ] **Step 3: Pass test + Commit** after gate passes.

---

### Task 6: Quieter logs + faster auth-skip

**Files:**
- Modify: `scripts/client/connect-ui.ps1` (forbid_shrink logging)
- Modify: `scripts/client/windows/connect.ps1` (Syncing Cursor auth skip path)

- [ ] **Step 1: Demote** `LOG_SYNC_SKIP reason=forbid_shrink` to DEBUG or rate-limit once per session after first.

- [ ] **Step 2: Auth skip** — if stamp current, skip expensive `Test-PersonalCursorDominant` / full process snapshot (or defer snapshot to DEBUG). Keep WARN if personal dominant only when sync actually runs.

- [ ] **Step 3: Optional ops** — truncate/rebuild remote day log once if remote≫local (manual or one-shot tool); not required for client UX.

---

### Task 7: Version bump, publish, verify

**Version bumped in repo to `20260723.13`.** User still runs `publish\\publish.bat` on the Smart laptop and does manual acceptance.

- [ ] **Step 1: Bump** `CONNECT_VERSION` / `$script:ConnectVersion` / bat guard in lockstep (e.g. `20260723.13` or next date stamp).

- [ ] **Step 2: Publish** on smart laptop: `publish\publish.bat`.

- [ ] **Step 3: Manual acceptance (user)**
  1. Double-click Connect — no flash CMD storm; UAC absent if SSH already OK.
  2. Select `Claude Code Server` — mount/check path &lt; ~10s when tunnel up (no double 12s timeout).
  3. Cursor opens on profile folder **without** `[Administrator]`; Connect console has no punycode/mutex spam.
  4. Wrong username in conf can be fixed without wiping other keys; `smart` persists.

---

## Verification matrix

| Check | Pass criteria |
|-------|----------------|
| Mount stale | One failed check → recover/up; wall &lt; ~15s typical |
| Bat windows | ≤1 minimized/hidden helper + 1 visible Connect UI |
| UAC | Not on every start; only on repair |
| Cursor | Non-admin profile process; stderr in log file |
| Conf | Username edit preserves keys |
| Tests | `scripts\client\tests\run-all.bat` green for touched areas |


## Wave execution notes (2026-07-23)

- Phase = Task step. Parallel only write-disjoint + dependency-free slices.
- Hotspots (single-writer per wave): `connect.ps1`, `connect.bat`, `editor-launch.ps1`.
- Task 1 waves: RED tests → GREEN (`claude-mount.sh` || `connect.ps1`) → GREEN (`git-mode.ps1` needs SshX API) → verify → deploy mount → commit.
- Task 2: one owner for `connect-preflight.ps1` + `connect.bat` (shared contract).
- Tasks 3 and 5 both touch `connect.ps1` — serialize (Task 3 then Task 5).
- Task 4 only `editor-launch.ps1` — can run after Task 1; parallel with Task 2 if needed.
- Task 6: `connect-ui.ps1` first (disjoint), then auth-skip in `connect.ps1` after Tasks 3/5.
- Task 7 last (version bump).

## Rollback

- Revert client package to previous Desktop ZIP; server mount via previous `claude-mount` from git.
- Elevation policy rollback: restore always-elevate block if sshd repair regresses for non-admin users.

## Why Task/subagents abort mid-wave (ops note)

Cursor kills running Task Workers when the **parent chat receives a new user
message** (`aborted` / `"User aborted/interrupted manually."`). Saying
"continue" mid-wave is the #1 cause. Forum also reports ~256s auto-cancel
mislabeled as user interrupt. **Mitigation:** do not ask the user during an
open wave; prefer Coordinator-direct implementation when the user is chatting;
see `~/.cursor/skills/parallel-phased-execution/SKILL.md`.
