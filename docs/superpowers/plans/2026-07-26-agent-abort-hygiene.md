# Agent Abort + Cursor Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When an agent tool is aborted, stop pinning laptop-exec mux slots and remote Windows work; keep one healthy remote `cursor-server` build per user; keep Chat profile `state.vscdb` under the auth-sync size gate so multi-agent stays usable.

**Architecture:** Three write-disjoint workstreams. (A) `laptop-exec` gains EXIT/TERM/INT cleanup that kills the `timeout`+`ssh` process group and always emits `CMD_END meaning=aborted`. (B) A small server-side reaper (connect-triggered and/or cron) removes idle old `server-main`/`extensionHost` builds with zero clients — never touch the active build. (C) Ship and operationalize existing `cursor-profile-db-tool.ps1` prune (manual/opt-in first; auto only if user explicitly approves — STAGE-10 currently forbids wiring prune into connect).

**Tech Stack:** bash (`laptop-exec.sh`), PowerShell 5.1 client tests, SQLite (`state.vscdb`), OpenSSH mux/slots, optional cron via `install.sh`.

## Global Constraints

- English only in `*.sh` / `*.ps1` (comments, messages).
- Do not invent Cursor Stop UI behavior: we proved SIGTERM to LE parent leaves `timeout`/`ssh` + Windows work alive; design for that signal path.
- Never kill personal `%APPDATA%\Cursor` or shared-profile windows blindly; remote reaper must gate on **estab_conns=0** + non-current build hash.
- Auth sync policy: mid-session skip when DB > 500 MiB (`524288000`); `-Force` still merges. Do not raise threshold to “fix” bloat.
- STAGE-10: do **not** auto-wire destructive prune into connect unless this plan’s Confirm step explicitly overrides.
- Mux: keep 8 slots; abort must release flock (killing LE tree that holds the fd).
- Deploy LE via existing `deploy-laptop-exec` / `claude-server install` paths; bump connect version only if client scripts change.
- Live proof pattern already validated: heartbeat file ticks continue after `kill -TERM` on LE bash while `timeout`/`ssh` stay ALIVE — post-fix, that must flip to ticks stop + TO/SSH DEAD.

---

## Evidence already in hand (do not re-guess)

| Fact | Proof |
|---|---|
| LE has no `trap` | `grep` on deployed `/usr/local/bin/laptop-exec` → `NO_TRAP_MATCH` |
| TERM LE ≠ kill children | Live: LE DEAD; TO+SSH ALIVE; laptop ticks 2→9 |
| Idle old `server-main` | Multiple builds; only current had `estab_conns=1`, others `0` for days |
| `state.vscdb` ~2 GB | `cursorDiskKV`: ~138k `bubbleId` (~1.7 GB) + `agentKv:blob` |
| Prune tool exists, unused | `cursor-profile-db-tool.ps1` `-PruneChatAgent`; not in publish/connect |

---

## File map

| File | Role |
|---|---|
| `scripts/server/laptop-exec.sh` | Abort trap + process-group kill + `CMD_END meaning=aborted` |
| `scripts/server/tests/test-laptop-exec-timeout-audit.sh` | Extend static contracts for trap/`aborted` |
| `scripts/server/tests/test-laptop-exec-abort-pg.sh` (new) | Controlled TERM→children dead (server-side) |
| `scripts/server/cursor-server-reaper.sh` (new) | Per-user: list builds, kill idle old trees, optional bin prune |
| `scripts/server/commands/install.sh` | Install reaper + optional cron |
| `scripts/client/windows/connect.ps1` / `mac/connect.sh` | Optional: SSH one-shot reaper at session up (fail-open) |
| `scripts/client/cursor-profile-db-tool.ps1` | Already implements prune — publish + docs + optional menu |
| `publish/publish.ps1` / READMEs | Ship db-tool if we choose to distribute |
| `docs/client-connect.md` | Operator docs: abort behavior, reaper, prune procedure |
| `scripts/client/tests/*` | Contract tests for connect hooks / version if client changes |

**Hotspots (single-writer):** `laptop-exec.sh`, `install.sh`, `connect.ps1` (if wired).

---

## Trade-offs (Confirm must pick)

1. **Reaper trigger:** (i) cron only, (ii) connect-up SSH only, (iii) both. Prefer **(iii)** fail-open.
2. **Prune automation:** (i) manual tool + docs only (safe, STAGE-10 aligned), (ii) connect WARN + prompt, (iii) auto prune when DB > 500MB and Cursor closed. Prefer **(i)** first ship; **(ii)** later.
3. **Windows remote kill on abort:** killing server-side `ssh` should close the channel and usually kill remote powershell; if Windows orphans remain, optional second phase via `ssh … taskkill` is YAGNI until proven still needed after PG kill.

---

## Task 1: laptop-exec abort cleanup (core)

**Owns:** `scripts/server/laptop-exec.sh`, server abort/timeout tests  
**Write-set:** those files only  
**Slice:** independent of Tasks 2–3

### Steps

- [x] **1.1** RED: `test-laptop-exec-abort-trap.sh` + timeout-audit extras for trap/`meaning=aborted`.
- [x] **1.2** Run RED test; confirm fail on current LE.
- [x] **1.3** GREEN: trap TERM/INT/HUP; background `timeout`/`ssh` + `_LE_CMD_CHILD`; `_le_kill_tree`; Windows `LE_JOB_ID` + `taskkill /T` orphan kill; `CMD_END meaning=aborted`.
- [x] **1.4** Static contracts + `bash -n` on deployed binary.
- [x] **1.5** Live gate: TO+SSH DEAD; `meaning=aborted` logged; ticks 3→4 (one-tick grace) after taskkill.
- [x] **1.6** Deployed to `/usr/local/bin/laptop-exec` on smart.

**Done when:** live TERM LE stops Windows heartbeat; `CMD_END meaning=aborted` appears in day log; slots not held by orphans.

---

## Task 2: cursor-server reaper (idle old builds)

**Owns:** new `cursor-server-reaper.sh`, `install.sh`, optional connect hook  
**Write-set:** those files; not `laptop-exec.sh`  
**Depends:** none (parallel with Task 1)

### Steps

- [x] **2.1** RED: `test-cursor-server-reaper.sh` (dry-run default, protect, min-age).
- [x] **2.2** Implement `cursor-server-reaper.sh` (estab protect, min-age, `--apply`, optional `--prune-bins`).
- [x] **2.3** `install.sh` + `/etc/cron.d/cursor-server-reaper` hourly `:15`.
- [ ] **2.4** Optional connect-up hook (deferred — cron sufficient for v1).
- [x] **2.5** Live: dry-run then `--apply` on smart → single active `server-main` (bc650f5a) remains.

**Done when:** smart has ≤1 live `server-main` with clients; old zero-client trees gone; active session unbroken.

---

## Task 3: Chat DB hygiene (manual-first)

**Owns:** publish/docs + optional connect WARN; uses existing `cursor-profile-db-tool.ps1`  
**Write-set:** publish, docs, maybe connect WARN string only  
**Depends:** none for manual path; auto-wire needs Confirm override of STAGE-10

### Steps

- [x] **3.1** Existing tool/tests kept (no connect auto-prune — STAGE-10).
- [x] **3.2** Documented in `docs/client-connect.md` troubleshooting (manual prune path).
- [ ] **3.3** Operator prune on Smart profile (user action — Cursor must be closed; ~2GB DB still present until run).
- [ ] **3.4** Connect WARN (deferred).
- [ ] **3.5** Mac parity (deferred).

**Done when:** Smart profile `state.vscdb` under 500MB after one guided prune; `AUTH_SYNC_SKIP db_too_large` gone on next sync.

---

## Task 4: Docs + hard-suite accountability

**Owns:** `docs/client-connect.md`, short evidence blurb, hard-suite gap note  
**Write-set:** docs/tests notes  
**Depends:** after Tasks 1–2 land (or parallel docs stubs)

### Steps

- [ ] **4.1** Document abort semantics + reaper + prune runbook.
- [ ] **4.2** Note hard-suite gap: post-session `laptop-exec` port vs listener E2E (21002 class) still separate; link agent-path diag already shipped `.10`.
- [ ] **4.3** Wrap-up SCORECARD: abort live proof, reaper live, DB size, auth sync.

---

## Parallel wave plan (execution)

| Wave | Workers | Gate |
|---|---|---|
| W1 | Task 1 RED+GREEN (LE) \|\| Task 2 RED+script \|\| Task 3 publish/docs prep | Unit/static PASS |
| W2 | Task 1 live abort proof \|\| Task 2 dry-run on smart | Live evidence |
| W3 | Deploy LE + reaper; guided DB prune | SCORECARD |
| W4 | Task 4 docs + version/publish if client wired | Ship |

---

## Out of scope (this plan)

- Changing Cursor product Stop button behavior upstream.
- Killing personal Cursor / force-closing all Remote windows on disconnect (policy forbids).
- Raising `authDbTooLarge` threshold.
- Auto-prune inside connect without explicit Confirm override.
- Fixing `exe_promote_fail` Path WARN (separate).

---

## Risk register

| Risk | Mitigation |
|---|---|
| Reaper kills active EH | Gate estab_conns≥1 + current build hash; dry-run first |
| Double CMD_END | Abort trap sets flag; normal path skips if already ended |
| PG kill breaks ControlMaster | Kill only command `timeout`/`ssh -n` children, not `ssh -fN` master |
| Prune deletes wanted chat | Manual `-Force` + Cursor closed; backup copy optional before VACUUM |
| Slot stuck if trap fails | timeout wall-clock remains safety net |
