<!-- Executed Stage 4: 2026-07-28/29 — HT-S HT1 HT2 HT3 HT-ALL PASS; verify PASS -->

---
name: Problem Triage Matrix
overview: "Heavy-task-plan SoT: agent re-education (incl. max parallel tool calls for speed) + tunnel residual + mount class + deny. Wave-ready TDD HT*. Discovery DONE. Awaiting Stage 4 go."
todos:
  - id: stage3-confirm
    content: User go-ahead for Stage 4 (execute waves)
    status: completed
  - id: t0-skill-reeducation
    content: "Task0: skill/mdc/session + PARALLEL fan-out rules + git-p fix; HT-S including parallel markers"
    status: completed
  - id: t1-tunnel
    content: "Task1 Tunnel residual: RED HT1 → GREEN legacy/empty heal + Mac PORT → HT1 PASS"
    status: completed
  - id: t2-mount-die
    content: "Task2 Mount class + DIE NEXT: RED HT2 → GREEN session/guard/DIE → HT2 PASS"
    status: completed
  - id: t3-deny
    content: "Task3 Deny gate: RED HT3 → GREEN beforeShellExecution → pilot → HT3 PASS"
    status: in_progress
  - id: t4-wrap
    content: "Task4 Wrap-up: HT-ALL + verify + Reload note + Memory observation"
    status: pending
isProject: false
---

# Fleet LE routing + agent re-education — Implementation Plan

> **For agentic workers:** REQUIRED: heavy-task-plan Stage 4 = `parallel-phased-execution` (Coordinator→Workers→Verifier). Steps use checkbox syntax. Paste PRIORITY+FAILOVER in every Task prompt.
>
> **SoT plan file:** `~/.cursor/plans/problem_triage_matrix_16861942.plan.md`  
> **On execute, mirror to:** `docs/superpowers/plans/2026-07-28-fleet-le-agent-reeducation.md`

**Goal:** Stop agents repeating LE CLI DIE storms; **maximize wall-clock via parallel tool calls** whenever independent; heal legacy/missing TUNNEL_PORT; classify mount MOUNTED/STALE/NOT_LIVE; optionally deny LE read/rg when MOUNTED — each with hard tests.

**Architecture:** Laptop disk is SoT. Agent behavior = skill + mdc + sessionStart paste (re-education first, including **parallel fan-out caps**). Runtime = `laptop-exec.sh` heal/parser + cursor hooks. Enforce later via conditional Shell deny. Deploy via `deploy-laptop-exec` / `claude-server` to `/usr/local/lib` + all `~/.cursor/*`.

**Tech Stack:** bash hooks, `laptop-exec.sh`, Cursor skills/rules, PowerShell client push, `scripts/server/tests/*-hard.sh`, `sudo-from-laptop`.

## Global Constraints

- English only in repo (no Persian in scripts/docs/skills).
- git only via `laptop-exec git`; Write prefer MCP→mount→LE.
- Do not kill tunnels / MaxStartups stress / ACTIVE_MOUNT casually.
- Prefer last-3h strict `] [LEVEL] […] event=` counts (not substring in `cmd=`).
- Project hooks stay `{"version":1,"hooks":{}}`.
- Hard tests HT* must be zero-fail before next Task.
- LE mux: prefer ≤4 parallel LE; Task Workers ≤4 on this fleet.
- **Parallel-by-default (Cursor agent):** independent Reads/Greps/MCP/Glob/Task in the **same turn**; never serialize when there is no dependency. Caps below are HARD max, not targets to under-shoot when work is independent.

---

## Stage 1 — Discovery (COMPLETE — 2026-07-28)

Evidence already gathered (do not re-litigate):

| Finding | Status |
|---------|--------|
| amir TUNNEL_PORT_MISSING storm | Ended 08:42; conf now 20060 |
| Heal only when PORT **empty** | Wrong legacy 210xx never healed |
| mohammad 21001 / pouyan 21018 | LEGACY; not listening |
| hamed | NO_PORT (Mac) |
| Deny LE when mount LIVE | **Not implemented** |
| Session | `/proc` only; no STALE |
| DIE top | rg flags, git -p, read usage, invent verbs, no git repo |
| `_cmd_git` | Any `-p` in args DIE — breaks `git log -p` |
| Smart client | `.39` vs bundle `.01` |
| Only 2 LIVE mounts | amir/smartclub, smart/review |

**Unknowns resolved enough to design.** Residual product (multi-mount, MUX) deferred.

---

## Stage 2 — Design (this document)

### File map (owns)

| Path | Responsibility |
|------|----------------|
| `scripts/server/skills/laptop-exec/SKILL.md` | Agent cookbook + Shell strategy + Footguns |
| `scripts/server/cursor-rules/laptop-exec.mdc` | Short HARD bullets |
| `scripts/server/cursor-hooks/laptop-exec-session.sh` | MOUNTED/STALE/NOT_LIVE + anti-DIE paste |
| `scripts/server/cursor-hooks/laptop-exec-guard.sh` | ACTIVE_MISMATCH audit; Phase3 deny |
| `scripts/server/laptop-exec.sh` | Legacy/empty PORT heal; `_cmd_git` patch allow |
| `scripts/client/git-mode.sh` (+ `.ps1` if needed) | Mac/Win always push TUNNEL_PORT formula |
| `scripts/server/tests/test-laptop-exec.sh` | Expand DIE/git cases |
| `scripts/server/tests/test-tunnel-port-heal-hard.sh` | **new** HT1 |
| `scripts/server/tests/test-session-mount-class-hard.sh` | **new** HT2 |
| `scripts/server/tests/test-routing-deny-hard.sh` | **new** HT3 |
| `scripts/server/commands/deploy-laptop-exec.sh` | Sync skill/hooks/bin (touch only if markers needed) |

**Hotspots (single-writer — never parallel-write):** `laptop-exec.sh`, `laptop-exec-guard.sh`, `laptop-exec-session.sh`, `SKILL.md`.

### Trade-offs (locked)

| Decision | Choice | Why |
|----------|--------|-----|
| Re-education vs deny first | **Skill/session first** | Fastest agent win; deny ROI low while ACTIVE≠workspace |
| Empty-PORT heal rewrite | Keep; **add legacy heal** | Empty heal exists; legacy is the landmine |
| `git log -p` | Fix parser + skill `--patch` | False DIE is real |
| Multi-mount | Deferred Needs-product | Out of scope |
| 100× speed | Won't-fix | Lab ~20–28× ceiling |

### Execution waves overview

```text
Task0 Agent re-education     (skill ‖ mdc ‖ session paste ‖ git-p) → HT-S
Task1 Tunnel residual        (heal LE ‖ client push Mac) → HT1
Task2 Mount class + DIE      (session ‖ DIE strings) → HT2  [guard deny later]
Task3 Deny gate              (guard only) → HT3
Task4 Wrap-up                HT-ALL + verify
```

---

## Task 0 — Agent re-education (ship first)

**Goal:** Agents stop repeating top DIE patterns **and** always fan out independent tool calls for speed after Reload Window.

### Parallel fan-out contract (must land in skill + mdc + session + Task paste)

| Path | Max parallel same turn | Rule |
|------|------------------------|------|
| Cursor Read / Grep on healthy mount | **~16–32** | Batch independent files/patterns in one response |
| MCP FileSystem / Select-String / search | **~8–12** | Abs Windows paths; one hard fail → MCP down |
| `laptop-exec` (read/rg/git/run) | **≤4** (hard mux 8) | Prefer mount/MCP first when healthy |
| Task subagents | **≤4** (plan waves 3–5) | Paste PRIORITY+FAILOVER; children do not inherit |
| Failover | same turn | If 1st path errors → 2nd then 3rd **without** waiting for a new user message |

**Anti-patterns to name in skill:**

- Serial Read of N files when all paths known → instead N parallel Reads  
- LE read loop while mount LIVE → Cursor Read parallel  
- One mega-Shell that greps everything → parallel Grep / python once  
- Waiting to “finish” tool A before starting independent tool B  

### Step 0.1 RED (wave: 1 Worker)

- [ ] Add failing tests to `test-laptop-exec.sh` (or HT-S harness):
  - `git -p ID -- log -p -1` must **not** hit “-p BEFORE” DIE (will fail on current code)
  - `git status -p ID` must still DIE
- [ ] Run tests — expect FAIL on log -p
- **Owns:** `scripts/server/tests/test-laptop-exec.sh`
- **Gate:** RED observed

### Step 0.2 GREEN wave (parallel Workers — disjoint writes)

| Worker | Owns | Does |
|--------|------|------|
| W0a | `SKILL.md` | Footguns + Shell strategy + Command cookbook + **Parallel fan-out** section (caps table + anti-patterns) |
| W0b | `laptop-exec.mdc` | HARD bullets incl. `PARALLEL: mount~16-32 MCP~8-12 LE≤4 same turn` |
| W0c | `laptop-exec.sh` `_cmd_git` only | Allow `-p/--patch` after `log|show|diff`; keep wrong-order DIE |
| W0d | `laptop-exec-session.sh` + Task paste in guard | Anti-DIE line + **explicit parallel caps** in `additional_context` / Task allow |

- [ ] W0a–W0d in **one** Coordinator batch
- [ ] Integrate; run HT-S.1–S.4 + S.5 grep markers (**must include** `16-32`, `LE≤4` or `LE <=4`, `same turn`)
- **Gate:** HT-S.1–S.5 PASS

### Step 0.3 Deploy

- [ ] `deploy-laptop-exec` / sync skill+rule+hooks+bin to all users
- [ ] HT-S.6 sha spot-check ≥3 users
- [ ] Operator note: **Reload Window**
- **Gate:** HT-S.6–S.7 PASS

---

## Task 1 — Tunnel residual

### Step 1.1 RED

- [ ] New `test-tunnel-port-heal-hard.sh` covering HT1.1–1.4, 1.7 (fixtures; no live amir required for unit)
- [ ] Run — FAIL until heal supports legacy
- **Owns:** new test file
- **Gate:** RED

### Step 1.2 GREEN wave

| Worker | Owns | Does |
|--------|------|------|
| W1a | `laptop-exec.sh` `_load_global` | If PORT set and equals `20000+uid` and formula TCP live → rewrite + LEGACY_HEALED |
| W1b | `git-mode.sh` (+ ps1 if gap) | Mac/Win Push always writes TUNNEL_PORT formula |

- [ ] Parallel W1a ‖ W1b
- [ ] One-shot ops (Coordinator): hamed/mohammad/pouyan conf fix if safe
- **Gate:** HT1.* PASS (HT1.5–1.6 may need live/sudo)

---

## Task 2 — Mount class + DIE NEXT

### Step 2.1 RED

- [ ] `test-session-mount-class-hard.sh` covering **HT2.1–2.9** (mount class + DIE storms + no mountpoint -q)
- **Gate:** RED

### Step 2.2 GREEN wave

| Worker | Owns | Does |
|--------|------|------|
| W2a | `laptop-exec-session.sh` | MOUNTED/STALE/NOT_LIVE via `_sshfs_state` semantics; ACTIVE_MISMATCH |
| W2b | `laptop-exec.sh` DIE NEXT strings only | Tighten D1/D6/D8/D9/D12 messages |

- [ ] Do **not** edit guard deny here (Task3)
- **Gate:** HT2.* PASS

---

## Task 3 — Conditional deny

### Step 3.1 RED

- [ ] `test-routing-deny-hard.sh` covering **HT3.1–3.11**
- **Gate:** RED

### Step 3.2 GREEN

| Worker | Owns | Does |
|--------|------|------|
| W3a | `laptop-exec-guard.sh` `beforeShellExecution` | Deny read/rg iff MOUNTED; kill-switch; structured agent_message |

- **Gate:** HT3.* PASS on smart pilot (review MOUNTED vs CCS NOT_LIVE)

---

## Task 4 — Wrap-up

- [ ] HT-ALL.1–6
- [ ] `sudo claude-server verify`
- [ ] Fleet last-3h strict counters snapshot
- [ ] Memory MCP short convention observation (no secrets)
- [ ] Mirror plan → `docs/superpowers/plans/2026-07-28-fleet-le-agent-reeducation.md`
- [ ] Summarize verified commands + deferred (multi-mount, MUX, 100×)

---

## Hard test index (SoT)

- **HT1.** tunnel empty/legacy/dead/correct/Mac/strict log/substring/pardis  
- **HT2.** MOUNTED/STALE/NOT_LIVE/mismatch/DIE storms/no mountpoint -q  
- **HT-S.** git patch allow/wrong-order DIE/skill markers incl. **parallel caps `16-32` / `LE≤4` / `same turn`**/sha sync  
- **HT3.** deny/allow/kill-switch/STALE/false-positive/env prefix/sudo/A-8/fail-open  
- **HT-ALL.** suite + legacy gone + MISSING quiet + deny pilot + skill sync + verify  

---

## Stage 3 — Confirm (WAITING)

**Short summary for go-ahead:**

1. **First:** Task0 skill+mdc+session+git `-p` fix + **parallel fan-out caps** (mount~16–32, MCP~8–12, LE≤4, same-turn failover) + deploy.  
2. **Then:** legacy/empty PORT heal + Mac push.  
3. **Then:** mount class STALE + DIE NEXT.  
4. **Then:** deny LE read/rg when MOUNTED.  
5. Every Task = RED tests → GREEN → HT gate. Parallel Workers only on disjoint owns. Cursor agents must batch independent tool calls every turn.

**Deferred:** multi-mount, MUX redesign, MCP footguns product, 100×.

Reply **`برو` / `execute` / `go`** to start Stage 4 (parallel-phased-execution).  
Reply with scope cuts if you want Task0 only first.

---

## Appendix — triage leftovers

Won't-fix / Needs-product / live re-check tables from prior investigation remain valid; see conversation evidence 2026-07-28. Day-total amir MISSING=735 is historical (last event 08:42).

---

## Final review (2026-07-28) — readiness for Stage 4

### Verdict: **READY to execute** with the patches below locked in

Plan is coherent (heavy-task + TDD RED→GREEN + HT gates + parallel agent contract). Discovery is sufficient. Stage 3 still needs user **`برو`**.

### Consistency — PASS

| Check | Result |
|-------|--------|
| Order Task0→1→2→3→4 | Matches deny-after-signals and skill-first trade-off |
| Parallel fan-out in Goal / Constraints / Task0 / HT-S / Confirm | Aligned |
| Hotspots listed | Correct for within-wave Workers |
| English-only / empty project hooks / no tunnel kill | Present |
| Deferred multi-mount / MUX / 100× | Explicit |

### Gaps fixed into this review (treat as plan amendments)

1. **`laptop-exec.sh` cross-Task serialization (critical)**  
   Touched by Task0 W0c (`_cmd_git`), Task1 W1a (`_load_global`), Task2 W2b (DIE strings).  
   **Rule:** never parallelize those Tasks; within a Task only one Worker owns `laptop-exec.sh`. Already sequential Tasks — call out in Stage 4 Coordinator brief.

2. **Task2 RED under-scoped**  
   Expand Step 2.1 to HT2.1–2.9 (not only 2.1–2.4, 2.9). DIE storm cases HT2.5–2.8 are required before GREEN.

3. **Task3 RED under-scoped**  
   Expand Step 3.1 to HT3.1–3.11 (include A-8 + fail-open).

4. **ACTIVE_MISMATCH ownership**  
   File map lists guard + session; Task2 only session. **Lock:** sessionStart emits mismatch; guard optional audit log in Task2 W2a only (no guard deny until Task3).

5. **Ops leftovers not in Task1 steps (add Coordinator bullets)**  
   - Spot-fix conf: hamed NO_PORT, mohammad/pouyan legacy (if tunnels allow).  
   - Note Smart client `.39` vs bundle `.01` — reconnect/`u` or document as follow-up (not block Task0).  
   - pardis username sanitize = **optional** client follow-up (HT1.8 only if shipped).

6. **Sync Rule**  
   Any change to `laptop-exec.sh` / cursor-hooks / skill / mdc → update `install.sh` deploy section if needed + `deploy-laptop-exec` / `claude-server install` as appropriate (CLAUDE.md Sync Rule).

7. **Stage 4 Task prompts**  
   Every Worker prompt must paste PRIORITY+FAILOVER + parallel caps + owns/reads/done criteria + report path (parallel-phased-execution).

### Risk register (accept / mitigate)

| Risk | Mitigation |
|------|------------|
| Skill text ignored (history) | Task0 + Reload; Task3 deny later for read/rg |
| Legacy heal false-positive on intentional odd PORT | Only rewrite when PORT == `20000+uid` exactly |
| STALE mis-detect → deny blocks LE | Task3: deny only `MOUNTED`, allow STALE/NOT_LIVE |
| HT1.6 needs live tunnel | Soft-gate: unit HT1.1–1.4 hard-required; 1.5–1.6 best-effort same day |
| Mux pressure from parallel Reads | Caps already; LE≤4 hard |

### Not in scope (do not sneak into Stage 4)

- Multi-mount / connect “mount this workspace”  
- MUX_RECREATE redesign  
- MCP Desktop-relative product fix  
- Central fleet log aggregator  
- Claiming 100×  

### Execute checklist (when user says go)

1. Switch to Agent mode / Stage 4.  
2. Task0 only wave first if user said Task0-only; else 0→1→2→3→4 with HT gates.  
3. Commit only if user asks (git via `laptop-exec git`).  
4. Mirror plan to `docs/superpowers/plans/2026-07-28-fleet-le-agent-reeducation.md` in Task4.
