# Fix 9 Confirmed Connect-Client Bugs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development /
> superpowers:dispatching-parallel-agents. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 8 evidence-based bugs from `cursor-agent-fix-prompt.md` (mount port fallback,
dead title-regex on-folder detection, xray-probe first-attempt stall + a worse-case retry
regression, tunnel-survives-terminal-close defeated by Job Object semantics, unsynchronized
concurrent local log writers, a proxy known-down cache that can't self-heal for 2 minutes, and a
launch-recovery guard that always collapses to dead code) — each proven with a real
failing-then-passing LIVE test — then do an explicit consolidation pass (bug 9) and delete 3 stray
debug artifacts.

**Environment note:** this session runs natively on the Windows laptop at
`D:\Smart\Claude-Code-Server` (direct filesystem + PowerShell access) — **not** on the Linux
Cursor-server side, so `laptop-exec` / SSHFS mounts are not applicable here. All workers use
`Read`/`Write`/`StrReplace`/`Shell` directly on this repo.

**Verified against current on-disk code (2026-07-24, post commit `a49f486`)** — all 8 bugs'
line numbers and mechanisms were independently re-confirmed by reading the live files, not
trusted from the prompt alone (systematic-debugging Phase 1-2). Evidence:

| Bug | File:line confirmed | Confirmed mechanism |
|---|---|---|
| 1 | `claude-mount.sh:39-41`, `git-mode.ps1:2846-2852` | `TUNNEL_PORT=$((20000 + $(id -u)))` fallback; AM_ONLY branch keeps `$CUR_PORT` (empty when no prior conf) instead of publishing `$PORT` |
| 2 | `editor-launch.ps1:1192,1263,1325,1404` | Literal `\[Claude Server\]` regex; real title is site-qualified `[Claude Server Smart]` |
| 3/4 | `git-mode.ps1:1366-1444` `Test-RemoteXraySocksOpen` | Attempt1 `WaitForExit(5000)` + full retry `WaitForExit(6000)` = **11s** worst case vs. old flat 8s; also contains leftover debug-log instrumentation (`H19`) writing to `debug-c46ba1.log` |
| 5 | `cursor-proxy-sidecar.ps1:13-123` Job Object, `git-mode.ps1:2611-2617`, `connect.ps1:2779-2837` | `CreateJobObject(IntPtr.Zero, null)` unnamed/non-inherited handle; `keepTunnelForEditor` branch skips cleanup but process exit auto-closes the job handle anyway |
| 6 | `connect-ui.ps1:326-394` `Initialize-ConnectLog`/writer | `FileStream` opened once with `FileShare.ReadWrite`, `WriteLine` calls have no mutex/lock unlike `Sync-ConnectLogToServer`'s `.sync-lock` (490-515) |
| 7 | `cursor-proxy-sidecar.ps1:406-464` | `Test-CursorProxyBackendOpen` short-circuits `$false` on `Test-CursorProxyKnownDown` for full 120s TTL, never re-probes |
| 8 | `editor-launch.ps1:1871-1889, 2054-2058, 2237-2243` | `Get-CursorLaunchWindowPlan`: `$useNewWindow` is **always true** whenever `$profileProcCount -gt 0` (via `$orphanHelpers` when `$hasProfileWindow` is false) ⇒ `$preservedOpenWindows` at 2237 always mirrors the outer `$profileProcCount -gt 0` guard at 2243 ⇒ recovery block unreachable |

**Research (mandatory, cited per-bug in the final report too):**
- Win32 Job Objects: "the job is destroyed when its last handle has been closed **and** all
  associated processes have exited... if `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` is specified,
  closing the last job object handle terminates all associated processes" (MS Learn,
  Job-Objects). `DuplicateHandle` can create a second handle to the *same* job object in another
  process — as long as any handle anywhere is open, the job is not destroyed (MS Learn
  `DuplicateHandle`). This directly enables the bug-5 fix: duplicate the job handle into the
  tunnel process itself right before `connect.ps1` exits when `keepTunnelForEditor` is true, so
  the job's handle-count does not hit zero when `connect.ps1`'s own handle auto-closes.
- Win32-OpenSSH `ConnectTimeout`: a long-known upstream behavior/bug (PowerShell/Win32-OpenSSH#1352)
  where the *non-blocking poll() path* can make the client wait the *entire* `ConnectTimeout`
  duration rather than only capping slow connections — consistent with this repo's own comment
  about MaxStartups throttling causing attempt-1 stalls under boot-time SSH bursts. Confirms
  tuning must budget for "genuinely wait the full timeout sometimes," not just "occasionally
  slow," i.e. a **single** attempt with a sane timeout beats attempt+retry stacking.
- `Get-CimInstance`/`Win32_Process` returns a point-in-time snapshot, never live-updating; VS
  Code/Cursor Remote-SSH's single-instance IPC hands a new `--folder-uri` request to the
  *existing* window's server process without spawning a new client process, so that PID's
  `CommandLine` never reflects the new folder — confirms window-title/window-count must be the
  detection signal, not `CommandLine` alone, for this class of session.
- Multi-writer log files on Windows: named `System.Threading.Mutex` or an exclusive
  (`FileShare.None`) `FileStream` around each write are the two standard safe patterns; this
  repo already uses a `FileShare.None` `.sync-lock` file for the sync path — a named Mutex is a
  closer fit for the *already-open* per-process `StreamWriter` used for local day-log writes
  (avoids reopening the file handle on every line).

## Process notes on the "6 parallel agents" requirement

The 8 bugs concentrate into only **4 write-disjoint production-file groups** (writes must not
overlap a single file between concurrently-running workers):
`{git-mode.ps1 + claude-mount.sh}` (1,3,4), `{editor-launch.ps1}` (2,8), `{connect-ui.ps1}` (6),
`{cursor-proxy-sidecar.ps1 + connect.ps1}` (5,7). A fix-phase with more than 4 parallel workers
would require multiple agents writing the same file concurrently, which risks clobbering each
other's edits — so the **fix phase explicitly runs 4 parallel workers**, not 6, and this is
flagged here per the process rule rather than silently collapsed.

To still get genuine ≥6-way parallelism where the codebase actually supports it (write-disjoint),
**Wave 1 (test-first) runs 8 parallel workers** — one per bug, each creating exactly one new,
never-shared test file (zero write overlap even though several dot-source the same production
files for reading). Each Wave-1 worker proves the bug's current buggy behavior with a real
failing LIVE test before any fix lands (test-driven-development: red first).

## Wave 1 — 8 parallel workers, write-disjoint new test files (RED)

Each worker: (a) re-verify the bug against current code, (b) do the specific research listed
above/expand it, (c) write ONE new LIVE test file per the established idiom
(`Get-FunctionSource` brace-extraction from `_paths.ps1`, real sockets/processes/mutexes/files,
no source-text-only pattern matching), (d) run it standalone and confirm/report it currently
demonstrates the bug (fails an assertion, or for latency bugs, prints the actual measured
elapsed time proving the regression), (e) do NOT modify any production `.ps1`/`.sh` file.

| Slice | Bug | New file (owns) | Function(s) under test |
|---|---|---|---|
| 1A | 1 | `test-mount-port-fallback-live.ps1` | `claude-mount.sh` port fallback (via a real bash-less string-formula check is not possible on Windows without WSL — test drives the **AM_ONLY publish** half in `Push-ServerConnectConf`, git-mode.ps1) — if no bash available, test must clearly state it validates the PowerShell-side half only and why |
| 1B | 1 | (same, or split) covered above | `Push-ServerConnectConf` AM_ONLY branch |
| 2 | 2 | `test-window-title-site-tag-live.ps1` | `Test-CursorWindowTitleIsAgentHome`, `Test-RemoteEditorOnCorrectFolder` title-match arm, against a real decoy process with title `[Claude Server Smart] repo` |
| 3/4 | 3,4 | `test-xray-probe-worst-case-live.ps1` | `Test-RemoteXraySocksOpen` against a black-holed IP, measuring real wall-clock for the retry-stacking regression |
| 5 | 5 | `test-job-detach-survives-close-live.ps1` | new detach primitive (to be added) + `Stop-CursorProxySidecarJob`, proving a detached member process survives job-handle close while a non-detached one still dies |
| 6 | 6 | `test-concurrent-log-writers-live.ps1` | `Initialize-ConnectLog`/local write path, 2+ real concurrent processes appending, byte-level interleave check |
| 7 | 7 | `test-known-down-selfheal-live.ps1` | `Test-CursorProxyBackendOpen` + `Test-CursorProxyKnownDown`, real listener recovers mid-TTL |
| 8 | 8 | `test-launch-recovery-reachable-live.ps1` | `Get-CursorLaunchWindowPlan` + the `$preservedOpenWindows` guard reproduced from source, across the 4 `(agentHome,hasProfileWindow,profileProcCount)` combinations |

**Wave 1 gate:** all 8 files run standalone; each either shows a genuine RED (bug reproduced) or
documents precisely why the bug cannot be reproduced without production-code access (e.g. bug 1's
bash half) — no test is silently skipped without an explicit printed reason.

## Wave 2 — 4 parallel workers, write-disjoint production files (GREEN + consolidate)

Each worker applies the verified fix(es) below to their owned file(s), re-runs the Wave-1 test(s)
for their bug(s) to confirm RED→GREEN, and where listed, also does the bug-9 consolidation pass
for that file.

### Worker G — `scripts/server/claude-mount.sh` + `scripts/client/git-mode.ps1` (bugs 1, 3, 4 + consolidation)
- Bug 1a: replace the deprecated `20000 + UID` fallback in `claude-mount.sh` with either the
  correct `20000 + (UID-1000)*10 + slot` formula or a loud failure (no silent wrong-port guess).
- Bug 1b: in `Push-ServerConnectConf`'s AM_ONLY remote body, only preserve `$CUR_PORT` when it is
  actually non-empty; otherwise publish the session's own `$PORT`.
- Bug 3/4 + consolidation: re-derive `Test-RemoteXraySocksOpen` as ONE attempt with a single
  clear timeout budget (no attempt+retry stacking), capped at/under the original ~8s worst case;
  remove the `H19`/`H10_proxy_health_timeout` debug-log instrumentation writing to
  `debug-c46ba1.log` (dead artifact, being deleted in this same pass).
- Admit: Wave-1 slice 1B and 3/4 tests pass; `debug-c46ba1.log` no longer written by this file.

### Worker E — `scripts/client/editor-launch.ps1` (bugs 2, 8 + consolidation)
- Bug 2: fix the 4 literal `\[Claude Server\]` regexes to match the site-qualified title
  (`\[Claude Server(?: Smart| Sepidz)?\]` or dynamically built from the actual site tag); add a
  window-count-based secondary signal per the bug's suggestion.
- Bug 8 + consolidation: re-derive `Get-CursorLaunchWindowPlan`'s `$useNewWindow`/`$orphanHelpers`
  and the `$preservedOpenWindows` guard at line ~2237 so the recovery-skip and the cold-launch
  recovery path are both reachable under the conditions each was designed for (recovery-skip
  should gate on an actual visible open window — `$hasProfileWindow`/`$agentHome` — not on
  `$useNewWindow`, which is unconditionally true whenever `$profileProcCount -gt 0`).
- Also remove the `H3_recovery_kill_context` debug-log instrumentation block.
- Admit: Wave-1 slice 2 and 8 tests pass.

### Worker U — `scripts/client/connect-ui.ps1` (bug 6)
- Wrap local day-log `WriteLine` calls in a named Mutex (or per-write `FileShare.None` open),
  matching the `.sync-lock` idiom already used for the sync path.
- Remove the `H9_init_log_breakdown` debug-log instrumentation block.
- Admit: Wave-1 slice 6 test passes (no interleaved/corrupted lines under real concurrent
  writers).

### Worker C — `scripts/client/windows/cursor-proxy-sidecar.ps1` + `scripts/client/windows/connect.ps1` (bugs 5, 7 + consolidation)
- Bug 5: add a `Detach-CursorProxySidecarJobProcess` (or similar) helper using `DuplicateHandle`
  to plant a second handle to the same job object inside a target process, so the job survives
  `connect.ps1`'s own handle auto-closing on normal exit. Call it from `connect.ps1`'s
  `keepTunnelForEditor` branch (~line 2822) for the tunnel process before the script exits.
- Bug 7 + consolidation: re-derive `Test-CursorProxyKnownDown`/`Test-CursorProxyBackendOpen` so a
  cache hit still performs a cheap real check (or the TTL/early-exit re-probe design the bug
  suggests) instead of trusting the cache unconditionally for the full 120s.
- Remove the `H10_proxy_health_timeout` debug-log instrumentation blocks in this file.
- Admit: Wave-1 slice 5 and 7 tests pass.

**Wave 2 gate:** all 4 workers report RED→GREEN for their tests with actual captured output; no
new lint/parse errors (`powershell -NoProfile -Command "$null = Get-Content <file> | Out-String |
[ScriptBlock]::Create"`-style parse check per touched file).

## Wave 3 — Cleanup + full regression (coordinator, not parallel)
- [ ] Delete stray repo-root artifacts: `--help`, `_diff2.txt`, `debug-c46ba1.log`.
- [ ] Register all new Wave-1 test files in `scripts/client/tests/run-all.ps1`.
- [ ] Run `scripts/client/tests/run-all.ps1` in full; capture real output.
- [ ] Confirm zero new regressions vs. pre-existing baseline; note (don't silently fix) any
      already-failing unrelated test.
- [ ] Check CLAUDE.md's "Sync Rule for Server Scripts" table for `claude-mount.sh` (pushed on
      connect per that table, not deployed via `install.sh` — confirm no `install.sh` change
      needed) and for any other touched server file.
- [ ] Compose final report per the 9-item format requested (test proof, file:line, pass/fail with
      captured output, research cited, any pre-existing unrelated failures flagged).
- [ ] Do not `git commit`/`git push` — stage only if asked; report what would be committed.
