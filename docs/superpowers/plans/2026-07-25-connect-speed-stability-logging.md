# Connect Speed + Stability + Logging Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `scripts/server/skills/parallel-phased-execution/SKILL.md` (waves per step; same-file writes serialize; TDD RED then GREEN; Coordinator→Workers→Verifier). Also use task review after each Task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Commits:** Only when the user authorizes — do not commit until asked. Bump client version once per shippable slice that changes connect behavior.

**Goal:** Make Windows Claude Connect feel fast and stable again without lying in day logs: cut remaining critical-path SSH taxes, stop Opening Cursor false-green / sticky editor state, restore Mount BG + log-sync observability, then prune dead code and close Mac/Designer parity gaps.

**Architecture:** Keep mount `up` backgrounded (agents use laptop-exec), but stop pretending MountOk=true and stop paying a sync `timeout 12 claude-mount check` on every pick. Route all day-log writers (including Mount BG child) through the named mutex / seek-EOF path. Make SCORECARD / SESSION_OPEN / VERDICT consume live MountOk + `$script:EditorOpened`. Cut newly exposed auth WaitForExit and redundant Prepare sha256 SSH. TDD: RED tests that fail on today's false-green contracts, then GREEN with minimal code.

**Tech Stack:** PowerShell 5.1 (`connect.ps1`, `connect-ui.ps1`, `git-mode.ps1`, `editor-launch.ps1`, `connect-diagnostic.ps1`, `windows-mcp-laptop.ps1`), bash Mac (`connect.sh`, `git-mode.sh`, `connect-ui.sh`), designer forks, client tests under `scripts/client/tests/`, publish via `publish/publish.bat`.

**Evidence baseline (Smart laptop day logs, measured 2026-07-25):**

| Metric | Jul 24 | Jul 25 | Interpretation |
|--------|--------|--------|----------------|
| Mounting files median (success) | ~15467 ms | ~46 ms | BG mount removed cold SSHFS from UI — real win |
| `MOUNT_BG_STARTED` / body events | 0 / 0 | 18 / **0** | Child log silent — sharing violation |
| Opening Cursor STEP fail rate | 47.8% (11/23) | **68.4%** (13/19) | Stability regress; fail med ~34s |
| Opening ok median (first ok) | ~2544 ms | ~1784 ms | When it works, fine |
| Server setup median (success) | ~11577 ms | ~8897 ms | Still dominant pre-menu tax |
| `LOG_SYNC_OK` | 0 | 0 | Sync broken / never succeeding |
| Prior plan P0-A/B/C/D (2026-07-23) | — | mostly fixed | Leftover: sync mount **check** still on CP |

**Deep discovery artifacts:** `%TEMP%\cc_stage2_deep\{crit,perf,dead}.md` + earlier wave reports under `%TEMP%\cc_stage2\`.

## Global Constraints

- Client version: bump `$script:ConnectVersion` / `CONNECT_VERSION` / `connect-version.txt` / `connect.bat` guard together (tree at plan write: `20260725.38`).
- No Persian in `*.ps1` / `*.bat` / `*.sh` (English only).
- Project hooks stay `{"version":1,"hooks":{}}`. Agents: Windows-MCP FileSystem/PowerShell first when ready; `laptop-exec` for git/rg.
- Do not invent a “3× slower” claim — use measured STEP/SCORECARD/SSH counts.
- Prefer ≤4 parallel `laptop-exec`; ~8 parallel windows-mcp when hybrid.
- Never store passwords/tokens in plan or logs.
- Hotspot single-writer files (never parallel-write): `windows/connect.ps1`, `connect-ui.ps1`, `git-mode.ps1`, `editor-launch.ps1`.
- Designer / Mac: mirror only when Task says so; do not silently diverge invariants.

## Problem inventory

| ID | Sev | Symptom | Root cause | Evidence |
|----|-----|---------|------------|----------|
| P0-S1 | P0 | Still waits after project pick | `Invoke-RecoverIfNeeded` → `Test-ProjectMountHealthy` (`timeout 12`) still sync on CP even when BG `up` | crit.md #22; live `SSH_BEGIN … claude-mount check` after pick |
| P0-S2 | P0 | Opening Cursor often fails ~25–80s | Warm poll up to ~20s + sticky/`EditorSeenOpen` + trust path sets `onFolderNow=$true` without durable `$script:EditorOpened` | fail rate 68%; editor-launch LAUNCH_POLL; connect.ps1:2457–2475 |
| P0-S3 | P0 | Auth step can sit ~5s after mount-BG | `BgAuthStampProc.WaitForExit(5000)` exposed now that mount no longer covers it | connect.ps1 ~2236; crit.md #29 |
| P0-S4 | P0 | Extra SSH every first pick | Prepare sha256 not seeded from Server setup `MOUNT_HASH` | crit.md #20a / leftover #3 |
| P0-L1 | P0 | Mount BG body never in day log | Child `AppendAllText` + `catch {}` while parent holds FileStream (`FileShare.ReadWrite` still blocks exclusive assumptions) | MOUNT_BG_STARTED=18, BEGIN/OK/FAIL=0 |
| P0-L2 | P0 | Logs claim MountOk / editor=open falsely | Optimistic `Ok=$true` + SESSION_OPEN `-MountOk $true`; SCORECARD prefers unwired `$script:EditorOpened` | connect.ps1:2161–2162, 2506; connect-ui.ps1:1482 |
| P0-L3 | P0 | Server day log lags / mkdir_timeout | non-Force mkdir budget 3s + `find -mtime +1` in same SSH; `Complete-ConnectLogAsyncDrain` clears `Needed` before Force can fail | connect-ui.ps1:476,650–674,913–937; LOG_SYNC_FAIL×10 |
| P1-T1 | P1 | Tests green while contracts lie | Presence-only / wrong isolation for mount-bg, scorecard, SESSION_FILTER | stage-2 wave A |
| P2-D1 | P2 | Dead helpers / unused locals | SAFE_DELETE list verified 0 product calls | dead.md |
| P2-M1 | P2 | Mac/Designer parity gaps | Mac scorecard n/a; proxy release unwired; designer Close-ConnectLog | prior wave D + dead.md |

**Out of scope:** Windows SshX ControlMaster redesign; full log-sync rewrite beyond mkdir/retention/Needed; personal Cursor policy; inventing historical 3× from missing Jul22/23 day files.

## File map

| File | Responsibility in this plan |
|------|------------------------------|
| `scripts/client/windows/connect.ps1` | Skip/background mount check; MountOk truth; EditorOpened; auth wait; SESSION_OPEN args; version |
| `scripts/client/git-mode.ps1` | Optional skip-healthy-check flag; seed mount hash from setup; tunnel tests if touched |
| `scripts/client/connect-ui.ps1` | Day-log mutex helper for satellites; log-sync mkdir/find; drain Needed; SCORECARD EditorOpened |
| `scripts/client/editor-launch.ps1` | Launch trust / poll honesty; remove Quiet dead path if Task 9 |
| `scripts/client/connect-diagnostic.ps1` | Light diag must not hardcode MountOk; LaunchHistory wire |
| `scripts/client/mac/connect.sh` + `git-mode.sh` + `connect-ui.sh` | Parity Tasks only |
| `scripts/client/users/designer/*` | Close-ConnectLog / sync parity only |
| `scripts/client/tests/test-*.ps1` | RED→GREEN for each P0 |
| `docs/client-connect.md` | Mount BG semantics + log sync truth |
| `publish/*` / version txt | Version bump on ship |

## Trade-offs

1. **Skip sync mount check when BG `up`**
   - **A (chosen):** Skip `Test-ProjectMountHealthy` on the path that kicks BG `up`; log `MOUNT_CHECK_SKIPPED reason=bg_up`. Still run check for `skipRemount` / GIT_MODE=off healthy reuse.
   - **B:** Keep check, only shorten timeout to 3s.
   - **Why A:** Agents do not need SSHFS; check is leftover tax after BG. Risk: Cursor tree empty until BG finishes — already true today; surface `MOUNT_BG_*` instead.
2. **MountOk semantics**
   - **A (chosen):** `started_in_background` → `MountOk=$false` until `MOUNT_BG_OK` observed (or live re-probe before SCORECARD/SESSION_OPEN). UI StepOk still shows “started in background”.
   - **B:** Keep MountOk=true but add `MountPending=true` field.
   - **Why A:** Fewer lying fields; existing `MountOk` consumers get truth.
3. **Trust path after launch**
   - **A (chosen):** Keep skip re-probe on `didLaunch+launchOk`, but set `$script:EditorOpened=$true` and require Launch-RemoteEditor returned true with on-folder poll evidence already inside launch.
   - **B:** Always re-probe (can double-launch).
   - **Why A:** Fixes false-closed SCORECARD without reintroducing double-launch.

## Wave-ready execution notes

| Hotspot | Serialize Tasks |
|---------|-----------------|
| `connect.ps1` | 1, 2, 3, 5, 6 (one Writer at a time) |
| `connect-ui.ps1` | 4, 7 (serialize) |
| `git-mode.ps1` | 1, 3 (serialize with connect.ps1 if both touch call sites) |
| Tests | Usually parallel with product Task after RED written in same Task |

Default wave size: 3–5 Workers. Prefer RED tests in parallel (disjoint test files), then one GREEN worker per hotspot file.

---

### Task 1: Skip sync mount check when backgrounding `up`

**Files:**
- Modify: `scripts/client/git-mode.ps1` (`Invoke-RecoverIfNeeded`, `Test-ProjectMountHealthy` callers)
- Modify: `scripts/client/windows/connect.ps1` (~2039–2165)
- Test: `scripts/client/tests/test-mount-check-skipped-on-bg-up.ps1` (create)
- Harden: `scripts/client/tests/test-mount-backgrounded-live.ps1` (must assert check skip or count)

**Interfaces:**
- Consumes: `Start-MountProjectBackground`, `Invoke-RecoverIfNeeded`
- Produces: `Invoke-RecoverIfNeeded -SkipHealthyCheck` (or connect path that does not call recover check before BG); log `MOUNT_CHECK_SKIPPED reason=bg_up`

- [ ] **Step 1: Write the failing test**

```powershell
# test-mount-check-skipped-on-bg-up.ps1
# Assert product source: the branch that calls Start-MountProjectBackground does NOT call
# Test-ProjectMountHealthy / "claude-mount check" on the same synchronous path after kick
# (or explicitly logs MOUNT_CHECK_SKIPPED). Presence-only is FAIL.
$connect = Get-Content -Raw 'scripts/client/windows/connect.ps1'
# Extract the else-branch that starts background mount (between Step "Mounting files" and StepOk started_in_background)
Assert ($connect -match 'MOUNT_CHECK_SKIPPED reason=bg_up') 'BG up path must log MOUNT_CHECK_SKIPPED'
Assert ($connect -match 'SkipHealthyCheck|skip_mount_check_bg') 'Recover/check must be skippable for BG path'
```

- [ ] **Step 2: Run test — expect FAIL** on current tree (no skip marker).

```bat
powershell -NoProfile -File scripts\client\tests\test-mount-check-skipped-on-bg-up.ps1
```

- [ ] **Step 3: Implement**

In `connect.ps1` before BG kick: do **not** call `Invoke-RecoverIfNeeded` solely to decide BG vs skip when GIT_MODE≠off healthy. Preferred shape:

```powershell
# When cold mount needed:
Write-ConnectLog 'MOUNT_CHECK_SKIPPED reason=bg_up' 'DEBUG'
[void](Start-MountProjectBackground ...)
$mountResult = [pscustomobject]@{ Ok = $false; Out = 'started_in_background'; Skipped = $true; Pending = $true }
```

Keep `Invoke-RecoverIfNeeded` / healthy check **only** for the `skipRemount` / already-mounted branch (`GIT_MODE=off` + prior recover ok).

Optional: add `[switch]$SkipHealthyCheck` to `Invoke-RecoverIfNeeded` for callers that still need recover-without-check — only if recover-one is still required without check; otherwise leave recover for O/R paths.

- [ ] **Step 4: Run test — expect PASS**; also run `test-mount-failfast.ps1` + `test-mount-backgrounded-live.ps1`.

- [ ] **Step 5: Commit** (only if user authorized)

```text
perf(connect): skip sync mount check when backgrounding SSHFS up
```

---

### Task 2: Drop exposed auth stamp WaitForExit(5000) when local_ttl already current

**Files:**
- Modify: `scripts/client/windows/connect.ps1` (~2107–2240)
- Test: `scripts/client/tests/test-auth-stamp-prefetch-no-block.ps1` (create)

**Interfaces:**
- Consumes: `Test-CursorAuthStampCurrent`, `BgAuthStampProc`
- Produces: no WaitForExit when local stamp already current; log `AUTH_STAMP_WAIT_SKIPPED reason=local_ttl`

- [ ] **Step 1: Failing test** — assert source contains `AUTH_STAMP_WAIT_SKIPPED` and that WaitForExit(5000) is gated.

```powershell
$c = Get-Content -Raw 'scripts/client/windows/connect.ps1'
Assert ($c -match 'AUTH_STAMP_WAIT_SKIPPED') 'must skip stamp wait when already current'
Assert ($c -match 'WaitForExit\(5000\)') 'prefetch wait still exists for cold path'
# Ensure WaitForExit is inside a condition, not unconditional before Syncing Cursor auth
Assert ($c -match '(?s)AUTH_STAMP_WAIT_SKIPPED.*?WaitForExit\(5000\)|WaitForExit\(5000\).*?else') 'WaitForExit must be conditional'
```

- [ ] **Step 2: Run — FAIL** if wait is unconditional.

- [ ] **Step 3: Implement**

```powershell
$stampAlreadyCurrent = $false
try { $stampAlreadyCurrent = [bool](Test-CursorAuthStampCurrent ...) } catch { }
if ($BgAuthStampProc -and -not $BgAuthStampProc.HasExited) {
    if ($stampAlreadyCurrent) {
        Write-ConnectLog 'AUTH_STAMP_WAIT_SKIPPED reason=local_ttl' 'DEBUG'
    } else {
        $null = $BgAuthStampProc.WaitForExit(5000)
    }
}
```

- [ ] **Step 4: PASS** + smoke `test-connect-pipeline.ps1` auth-related asserts.

- [ ] **Step 5: Commit** (if authorized): `perf(connect): do not block 5s on auth stamp when local_ttl current`

---

### Task 3: Seed `ClaudeMountSyncVerifiedHash` from Server setup MOUNT_HASH

**Files:**
- Modify: `scripts/client/windows/connect.ps1` (`Initialize-ServerSession` ~761)
- Modify: `scripts/client/git-mode.ps1` (`Prepare-ServerSessionParallel` ~2299)
- Test: `scripts/client/tests/test-mount-hash-seed-from-setup.ps1` (create)

**Interfaces:**
- Consumes: batched setup output `MOUNT_HASH=…`
- Produces: `$script:ClaudeMountSyncVerifiedHash` set in setup; Prepare skips sha256 SshX when equal

- [ ] **Step 1: Failing test** — setup assigns verified hash; Prepare skips when set.

```powershell
$c = Get-Content -Raw 'scripts/client/windows/connect.ps1'
$g = Get-Content -Raw 'scripts/client/git-mode.ps1'
Assert ($c -match 'ClaudeMountSyncVerifiedHash\s*=') 'setup must seed ClaudeMountSyncVerifiedHash'
Assert ($g -match 'ClaudeMountSyncVerifiedHash') 'Prepare must honor seeded hash'
```

- [ ] **Step 2: FAIL** if seed missing.

- [ ] **Step 3: Implement** — parse `MOUNT_HASH=` from setup batch; assign `$script:ClaudeMountSyncVerifiedHash`. In Prepare, if hash matches remote/local intent, skip `sha256sum` SshX (existing skip branch if any — extend it).

- [ ] **Step 4: PASS** + `test-connect-pipeline.ps1` setup invariants.

- [ ] **Step 5: Commit** (if authorized): `perf(connect): reuse Server setup mount hash in Prepare`

---

### Task 4: Mount BG day-log via mutex (restore MOUNT_BG_BEGIN/OK/FAIL)

**Files:**
- Modify: `scripts/client/connect-ui.ps1` (export a satellite-safe writer OR document mutex name + seek pattern)
- Modify: `scripts/client/windows/connect.ps1` (`Start-MountProjectBackground` runner ~1048–1071)
- Test: `scripts/client/tests/test-mount-bg-daylog-mutex-contention-live.ps1` (create)

**Interfaces:**
- Consumes: `Get-ConnectLogWriteMutex` / `Write-ConnectLogSynced` pattern
- Produces: BG child lines in same day log; parent still holds FileStream

- [ ] **Step 1: Failing live test**

```powershell
# Open day log with FileStream Append + FileShare.ReadWrite (parent simulation).
# Spawn child that uses NEW Write-MountBgLog implementation.
# Assert child line appears within 2s (not swallowed by catch {}).
```

Concrete test outline:

```powershell
$day = Join-Path $TestDrive ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
$fs = [IO.FileStream]::new($day, 'Append', 'Write', 'ReadWrite')
# dot-source fixed writer helper; write MOUNT_BG_BEGIN
# Assert (Get-Content $day) -match 'MOUNT_BG_BEGIN'
$fs.Dispose()
```

- [ ] **Step 2: FAIL** on current `AppendAllText` + empty catch under parent lock.

- [ ] **Step 3: Implement** — child must:

```powershell
function Write-MountBgLog([string]$Msg, [string]$Level = 'INFO') {
    $day = Join-Path $LogDir ('connect-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = "[$ts] [$Level] [$SessionId] $Msg"
    $mutex = $null
    try {
        $mutex = [System.Threading.Mutex]::new($false, ("Global\ClaudeConnectLogWrite-{0}" -f ([IO.Path]::GetFileName($day))))
        $null = $mutex.WaitOne(5000)
        $fs = [IO.FileStream]::new($day, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
        try {
            $fs.Seek(0, 'End') | Out-Null
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes($line + "`r`n")
            $fs.Write($bytes, 0, $bytes.Length)
        } finally { $fs.Dispose() }
    } catch {
        # last resort: sidecar next to day log so silence never happens
        try { Add-Content -LiteralPath ($day + '.mount-bg') -Value $line } catch { }
    } finally {
        if ($mutex) { try { $mutex.ReleaseMutex() } catch { }; $mutex.Dispose() }
    }
}
```

Reuse exact mutex name algorithm from `Get-ConnectLogWriteMutex` in `connect-ui.ps1` (do not invent a second naming scheme — extract shared helper if needed).

- [ ] **Step 4: PASS** live contention test; manually confirm next connect produces `MOUNT_BG_BEGIN`/`OK|FAIL`.

- [ ] **Step 5: Commit** (if authorized): `fix(connect): mount BG day-log writes via shared mutex`

---

### Task 5: Honest MountOk + `$script:EditorOpened` + SESSION_OPEN / SCORECARD

**Files:**
- Modify: `scripts/client/windows/connect.ps1` (~2161–2520)
- Modify: `scripts/client/connect-ui.ps1` (`Write-ConnectScorecard` ~1482)
- Modify: `scripts/client/connect-diagnostic.ps1` if MountOk hardcoded
- Test: `scripts/client/tests/test-editor-opened-script-scope.ps1` (create)
- Harden: `scripts/client/tests/test-connect-scorecard.ps1`

**Interfaces:**
- Consumes: `$editorOpened`, `$mountResult.Pending`, live `Test-ProjectMountHealthy` optional at SCORECARD
- Produces: `$script:EditorOpened` assigned; SESSION_OPEN `-MountOk $mountOk`; SCORECARD uses script scope

- [ ] **Step 1: Failing tests**

```powershell
# test-editor-opened-script-scope.ps1
$c = Get-Content -Raw 'scripts/client/windows/connect.ps1'
Assert ($c -match '\$script:EditorOpened\s*=\s*\$true') 'must assign script:EditorOpened on open'
Assert ($c -match 'Write-SessionDiagnosticReport[\s\S]*?-MountOk \$mountOk') 'SESSION_OPEN must pass live mountOk'
Assert ($c -notmatch "Write-SessionDiagnosticReport[\s\S]*?-MountOk \$true") 'must not hardcode MountOk true'
```

- [ ] **Step 2: FAIL** on hardcoded `-MountOk $true` / missing `$script:EditorOpened =`.

- [ ] **Step 3: Implement**

```powershell
# after BG kick (Task 1 already sets Ok=false Pending=true):
$mountOk = [bool]$mountResult.Ok

# when onFolderNow:
$editorOpened = $true
$script:EditorOpened = $true
# when closed:
$editorOpened = $false
$script:EditorOpened = $false

$null = Write-SessionDiagnosticReport -Phase 'SESSION_OPEN' -MountOk $mountOk -MountOut $mountOut ...
Complete-PostTunnelRecovery -MountOk $mountOk ...
```

SCORECARD: prefer `$script:EditorOpened`; keep Scope-1 fallback only as secondary.

- [ ] **Step 4: PASS** scorecard + editor-opened tests.

- [ ] **Step 5: Commit** (if authorized): `fix(connect): honest MountOk and script EditorOpened for SCORECARD`

---

### Task 6: Opening Cursor stability — sticky seen-open + trust path contracts

**Files:**
- Modify: `scripts/client/windows/connect.ps1` (fail branch ~2473–2490; trust ~2457)
- Modify: `scripts/client/editor-launch.ps1` only if poll budget must change (prefer connect.ps1 first)
- Test: `scripts/client/tests/test-launch-trust-path-no-double-relaunch.ps1` (create)
- Test: `scripts/client/tests/test-opening-fail-clears-editor-seen.ps1` (create)

**Interfaces:**
- Consumes: `didLaunch`, `launchOk`, `onFolderNow`, `$script:EditorSeenOpen`
- Produces: Opening STEP fail clears sticky open unless window still proven open; trust path only when launchOk already observed on-folder inside Launch-RemoteEditor

- [ ] **Step 1: Failing tests** — assert fail path logs `EDITOR_SEEN_CLEAR reason=opening_step_fail` when STEP fails; trust path still has `SESSION: trusting launch result`.

- [ ] **Step 2: FAIL** if sticky open survives STEP fail with window closed.

- [ ] **Step 3: Implement** — on Opening Cursor StepFail / launch not ok:

```powershell
if (-not $launchOk) {
    if (-not $windowOpenInit) {
        $script:EditorSeenOpen = $false
        $script:EditorOpened = $false
        Write-ConnectLog 'EDITOR_SEEN_CLEAR reason=opening_step_fail' 'INFO'
    }
}
```

Do **not** remove trust-path skip-reprobe (that caused double launch). Cap warm LAUNCH_POLL only if live evidence shows >12s waits on success path (Jul 25 success poll med 250ms — do not shorten blindly).

- [ ] **Step 4: PASS** both new tests + `test-editor-launch-strategies.ps1`.

- [ ] **Step 5: Commit** (if authorized): `fix(connect): clear sticky editor-open on Opening Cursor fail`

---

### Task 7: Log sync — split find retention; preserve Needed on Force fail

**Files:**
- Modify: `scripts/client/connect-ui.ps1` (`Sync-ConnectLogToServer` mkdir ~650; `Complete-ConnectLogAsyncDrain` ~913)
- Test: `scripts/client/tests/test-log-sync-mkdir-no-find-on-fast-path.ps1` (create)
- Harden: existing log-sync contract tests (must assert behavior, not only presence)

**Interfaces:**
- Consumes: `$script:LogSyncFastMkdirMs`, Force flag
- Produces: fast mkdir **without** `find -mtime +1`; retention on Force or timer; Needed restored if Force sync fails

- [ ] **Step 1: Failing test**

```powershell
$ui = Get-Content -Raw 'scripts/client/connect-ui.ps1'
# Fast mkdir command must not embed find -mtime +1
Assert ($ui -match 'LogSyncFastMkdir') 
# After extracting the non-Force $mk assignment, assert it does NOT contain find -mtime
$m = [regex]::Match($ui, '\$mk\s*=\s*''([^'']+)''')
Assert ($m.Success) 'mk assignment found'
Assert ($m.Groups[1].Value -notmatch 'find .*mtime') 'fast mkdir must not run find retention'
# Drain must not clear Needed before successful Force sync
Assert ($ui -match '(?s)Complete-ConnectLogAsyncDrain.*?ConnectLogSyncNeeded\s*=\s*\$true') 'Needed restored on Force fail'
```

- [ ] **Step 2: FAIL** on today's packed find + clear-Needed-before-Force.

- [ ] **Step 3: Implement**

```powershell
$mk = 'mkdir -p "$HOME/.claude/logs" && chmod 700 "$HOME/.claude" "$HOME/.claude/logs" 2>/dev/null; true'
# Retention only on -Force or dedicated path:
$retain = 'find "$HOME/.claude/logs" -type f -mtime +1 -delete 2>/dev/null; true'
```

```powershell
function Complete-ConnectLogAsyncDrain {
    param([switch]$Force)
    # ... stop timer ...
    $hadNeeded = [bool]$script:ConnectLogSyncNeeded
    if (($script:ConnectLogSyncNeeded -or $script:ConnectLogWarnPendingUntil) -and ...) {
        try { Sync-ConnectLogToServer | Out-Null } catch { }
    }
    if ($Force -and ...) {
        try {
            Sync-ConnectLogToServer -Force | Out-Null
            if (-not $script:LastConnectLogSyncOk -and $hadNeeded) {
                $script:ConnectLogSyncNeeded = $true
                return
            }
        } catch {
            if ($hadNeeded) { $script:ConnectLogSyncNeeded = $true }
            return
        }
    }
    $script:ConnectLogSyncNeeded = $false
    $script:ConnectLogWarnPendingUntil = $null
}
```

- [ ] **Step 4: PASS** new + hardened sync tests.

- [ ] **Step 5: Commit** (if authorized): `fix(connect): log-sync fast mkdir without find; preserve Needed on Force fail`

---

### Task 8: Harden false-green tests (mount-bg, scorecard, SESSION_FILTER, tunnel debounce)

**Files:**
- Modify: `scripts/client/tests/test-mount-backgrounded-live.ps1`
- Modify: `scripts/client/tests/test-connect-scorecard.ps1`
- Modify: `scripts/client/tests/test-connect-diagnostic.ps1` (SESSION_FILTER)
- Create: `scripts/client/tests/test-tunnel-sync-down-debounce-returns-true.ps1`
- Modify: `scripts/client/tests/run-all.ps1` (register new tests)

**Interfaces:**
- Consumes: behaviors from Tasks 1–7
- Produces: tests that fail if contracts regress to presence-only lies

- [ ] **Step 1: Rewrite asserts** so each test requires:
  - mount-bg: day log contains `MOUNT_BG_BEGIN` under parent FileStream contention OR sidecar fallback exists
  - scorecard: with `$script:EditorOpened=$true` fixture → line has `editor=open`
  - SESSION_FILTER: tip uses a filter that actually matches bracketed sid (fix broken BRE if still present)
  - tunnel debounce: when tunnel down and miss&lt;3, function returns `$true` **and** logs `tunnel_down_debounce` (document intentional soft-health); add separate test if product should return `$false` earlier — **do not change product in this Task unless Task 6/stability requires it**

- [ ] **Step 2: Run suite subset — expect FAIL** until Tasks 4–5 landed; if Task 8 runs after 4–5, expect PASS.

- [ ] **Step 3: Fix only test harness bugs** in this Task (not product) unless a one-line tip string fix is in `connect-ui.ps1` SESSION_FILTER — that tip fix is allowed here:

```powershell
# Example tip (literal): grep by [sessionid] brackets — avoid broken char-class BRE
Write-ConnectLog "SESSION_FILTER grep=[$($script:ConnectSessionId)] tip=Select-String -Pattern '\\[$($script:ConnectSessionId)\\]'"
```

- [ ] **Step 4: PASS** subset; register in `run-all.ps1`.

- [ ] **Step 5: Commit** (if authorized): `test(connect): harden false-green mount/scorecard/filter contracts`

---

### Task 9: SAFE_DELETE verified dead helpers

**Files:**
- Modify: `scripts/client/windows/connect.ps1` — delete `Escape-BashSingleQuoted`, `Get-ActiveMountId`
- Modify: `scripts/client/editor-launch.ps1` — delete `Start-EditorProcessQuiet`, `Stop-CursorServerProfileTreeIfNeeded`
- Modify: `scripts/client/connect-ui.ps1` — delete `Write-ConnectPhaseLog`, `Write-ConnectTimedLog`, `Invoke-ConnectPerfBlock`
- Modify: `scripts/client/git-mode.ps1` — delete `Unmount-OtherProjects`, `Test-TunnelPortOccupiedByPeer`
- Modify: `scripts/client/tests/test-editor-launch.ps1` — expect Direct not Quiet
- Create: `scripts/client/tests/test-dead-safe-delete-connect.ps1`

**KEEP_BUT_WIRE deferred to Task 5/10:** `Write-ConnectUserFacingError`, `$projSafe`, `LaunchHistory`, Mac `release_cursor_proxy_owner`.

- [ ] **Step 1: RED** `test-dead-safe-delete-connect.ps1` + fix Quiet asserts in `test-editor-launch.ps1`.

- [ ] **Step 2: FAIL** until deletes land / Quiet asserts updated.

- [ ] **Step 3: Delete defs only after grep shows 0 product calls** (re-verify in Worker).

- [ ] **Step 4: PASS** dead-delete + editor-launch tests.

- [ ] **Step 5: Commit** (if authorized): `chore(connect): remove verified unused helpers`

---

### Task 10: Mac / Designer parity (proxy release, Close-ConnectLog, scorecard fields)

**Files:**
- Modify: `scripts/client/git-mode.sh` (`clear_session_mount` → `release_cursor_proxy_owner`)
- Modify: `scripts/client/mac/connect.sh` / `connect-ui.sh` as needed for MountOk / scorecard
- Modify: `scripts/client/users/designer/connect.ps1` — `Close-ConnectLog` on exit
- Test: `scripts/client/tests/test-mac-proxy-release-on-clear.ps1`

- [ ] **Step 1: RED** mac proxy release test + designer close-log presence test.

- [ ] **Step 2: FAIL**.

- [ ] **Step 3: Wire** `release_cursor_proxy_owner` into `clear_session_mount`; designer `finally { Close-ConnectLog }`; Mac scorecard: stop hardcoding `n/a` where Win has real fields **only if** values exist (do not invent).

- [ ] **Step 4: PASS**.

- [ ] **Step 5: Commit** (if authorized): `fix(connect): Mac proxy release + designer Close-ConnectLog parity`

---

### Task 11: Docs + version bump + acceptance measure

**Files:**
- Modify: `docs/client-connect.md` (Mount BG, MountOk pending, log sync mkdir, SCORECARD fields)
- Modify: version strings (`connect.ps1`, `mac/connect.sh`, `connect-version.txt` ×2, bat guard if present)
- Modify: `CLAUDE.md` only if invariant table still says always-elevate / old version

**Acceptance (run on Smart laptop after Tasks 1–8):**

```powershell
# Fresh connect → pick project → expect:
# 1) No SSH_BEGIN claude-mount check between project pick and Opening Cursor (BG path)
# 2) MOUNT_BG_BEGIN then MOUNT_BG_OK|FAIL in same day log
# 3) SCORECARD editor= matches visible Cursor
# 4) SESSION_OPEN MountOk false while pending; true after BG OK or skipRemount
# 5) LOG_SYNC_OK appears at least once per session end (or Needed remains true with retry — not silent clear)
# 6) Opening Cursor fail rate measured on new day log (report; target < Jul25 68%)
```

- [ ] **Step 1: Update docs** with measured before/after table template.

- [ ] **Step 2: Bump version** to next `20260725.NN` (or date of ship).

- [ ] **Step 3: Run** `scripts\client\tests\run-all.bat` (or focused subset if full suite too long) — record PASS count.

- [ ] **Step 4: Manual connect** acceptance checklist above — paste SCORECARD + MOUNT_BG lines into wrap-up.

- [ ] **Step 5: Commit** (if authorized): `docs(connect): speed/stability/logging acceptance + version bump`

---

## Spec coverage checklist (self-review)

| Requirement | Task |
|-------------|------|
| Skip sync mount check on BG path | 1 |
| Auth stamp 5s exposure | 2 |
| Prepare sha256 seed | 3 |
| Mount BG log silence | 4 |
| MountOk / EditorOpened / SCORECARD lies | 5 |
| Opening sticky / trust false-green | 6 |
| Log sync mkdir/find + Needed | 7 |
| False-green tests | 8 |
| Dead code SAFE_DELETE | 9 |
| Mac/Designer parity | 10 |
| Docs + version + measure | 11 |
| Do not claim invented 3× | Evidence section |
| Keep elevate-when-needed / preflight from 2026-07-23 | Out of scope (already done) |

## Placeholder scan

No TBD/TODO steps. Each Task has concrete asserts and code shapes. Tunnel debounce product change intentionally deferred (document-only in Task 8) unless live instability proves soft-`$true` is harmful — then add Task 8b.

---

## Execution handoff

Plan saved to `docs/superpowers/plans/2026-07-25-connect-speed-stability-logging.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per Task, review between Tasks, waves per `parallel-phased-execution`
2. **Inline Execution** — execute in this session with checkpoints

**Do not start Stage 4 until the user confirms this plan (heavy-task-plan Stage 3).**
