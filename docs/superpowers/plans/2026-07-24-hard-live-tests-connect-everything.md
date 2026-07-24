# Hard LIVE Tests for Connect Client — Everything Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add hard/functional ("LIVE") regression tests — exercising real OS primitives (real sockets, real spawned processes, real mutexes, real files/timestamps) — for the five Connect-client subsystems that currently only have static/regex source-pattern tests, so that "all tests passed" means real behavior was proven, not just that matching text exists in the source.

**Architecture:** Every new test follows the established idiom already shipped this session (`test-tunnel-job-object-live.ps1`, `test-sshx-hard-kill-live.ps1`, `test-update-check-failfast-live.ps1`, `test-exe-atomic-swap-live.ps1`, `test-logsync-fast-timeout-live.ps1`): use `Get-FunctionSource` (in `scripts/client/tests/_paths.ps1`) to brace-extract ONE real function verbatim out of the shipped production `.ps1` file, dot-source it in isolation, stub only its non-essential logging/network dependencies, and exercise it against a real OS resource this test creates itself (temp dir, ephemeral port, decoy process, real mutex). No production code changes in this plan — test-only additions.

**Tech Stack:** PowerShell 5.1, `Add-Type -Language CSharp` for compiled decoy stub `.exe`s, Win32 CIM/`Get-Process`/`TcpListener`/named `Mutex` primitives, `laptop-exec` for all remote file I/O on this project (`-p claude-code-server`).

## Global Constraints

- SSH-first / mounts: every Worker uses `laptop-exec -p claude-code-server` for read/write/run on this project; never `Read`/`Write`/`Grep`/`Glob` on `~/mounts/`; never `rg -i/-l/-n/--glob`; on any deny, run `NEXT:` immediately, do not retry.
- Never touch the real global 10-slot mutex pool (`Global\ClaudeConnect#0..#9`) beyond probing free-slot count and claiming **at most 2** for the duration of one test — never drain/exhaust it (a real Connect session, including the one driving this test run, may hold a slot).
- Never target production ports `18998`, `18999`, `19080`, `19180`, or the live SSH tunnel port (currently `20022`) in any new test — always bind ephemeral high ports (`49152-65535`) chosen at random per test run.
- Never let a boot-reap test kill the **real** production sidecar watchdog or delete its real lease file — stub `Stop-CursorProxySidecarWatchdog` so the boot-reap test only records the call; back up + restore any pre-existing real lease file (`%TEMP%\claude-connect-sidecar-watchdog.lease`) in `finally`.
- CIM process-name filters (`Name='ssh.exe'`, `Name='Cursor.exe'`) mean decoy stub `.exe`s must be **compiled with that exact output filename** (`Add-Type -OutputAssembly <dir>\ssh.exe` etc.) — never rename a real system binary.
- Every new test must clean up everything it created (processes, mutexes, temp dirs, TEMP relay scripts) in `try/finally`, even on assertion failure — no leaked ports/processes/mutexes after any single test run, pass or fail.
- Register every new test in `scripts/client/tests/run-all.ps1` next to its sibling static test.
- Test-only additions: no version bump, no `Copy-ExeAtomicSwap`/deploy changes, no edits to any production `.ps1` logic.
- Do not `git commit` unless the user explicitly asks.

## Discovery evidence (from Stage 1 parallel explore)

| Area | Key finding |
|---|---|
| Tunnel/port acquisition | `Acquire-TunnelPort` (git-mode.ps1:1477-1717), `Test-TunnelPortIsForeignPeer` (887-948), `Remove-LocalOrphanTunnel` (582-625), `Test-LocalPortFree` (1012-1024) — zero LIVE coverage today |
| Cursor-auth-sync | Lives in `scripts/client/cursor-auth-laptop.ps1` (not `windows/`); `Test-CursorAuthStampCurrent` (705-734), golden-missing-cache Set/Test/Clear (660-679) are cleanly fakeable via temp dir |
| Editor-launch | `Get-RemoteEditorProcesses`/`Test-RemoteEditorOnCorrectFolder` (editor-launch.ps1 ~993-1175) provable with a compiled decoy `Cursor.exe`; window-open/slot-gate flagged risky (interactive session / real mutex pool) |
| Sidecar proxy relay | `Test-CursorProxySidecarListening` (162-177), `Start-TcpPortRelay` (179-274), `Invoke-CursorProxySidecarBootReap` (604-630) in `cursor-proxy-sidecar.ps1`; boot-reap needs a Stop-stub + lease backup/restore |
| Multi-instance mutex | `Enter-`/`Exit-ConnectSingleInstance` (connect-ui.ps1:259-324); explicit safety flag against draining the real 10-slot pool |

---

## Task 1 (Wave 1 - 5 parallel Workers, all write-disjoint new files)

### Slice 1A: `test-local-port-free-bind-live.ps1`
**Owns:** `scripts/client/tests/test-local-port-free-bind-live.ps1`
**Function:** `Test-LocalPortFree` (git-mode.ps1:1012-1024)
**Scenario:** Pick a random ephemeral port. Assert `$true` when unbound. Bind a real `TcpListener` on it. Assert `$false`. Stop listener. Assert `$true` again.
**Admit:** runs standalone, exits 0, port unbound after.

### Slice 1B: `test-orphan-tunnel-kill-vs-sibling-live.ps1`
**Owns:** `scripts/client/tests/test-orphan-tunnel-kill-vs-sibling-live.ps1`
**Functions:** `Remove-LocalOrphanTunnel`, `Get-SiblingConnectTunnelPids`, `Get-LocalTunnelSshPids`, `Stop-TunnelProcessWithExitLog` (git-mode.ps1:582-625 region)
**Scenario:** Compile two decoy processes named exactly `ssh.exe` in two separate temp dirs; launch each with a `-R <port>:localhost:22`-style command line so `CommandLine` matches the real detection pattern - one as a true orphan, one as a sibling under a `connect.ps1`-shaped parent wrapper. Call the real `Remove-LocalOrphanTunnel`. Assert orphan killed, sibling survives.
**Risk:** only ever act on PIDs this test itself just spawned; kill both decoys in `finally` regardless of outcome.
**Admit:** orphan decoy confirmed dead, sibling decoy confirmed alive, both cleaned up.

### Slice 1C: `test-auth-stamp-current-live.ps1`
**Owns:** `scripts/client/tests/test-auth-stamp-current-live.ps1`
**Function:** `Test-CursorAuthStampCurrent` (cursor-auth-laptop.ps1:705-734)
**Scenario:** In a temp dir standing in for the profile dir, write `golden-synced-at.txt` with a fresh real mtime, assert `Current=$true, Source=local_ttl`. Force mtime past 60 minutes with stubbed `Get-CursorGoldenExportedAtStamp` returning a non-matching value, assert `Current=$false`. Same aged file, stub returns matching value, assert `Current=$true, Source=ssh`.
**Admit:** all three real-mtime branches proven, temp dir removed after.

### Slice 1D: `test-auth-golden-missing-cache-live.ps1`
**Owns:** `scripts/client/tests/test-auth-golden-missing-cache-live.ps1`
**Functions:** `Test-CursorGoldenKnownMissing` / `Set-CursorGoldenKnownMissing` / `Clear-CursorGoldenKnownMissing` (cursor-auth-laptop.ps1:660-679), stub `Get-LocalCursorGlobalStorage` to a temp dir
**Scenario:** Fresh dir - `Test-` is `$false`. `Set-` - `Test-` is `$true`. Age the cache file's real mtime past the 3-minute TTL - `Test-` is `$false` again (self-heal). `Set-` then `Clear-` - file gone, `Test-` is `$false`.
**Admit:** real file create/age/delete cycle proven, temp dir removed after.

### Slice 1E: `test-sidecar-listening-live.ps1`
**Owns:** `scripts/client/tests/test-sidecar-listening-live.ps1`
**Function:** `Test-CursorProxySidecarListening` (cursor-proxy-sidecar.ps1:162-177)
**Scenario:** Random ephemeral port unbound - `$false`. Bind real loopback `TcpListener` - `$true`. Close - `$false`.
**Admit:** proven against a real socket, port released after.

**Wave 1 gate:** all 5 files run standalone, exit 0, leave zero orphaned process/port/mutex. Coordinator appends all 5 filenames to `run-all.ps1` (single hotspot edit, not a Worker owns), then re-runs `run-all.ps1` in full.

---

## Task 2 (Wave 2 - 4 parallel Workers, all write-disjoint new files)

### Slice 2A: `test-tcp-port-relay-live.ps1`
**Owns:** `scripts/client/tests/test-tcp-port-relay-live.ps1`
**Functions:** `Test-CursorProxySidecarListening` + `Start-TcpPortRelay` (cursor-proxy-sidecar.ps1:179-274), stub job-assign/log helpers as no-ops
**Scenario:** Random ephemeral listen+backend ports. Start a tiny real backend `TcpListener` that echoes one line. Call `Start-TcpPortRelay`. Assert listen port reports listening. Open a real `TcpClient`, send a line, assert it round-trips through the relay from the backend. Kill spawned relay, dispose mutex, remove per-port TEMP `.ps1`.
**Admit:** real round-trip byte proven through the relay; everything cleaned up.

### Slice 2B: `test-sidecar-boot-reap-live.ps1`
**Owns:** `scripts/client/tests/test-sidecar-boot-reap-live.ps1`
**Function:** `Invoke-CursorProxySidecarBootReap` (cursor-proxy-sidecar.ps1:604-630) with a LOCAL stub `Stop-CursorProxySidecarWatchdog` that only records the call (never extract/run the real Stop)
**Scenario:** Back up any real lease file first. Case A: spawn a real long-lived decoy, write the lease with its real PID+timestamp, assert BootReap returns no-reap and stub not called; kill decoy. Case B: spawn+kill a decoy to get a real-but-dead PID, write the lease with that PID, assert BootReap returns reap-needed and stub called exactly once. Restore the original real lease file (or delete if none existed) in `finally`.
**Admit:** both branches proven with real PIDs, real production lease untouched/restored.

### Slice 2C: `test-remote-editor-detect-live.ps1`
**Owns:** `scripts/client/tests/test-remote-editor-detect-live.ps1`
**Functions:** `Invoke-CimEditorProcessQuery`, `Test-PathNeedleBoundaryMatch`, `Get-RemoteEditorProcesses`, `Test-RemoteEditorOnCorrectFolder` (editor-launch.ps1, ~938-1175), stub `Get-CursorRemoteProfileDir`
**Scenario:** Compile a decoy process with output filename exactly `Cursor.exe`, launch it with a command-line argument containing a realistic `vscode-remote://ssh-remote+alias/path` needle matching the real boundary-match pattern. Assert detected as on-folder (true positive). Launch a second decoy with a non-matching path (longer prefix / wrong alias), assert correctly ignored (true negative). Kill both decoys in `finally`.
**Admit:** one real true-positive and one real true-negative against actual process enumeration, both decoys killed after.

### Slice 2D: `test-connect-single-instance-live.ps1`
**Owns:** `scripts/client/tests/test-connect-single-instance-live.ps1`
**Functions:** `Enter-ConnectSingleInstance` / `Exit-ConnectSingleInstance` (connect-ui.ps1:259-324)
**Scenario (SAFE variant only):** First probe how many of the real 10 slots are currently free via non-blocking WaitOne(0) on each, immediately releasing every probed one. If fewer than 2 free, skip with a clear message and exit 0. If 2+ free: call the real `Enter-ConnectSingleInstance` twice in-process, assert two distinct slot values with no duplicate, call `Exit-ConnectSingleInstance` on one, assert a third `Enter-ConnectSingleInstance` call re-acquires. Release everything this test claimed in `finally`.
**Admit:** either an honest skip (insufficient free real slots) or a full real distinct-slot + release + re-acquire proof - never a drained pool.

**Wave 2 gate:** all 4 files run standalone and exit 0 (or documented honest skip for 2D); zero leaked processes/ports/mutexes/lease corruption. Coordinator appends all 4 filenames to `run-all.ps1`.

---

## Task 3: Full regression + wrap-up

- [ ] Run `scripts/client/tests/run-all.ps1` in full (all existing suites + 9 new LIVE tests).
- [ ] Confirm zero new regressions vs the last known-good baseline (the same pre-existing stale-fixture failures from before this plan are acceptable; nothing new).
- [ ] Confirm no test-spawned decoy process, ephemeral port, or mutex is left behind post-run.
- [ ] Report to user: what real behavior each new test proves, pass/fail table, and explicitly call out the 2D skip outcome if it occurred.
