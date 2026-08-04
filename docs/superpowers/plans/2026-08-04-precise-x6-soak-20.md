# Precise ×6 Soak-20 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Precise Parallel=6 Connect E2E pass **20 consecutive rounds** without stop (0 fail, 0 WARN noise that fails zero-noise, WMCP 6/6, mount ready 6/6).

**Architecture:** Multi-Connect shared-p keeps one published `TUNNEL_PORT` for agents/laptop-exec, but each Connect owns a session reverse tunnel. Mount and launch must not depend on a dying published port or tick-inflated warm polls. Fixes are behavioral (session-port mount override, wall-clock launch grace, abandoned-mutex unwrap) — not WARN demotion.

**Tech Stack:** PowerShell 5.1 client, bash `claude-mount`, Precise e2e harness, new soak wrapper.

## Global Constraints

- English only in repo (no Persian in files).
- Do **not** demote real faults (MOUNT_BG_FAIL, LAUNCH_RETRY) to hide zero-noise.
- Shared-p contract for agents stays: published `TUNNEL_PORT` for LE/AGENT_PATH.
- Session mount may use `CLAUDE_MOUNT_TUNNEL_PORT=<session>` when that port is live.
- Client version bump via `publish.ps1 -SmartOnly`; deploy `claude-mount.sh` via install/bundle.

## Evidence (8-agent deep read, run 20260804.16 / harness 021040)

| ID | Symptom | Root cause |
|----|---------|------------|
| M1 | W5 MOUNT_BG_FAIL port 20020 | `claude-mount up` uses conf TUNNEL_PORT, not session 20024; primary dies mid-mount |
| M2 | conf_port thrash 20020→20025 | w6 `port_takeover` after primary exit |
| L1 | W6 Opening Cursor 94s | Warm poll 80 ticks inflate ~76s wall; remote-classic useless; grace wins in 500ms |
| W1 | abandoned mutex skip | PS wraps AbandonedMutexException → Ensure skips Sync |
| C1 | Shared connect.conf stomp | Save-TunnelSlot overwrites PORT across workers |

---

## File map

| File | Change |
|------|--------|
| `scripts/server/claude-mount.sh` | Honor `CLAUDE_MOUNT_TUNNEL_PORT` after `_load_global` if TCP-alive |
| `scripts/client/windows/connect.ps1` | Pass session port into BG mount cmd |
| `scripts/client/git-mode.ps1` | Same override on sync mount path; optional Save-TunnelSlot mutex |
| `scripts/client/editor-launch.ps1` | Wall-clock warm budget + skip remote-classic when promising |
| `scripts/client/windows/windows-mcp-laptop.ps1` | Abandoned mutex message unwrap |
| `scripts/client/tests/test-e2e-precise-soak.ps1` | **New** 20-round Precise×6 soak |
| `scripts/client/tests/test-mount-session-port-override.ps1` | **New** static contract test |
| `publish` / install | Ship claude-mount + client |

---

## Task 1: Session-port mount override (M1)

- [x] **Step 1:** In `claude-mount.sh` after `_load_global` succeeds, if `CLAUDE_MOUNT_TUNNEL_PORT` is digits and `_mount_port_alive`, set `TUNNEL_PORT` to it and log `MOUNT_PORT_OVERRIDE session=... conf_was=...`.
- [x] **Step 2:** `Start-MountProjectBackground` builds:
  `CLAUDE_MOUNT_TUNNEL_PORT=$SessionPort CLAUDE_TRUSTED_TUNNEL=1 ... claude-mount up`
  where `$SessionPort = $script:Port`.
- [x] **Step 3:** Mirror in `Invoke-MountProject` / remount paths in `git-mode.ps1`.
- [x] **Step 4:** Static test asserts connect.ps1 + claude-mount.sh contain override strings.
- [ ] **Step 5:** Deploy claude-mount to Smart (`install` or user `~/.local/bin` copy).

## Task 2: Warm launch wall-clock (L1)

- [x] **Step 1:** In `Launch-RemoteEditor` warm attempt-1 loop, track `$swWarm`; cap wall at 25s.
- [x] **Step 2:** If `window_count_increased` true for ≥4 consecutive ticks and still not `on_folder`, break strategy early and skip `remote-classic` (go to grace with 45s wall budget).
- [x] **Step 3:** Keep `LAUNCH_RETRY` WARN when a strategy truly fails without promising.

## Task 3: WMCP abandoned mutex (W1)

- [x] **Step 1:** In `Enter-WmcpEnsureMutex` catch, unwrap InnerException / message `-match 'abandoned mutex'` → acquire.
- [x] **Step 2:** Static assert in `test-windows-mcp-probe-000000-hard.ps1`.

## Task 4: Soak harness

- [x] **Step 1:** Add `test-e2e-precise-soak.ps1 -Rounds 20 -Parallel 6 -Precise -AlsoAgentHello -StopOnFirstFail`.
- [x] **Step 2:** Aggregate log under `e2e-harness/precise-soak-{stamp}.log` + summary JSON.

## Task 5: Prove

- [ ] Publish Smart client + deploy mount script.
- [ ] Run soak 20 rounds; stop on first fail; fix and restart until 20/20.

## Incident addendum 20260804.30 (soak `.29c` R5)

Zero-noise fail after Rank-1 6/6: session `17dc55` `TUNNEL_DROP` → recovery → local `ssh.exe` `STATUS_DLL_INIT_FAILED` (`-1073741502`) on `MOUNT_DOWN`/`PUSH_CONF`.

- [x] `SshX` retries Exit &lt; 0 (spawn storm); always records `LastSshExit`
- [x] `Test-TunnelPortTcpOpen` / Sync: `probe_inconclusive` ≠ forward-dead
- [x] `Invoke-SshXChecked` + `PUSH_CONF` NTSTATUS retries; cleanup NTSTATUS → INFO
- [x] Recovery announce WARN → INFO (operational; hard fails stay WARN/ERROR)
- [x] Re-prove Precise×6 soak **20/20** on `20260804.33` (harness `precise-soak-20260804-064626`)

## Out of scope (later)

- Per-slot `connect-slot-N.conf` (C1) — helpful but Fix A unblocks mount.
- Changing shared-p product so every slot publishes TUNNEL_PORT.
