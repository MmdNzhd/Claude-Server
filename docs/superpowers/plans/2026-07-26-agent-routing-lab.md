# Agent Routing Lab (windows-mcp / mount / laptop-exec) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a disposable lab under the existing `temp` mount, run one challenge per wave to surface agent routing confusion, then fix skill/rule/hook wording (and only real tool bugs) until each challenge has a clear winning path.

**Architecture:** Lab lives on project `temp` (`D:/temp` ↔ `/home/smart/mounts/temp`), not inside `claude-code-server`, so path/project-id mistakes are visible. Fixtures encode expected 1st-tool per action. Challenges produce evidence files; each FAIL drives a single-writer fix in deployable laptop-exec artifacts, then re-run. Cleanup is user-gated.

**Tech Stack:** windows-mcp (`FileSystem`, `PowerShell`), Cursor mount tools, `laptop-exec` CLI, deploy via `sudo claude-server install` / `deploy-laptop-exec` for server copies; live user copies under `~/.cursor/skills|rules|hooks`.

## Global Constraints

- English only in repo (no Persian in files/docs/skills).
- Lab root: `agent-routing-lab/` under mount project `temp` only.
- Path triple (must stay consistent in all challenges):
  - Mount: `/home/smart/mounts/temp/agent-routing-lab/...`
  - Windows MCP: `D:\temp\agent-routing-lab\...` (absolute; never Desktop-relative)
  - laptop-exec: `-p temp` + repo-relative `agent-routing-lab/...`
- `ACTIVE_MOUNT` may be `claude-code-server` — always pass `-p temp` for lab I/O via LE.
- Do not delete lab until user explicitly says cleanup.
- Prefer ≤4 parallel `laptop-exec`; ~8–10 parallel windows-mcp when independent.
- FAIL-FAST: one windows-mcp hard failure → MCP down for session; no retry.
- `user-filesystem` ≠ `windows-mcp`.
- `laptop-exec rg`: reject `-i`/`-l`/`-n`/`--glob`; exit 1 = no matches.
- git for lab (if any): `laptop-exec git -p temp` only.
- Do not commit unless user asks.
- After durable learnings: write short facts to Memory MCP (`user-memory`).

## Evidence refs (deep discovery 2026-07-26)

### Discovery subagent merge
Integrated reports from: [Discover LE confusion points](117fd4bb-402a-48ff-baa4-1d1c933df845), [Discover MCP path quirks](90f03bb5-6d7e-42c8-bc6a-51eec54ff68d), [Deep LE contradiction audit](77e14225-0831-443c-ad70-f63b467c6ad0), [Deep agent failure log mine](a2378bfb-f89c-4a6d-ae8f-406da778ff3d). Live re-verify: `dakhl` inject lacks `LAPTOP_REMOTE_PATH`; orphan Jul-19 hooks still in workspace.



### Path / env SoT

- Mount conf: `~/.claude-mounts.d/temp.conf` → `rpath=D:/temp`, `lpath=/home/smart/mounts/temp`
- Active workspace often `claude-code-server` (`REMOTE_PATH=D:/Smart/Claude-Code-Server`) while lab must use `-p temp`
- `laptop-exec status` prefer line (live): `READ/GREP/GLOB=MCP|mount; WRITE=mount; git=LE`
- Cursor MCP pack key in `~/.cursor/mcp.json`: `windows-mcp` → `http://127.0.0.1:28002/mcp`
- Tool namespace agents actually call: `user-windows-mcp` (Cursor prefix) — name mismatch confuses “is MCP ready?”

### Live-proven footguns (this session)

| ID | Proof | Effect |
|----|-------|--------|
| Desktop-relative MCP | FileSystem read `agent-routing-lab/fixtures/alpha.txt` → error path `C:\Users\Smart\Desktop\agent-routing-lab\...` | Silent wrong root unless absolute |
| Temp casing | PowerShell `(Get-Item D:\temp).FullName` → `D:\Temp` | Docs mix `D:/temp` vs `D:\Temp` |
| Wrong LE project path | Log `16:24:05` DIE `cannot resolve project from: tmp/agent-routing-lab` (discovery subagent, no `-p temp`) | Agents invent `tmp/` under wrong project |
| Policy flip same day | `HOOK_DENY`×25 on Read/Grep/Glob/Shell **until ~08:28**; after that ALLOW. Skill/rule say ALLOW. | Morning deny text still in agent muscle memory / old NEXT strings |
| `rg --glob` | `09:28:44` `RG_FLAG_REJECTED` + DIE | Real production footgun |
| LE CLI UX | DIE `usage: laptop-exec read...` (missing file); `unknown command 'status '` (trailing space) | Agents mis-invoke CLI |
| Mux pressure | `MUX_RECREATE`×168 today; `CMD_TIMEOUT` 120s “Hung remote cmd pinned a mux slot” | Parallel LE storms / tunnel flaps |
| ACTIVE_MOUNT ≠ `-p` | Many cmds: `project=refactoreoldclub` + `active_mount=claude-code-server` — OK only when `-p` explicit | Omitting `-p` writes/reads wrong tree |

### Stale / contradictory guidance (ranked)

**P0 — causes wrong tool choice** (merged from discovery subagents + live verify)

1. `reference-windows-mcp.md` FAIL-FAST #1–#2 (L40–44): MCP-down → *use laptop-exec immediately* + *never retry Cursor Read on mounts* — **contradicts** `SKILL.md` L51–54 (*mount + laptop-exec*). Also collapses Write to MCP/LE vs mount-first.
2. **Hook `_remote_path_for` ignores `rpath=`** (session + guard match only `REMOTE_PATH|remote_path`; `laptop-exec.sh` accepts `rpath|REMOTE_PATH`). Live proof: `dakhl` session inject has **no** `LAPTOP_REMOTE_PATH`; `claude-code-server` (`REMOTE_PATH=`) does. Most mounts use `rpath=` → agents invent Desktop/`C:\Users\...` paths for MCP.
3. **Orphan project hooks** (inactive but searchable): `.cursor/hooks/laptop-exec-{session,guard}.sh` dated Jul 19 still say *SSH-FIRST HARD STOP / Never call Cursor Read… on mounts*. Project `hooks.json` is empty so they do not run — agents reading workspace still get poisoned.
4. Guard Write NEXT (~L315–322) prefers MCP FileSystem write over mount; FAIL-FAST `ff` (~L298) says *never retry Read* / LE-immediate (deny-path mostly dead, still teaches wrong fallback).
5. Stale Task paste blocks: `parallel-phased-execution/SKILL.md` (~L225) and `evidence-gated-stages/.../multi-agent.md` still *no Read/Grep on mounts*.
6. `laptop-exec status` recommend string still *laptop-exec for agent work; SSHFS for manual IDE edits* — pre-hybrid.
7. LE path UX: `/home/.../mounts/...` → opaque Windows `Resolve-Path`; Windows abs `D:/...` works → three LE path dialects.
8. Soft-only routing (deny dead) + namespace `windows-mcp` vs `user-windows-mcp` + FileSystem schema (`mode` not `action`) from server.error.log.

**Lab location decision (locked):** keep project **`temp`** → `D:/temp/agent-routing-lab/` (user request). Reject alternate suggestion to put lab under `claude-code-server/tmp/` — that hides wrong-`-p` / cross-project path bugs that this lab must expose.

**P1 — stale comments / leftover deny-era**

5. Guard `_shell_should_block` comment (~L144–146): *“Read/Grep/Glob tools still denied in preToolUse”* while `_tool_targets_mounts` ALLOWs them (~L178–183).
6. Branding “SSH-first” everywhere while behavior is **hybrid** — agents over-index to LE.
7. Skill HARD STOP still framed around deny/NEXT; mounts are ALLOW so deny path is rare — preference not enforcement.

**P2 — docs / ops**

8. `CLAUDE.md` hybrid summary is correct but still labels rule file “SSH-first”.
9. Prior `D:\temp\audit_wmcp.py` only audited windows-mcp auth copies — not agent routing.

### Speed & quality bench (live 2026-07-26 ~20:05, file `.bench-routing-speed.txt` ≈64KB)

Tunnel UP, SSHFS mounted, windows-mcp via `127.0.0.1:28002` (session + Bearer). Numbers are wall-clock on this host — not Windows-local disk alone.

| Op | MCP (HTTP tools/call) | Mount (Cursor/SSHFS) | laptop-exec |
|----|----------------------:|---------------------:|------------:|
| Read ~64KB (avg) | **106 ms** (full) / 84 ms (limit5) | **48 ms** | **1604 ms** |
| Write short (avg) | **76 ms** | **175 ms** | **1232 ms** |
| Content search | Select-String via PowerShell tool **456 ms** | `grep` file **81 ms** | `rg` **1734 ms** |
| Parallel ×4 reads (wave wall) | **192 ms** | **70 ms** | **2173 ms** |

Windows-local only (no MCP RTT): File read ~1 ms, Select-String ~8 ms — proves MCP overhead is mostly HTTP/session, not disk.

**Consistency (quality) smoke:** mount write → LE size match; LE write → mount+MCP readback OK (tunnel UP, ~0.3s).

### Parallel load (same 64KB file, simultaneous workers)

Artifacts: `/tmp/bench-routing-load.json`, `/tmp/bench-routing-load-heavy.json`.

| Wave | ok/fail | wall | avg/call | p95 | throughput |
|------|---------|-----:|---------:|----:|-----------:|
| mount ×8 | 8/0 | 149 ms | 133 ms | 143 ms | **54 rps** |
| mount ×16 | 16/0 | 90 ms | 80 ms | 84 ms | **179 rps** |
| mount ×32 | 32/0 | 147 ms | 122 ms | 134 ms | **217 rps** |
| mount ×48 | 48/0 | 202 ms | 161 ms | 183 ms | **238 rps** |
| mount ×64 | 64/0 | 227 ms | 190 ms | 205 ms | **282 rps** |
| MCP ×8 | 8/0 | 334 ms | 211 ms | 295 ms | 24 rps |
| MCP ×16 | 16/0 | 587 ms | 379 ms | 566 ms | 27 rps |
| MCP ×32 | 32/0 | 1164 ms | 722 ms | 1118 ms | **~27 rps (flat)** |
| MCP ×48 | 48/0 | 1752 ms | 1029 ms | 1693 ms | **~27 rps** |
| MCP ×64 | 64/0 | 2261 ms | 1259 ms | 2144 ms | **~28 rps** |
| LE ×4 | 4/0 | 2287 ms | 2199 ms | 2251 ms | 1.8 rps |
| LE ×8 | 8/0 | 2944 ms | 2681 ms | 2926 ms | 2.7 rps |
| LE ×12 | 12/0 | 4099 ms | 3238 ms | 4058 ms | 2.9 rps |
| LE ×16 | 16/0 | 4650 ms | 3380 ms | 4380 ms | 3.4 rps |
| mount grep ×16 | 16/0 | 161 ms | 120 ms | 148 ms | **99 rps** |
| MCP Select-String ×8 | 8/0 | 851 ms | 781 ms | 834 ms | 9.4 rps |
| LE rg ×4 | 4/0 | 2156 ms | 2055 ms | 2133 ms | 1.9 rps |

### Multi-round validity (HIGH-N, 2026-07-26 ~20:15)

Artifact: `/tmp/bench-routing-multiround-N30.json`.

Round counts: idle ×**30**, load×16 ×**25**, load×32 ×**20**, LE×8 ×**15**, paired ×**25**.

| Scenario | n | wall mean±σ | median | p95 | CV | rps mean | fails |
|----------|--:|------------:|-------:|----:|---:|---------:|------:|
| idle mount ×1 | 30 | 101±19 ms | 103 | 135 | 19% | 10.7 | 0 |
| idle MCP ×1 | 30 | **81±22 ms** | 87 | 111 | 27% | 13.4 | 0 |
| idle LE ×1 | 30 | 1738±63 ms | 1725 | 1875 | **4%** | 0.6 | 0 |
| load mount ×16 | 25 | **145±38 ms** | 148 | 211 | 26% | 120 | 0 |
| load MCP ×16 | 25 | 1424±486 ms | 1691 | 1744 | 34% | 14 | 0 |
| load LE ×4 | 25 | 2364±208 ms | 2290 | 2833 | 9% | 1.7 | 0 |
| load mount ×32 | 20 | **170±32 ms** | 165 | 226 | 19% | 194 | 0 |
| load MCP ×32 | 20 | 3137±858 ms | 3467 | 3563 | 27% | 12 | 0 |
| load LE ×8 | 15 | 3116±182 ms | 3043 | 3333 | 6% | 2.6 | 0 |

**Paired ranking** (mount×16 vs MCP×16 vs LE×4), n=25:
- first place: mount **25/25**, MCP 0, LE 0
- P(mount&lt;mcp)=**1.00**, P(mount&lt;le)=**1.00**, P(mcp&lt;le)=**1.00**

**Validity notes:**
- 5-round MCP×16 (~559 ms) was optimistic; at n=25 median wall ~**1.7 s** (congestion / session aging). Multi-round required.
- Idle: MCP slightly ahead of mount on mean (overlap in noise); **not** a stable policy signal alone.
- Load: mount dominates with **100% win-rate** over 25 paired rounds.
- LE: lowest CV, always last by ~10–20× under load.
- Lab C13–C14 must use ≥20 rounds + report median/p95/CV/win-rate (not single shot).


**Load conclusions:**
1. Mount Read **scales** with concurrency (rps keeps rising; wall stays ~0.1–0.2s even at ×64).
2. MCP Read **saturates ~27–28 rps**; more parallelism only grows latency (p95 >2s at ×64) — still 0 fails.
3. LE under fan-out stays ~2–3.5 rps; ×16 did not hard-fail here but per-call ~3.4s (mux queue). Unsafe as default under multi-agent storms.
4. Content search under load: mount grep ≫ MCP Select-String ≫ LE rg.

**Policy tension (must decide in Task 4 / skill note):**
- Rule text cites older evidence `MCP read 19ms / mount 434ms / LE 9080ms`.
- Live idle: **mount ≤ MCP ≪ LE** for Read; **MCP ≤ mount ≪ LE** for Write; content search **mount grep ≪ MCP Select-String ≪ LE rg**.
- Live **under load**: mount wins harder; MCP plateaus; LE collapses relative to both.
- “SSHFS dies under parallel” was **not** observed for read×64 on this session. MCP-first for Read/Grep needs a non-speed reason or should flip to **mount-first when ALLOW + tunnel UP**, MCP when mount unhealthy, LE last / git always.

**Quality dimensions (beyond ms):**

| Dimension | MCP | Mount | LE |
|-----------|-----|-------|-----|
| Laptop truth / git SoT | good (direct) | STALE risk | **SoT** (git only here) |
| Error clarity | Desktop-relative trap | normal FS errors | opaque `Resolve-Path` on Linux paths |
| Mux / slot pressure | none | none | **caps ≤4 / 8** |
| Parallel fan-out | excellent | excellent | weak |
| Agent-preference enforcement | soft | soft (deny dead) | CLI hard fails on flags |

### Precision audit (2026-07-26 ~20:00)

| Check | Result |
|-------|--------|
| Digests live ↔ repo ↔ `/usr/local` for guard/session/wrap/skill/rule/reference | **Identical** (no copy drift) |
| Guard dry-run Read/Grep/Glob/Write/Shell → mount | all `{"permission":"allow"}` |
| Last real `HOOK_DENY` today | **08:28:41** (Grep+Glob); none since |
| `_tool_targets_mounts` for Read\|Grep\|Glob\|Write\|Shell\|Task | always returns 1 → **preToolUse deny branch is dead code** |
| `_shell_should_block` | always `return 1` → Shell deny also dead |
| `reference-windows-mcp.md` L42–44 vs `SKILL.md` L51–54 | **Contradiction:** reference says never retry Cursor Read on mounts; skill says use mount + LE |
| Guard `ff` L298 `never retry Read` | Only reachable if deny fires; currently unreachable, still poisons maintainers / future re-enable |
| LE with `/home/.../mounts/...` path | No friendly reject — Windows `Resolve-Path` *Cannot find path '/home/smart/mounts/...'* |
| LE with `D:/Smart/...` abs | Works (forwards to Windows) — agents may mix path forms |
| MCP relative path | Confirmed → `C:\Users\Smart\Desktop\...` |
| Preference enforcement | **Soft only** (skill/rule/session). Hook no longer steers via deny |

### What already AGREES (do not “fix”)

- Live + repo `SKILL.md` priority table (MCP → mount → LE for Read/Grep/Glob; mount Write; LE git)
- Live + repo `laptop-exec.mdc` same table + ALLOW hooks
- `laptop-exec-session.sh` hybrid strings (Select-String / mount Write)
- Project `hooks.json` empty; user hooks use guard-wrap (good)
- Three install locations are already in sync — fixes need one edit + deploy, not three hand-patches

## Anti-patterns / hard rejects

- Teaching agents to always use laptop-exec first for Read when MCP is listed.
- Re-denying Cursor Read/Grep/Glob/Write on mounts (policy is ALLOW; preference is MCP-first).
- Using FileSystem `search` as content Grep.
- Retrying the same MCP call after ECONNREFUSED / not connected.
- After MCP down: skipping mount and jumping only to LE for ordinary Read/Write.
- Lab under `claude-code-server/tmp/...` (already caused DIE) — must be project `temp`.
- Committing lab fixtures without user ask.
- “Fixing” by expanding encyclopedia in CLAUDE.md instead of skill/reference/guard NEXT text.

## Admit criteria (lab-wide)

Each challenge C1–C16 produces `agent-routing-lab/results/C#.md` with: tool used, path form, latency note, PASS/FAIL vs expected 1st tool, confusion note. Speed challenges must attach measured ms. A challenge is ADMITTED when re-run after fix is PASS, or FAIL is documented as intentional tool limit with skill/reference warning added. C16 requires an explicit human/operator decision: keep MCP-first (document non-speed reason) or switch Read/Grep preference to mount-first when ALLOW.

---

### Task 1: Scaffold lab fixtures under `temp`

**Files:**
- Create: `D:/temp/agent-routing-lab/README.md` (via mount write preferred)
- Create: `agent-routing-lab/fixtures/alpha.txt`
- Create: `agent-routing-lab/fixtures/beta.txt`
- Create: `agent-routing-lab/fixtures/nested/gamma.txt`
- Create: `agent-routing-lab/fixtures/NEEDLE_UNIQUE_ZZZ.txt` (content contains `NEEDLE_UNIQUE_ZZZ`)
- Create: `agent-routing-lab/challenges/CHALLENGE-MATRIX.md`
- Create: `agent-routing-lab/results/.gitkeep`
- Owns write-set: only under `agent-routing-lab/` on project `temp`

**Interfaces:**
- Consumes: mount `temp`, windows-mcp ready, `laptop-exec -p temp`
- Produces: fixture tree + matrix listing C1–C12 expected 1st tools

**Slices (wave-ready):**
- Slice A owns: `README.md`, `CHALLENGE-MATRIX.md`, `results/.gitkeep`
- Slice B owns: `fixtures/**`

- [ ] **Step 1: Create directory + README via mount Write (preferred write path)**

Write `/home/smart/mounts/temp/agent-routing-lab/README.md`:

```markdown
# Agent Routing Lab

Disposable. Delete only when operator says cleanup.

## Path triple

| Form | Value |
|------|-------|
| Mount | `/home/smart/mounts/temp/agent-routing-lab/` |
| Windows MCP | `D:\temp\agent-routing-lab\` |
| laptop-exec | `-p temp` + `agent-routing-lab/...` |

ACTIVE_MOUNT may differ — always `-p temp` for LE.
```

- [ ] **Step 2: Write fixtures (parallel mount writes OK)**

`fixtures/alpha.txt` → `alpha-line-1\nshared-token\n`
`fixtures/beta.txt` → `beta-line-1\nshared-token\n`
`fixtures/nested/gamma.txt` → `gamma-line-1\n`
`fixtures/NEEDLE_UNIQUE_ZZZ.txt` → `prefix NEEDLE_UNIQUE_ZZZ suffix\n`

- [ ] **Step 3: Write CHALLENGE-MATRIX.md**

```markdown
# Challenge matrix

| ID | Action | Expected 1st | Fallback 2 | Fallback 3 | Probe |
|----|--------|--------------|------------|------------|-------|
| C1 | Read file | windows-mcp FileSystem read abs | mount Read | LE read | `fixtures/alpha.txt` |
| C2 | Content Grep | MCP PowerShell Select-String | mount Grep | LE rg | pattern `NEEDLE_UNIQUE_ZZZ` |
| C3 | Filename Glob | MCP FileSystem search/list | mount Glob | mount ls / LE run | `**/gamma.txt` |
| C4 | Write/Edit | mount Write/StrReplace | MCP FileSystem write | LE write | create `scratch/c4.txt` |
| C5 | Wrong LE project | must fail or miss | — | — | `laptop-exec read -p claude-code-server agent-routing-lab/fixtures/alpha.txt` |
| C6 | Relative MCP path | must NOT invent Desktop file | abs path | — | FileSystem read `agent-routing-lab/fixtures/alpha.txt` (relative) |
| C7 | LE rg banned flags | reject | pattern alt | — | `laptop-exec rg -p temp -i needle` AND `--glob` |
| C8 | Parallel fan-out | 4 MCP reads same turn | — | — | alpha+beta+gamma+needle |
| C9 | MCP-down fallback | mount Read (not LE-only) | LE read | — | Simulate: after documenting FAIL-FAST text; verify skill says mount then LE |
| C10 | Namespace ready check | treat `user-windows-mcp` listed = ready | — | — | Confirm tools listed under `user-windows-mcp` even if mcp.json key is `windows-mcp` |
| C11 | LE CLI misuse | clear usage error | — | — | `laptop-exec read -p temp` (no file); `laptop-exec 'status '` trailing space |
| C12 | Path form `/mounts/` in LE | reject / DIE | use REL | — | `laptop-exec read -p temp /home/smart/mounts/temp/agent-routing-lab/fixtures/alpha.txt` |
| C13 | Speed gate Read | record MCP/mount/LE ms | — | — | same ~64KB fixture; fail if LE not ≫ others |
| C14 | Speed gate Grep | mount vs Select-String vs LE rg | — | — | document winner; update skill rationale if mount wins |
| C15 | Quality consistency | mount↔MCP↔LE same bytes after write | — | — | write via each path; cross-read |
| C16 | Policy decision | speed-optimal vs MCP-first | — | — | explicit skill paragraph: why MCP-first if mount faster |
```

- [ ] **Step 4: Verify path triple once**

Run (parallel OK):
1. windows-mcp FileSystem `list` `D:\temp\agent-routing-lab`
2. mount `ls /home/smart/mounts/temp/agent-routing-lab`
3. `laptop-exec run -p temp -- dir agent-routing-lab`

Expected: all three see same tree.

- [ ] **Step 5: Gate**

PASS if all three list `fixtures` and `challenges`. No commit unless user asks.

---

### Task 2: Run challenges C1–C4 (happy-path routing) and record evidence

**Files:**
- Create: `agent-routing-lab/results/C1.md` … `C4.md`
- May create: `agent-routing-lab/scratch/c4.txt`

**Interfaces:**
- Consumes: Task 1 fixtures
- Produces: PASS/FAIL evidence for Read/Grep/Glob/Write

**Slices:**
- Wave 1 (disjoint results): C1 ‖ C2 ‖ C3 (read-only probes)
- Wave 2: C4 write (after wave 1 gate)

- [ ] **Step 1: C1 Read — MCP first**

Call windows-mcp FileSystem `read` path `D:\temp\agent-routing-lab\fixtures\alpha.txt`.
Record in `results/C1.md`: PASS if content has `alpha-line-1`. Note if agent instinct was LE/mount instead.

- [ ] **Step 2: C2 Content Grep — Select-String first**

windows-mcp PowerShell:

```powershell
Select-String -Path 'D:\temp\agent-routing-lab\fixtures\*' -Pattern 'NEEDLE_UNIQUE_ZZZ' -SimpleMatch
```

PASS if hit file `NEEDLE_UNIQUE_ZZZ.txt`. FAIL if used FileSystem search for content.

- [ ] **Step 3: C3 Glob — FileSystem search**

windows-mcp FileSystem `search` under `D:\temp\agent-routing-lab` pattern `**/gamma.txt` (or list+filter if search glob differs).
PASS if finds nested gamma.

- [ ] **Step 4: C4 Write — mount first**

Cursor Write to `/home/smart/mounts/temp/agent-routing-lab/scratch/c4.txt` with body `c4-ok`.
Verify via MCP read abs path. PASS if mount write then MCP read agree.

- [ ] **Step 5: Gate**

All C1–C4 results written. List FAIL reasons for Task 3.

---

### Task 3: Run challenges C5–C12 (footguns) and record evidence

**Files:**
- Create: `agent-routing-lab/results/C5.md` … `C12.md`

**Slices:** Wave A: C5 ‖ C6 ‖ C7 ‖ C11; Wave B: C8 ‖ C10 ‖ C12; Wave C: C9 (docs/text verify + optional mount fallback demo).

- [ ] **Step 1: C5 wrong `-p`**

```bash
laptop-exec read -p claude-code-server agent-routing-lab/fixtures/alpha.txt
```

Also record the real DIE already seen: `cannot resolve project from: tmp/agent-routing-lab`.
Expected: fail / missing (file lives on `temp`). PASS = evidence why `-p temp` + REL under that project.

- [ ] **Step 2: C6 relative MCP path**

FileSystem `read` with path `agent-routing-lab/fixtures/alpha.txt` (no drive).
**Already proven:** resolves under `C:\Users\Smart\Desktop\...`. Reconfirm and file `C6.md`. Skill/reference must say absolute-required with Desktop example.

- [ ] **Step 3: C7 banned rg flags**

```bash
laptop-exec rg -p temp -i NEEDLE agent-routing-lab/
laptop-exec rg -p temp --glob '*.txt' NEEDLE agent-routing-lab/
```

Expected: both rejected (`RG_FLAG_REJECTED` / DIE). Then correct pattern+pathspec form.

- [ ] **Step 4: C8 parallel MCP fan-out**

In one parent turn, 4 parallel FileSystem reads (alpha, beta, gamma, needle). PASS if all return without serial drip across turns.

- [ ] **Step 5: C9–C12**

- C9: Quote current `reference-windows-mcp.md` FAIL-FAST #2 and guard `ff` string; PASS only after text says MCP-down → mount then LE (not “never retry Cursor Read”).
- C10: `GetDynamicTools` / tool list shows `user-windows-mcp`; document that mcp.json key `windows-mcp` still counts as ready.
- C11: invoke bad CLI forms; capture exact DIE; decide soft-trim trailing space vs skill warning only.
- C12: LE with absolute `/home/.../mounts/...` path; expect DIE/reject; skill Paths section must forbid it.

- [ ] **Step 6: Gate**

Footgun matrix C5–C12 complete; prioritize P0 text fixes before UX polish.

---

### Task 4: Fix confusion sources (skill / rule / hooks / comments)

**Hotspot single-writer files (serialize):**
1. `scripts/server/skills/laptop-exec/SKILL.md`
2. `scripts/server/cursor-rules/laptop-exec.mdc`
3. `scripts/server/cursor-hooks/laptop-exec-guard.sh`
4. `scripts/server/cursor-hooks/laptop-exec-session.sh`
5. Mirror deploy to live `~/.cursor/...` via existing deploy path (`laptop-exec-setup` / `sudo claude-server install` section for laptop-exec) — do not hand-edit only live copies.

**Files (P0 first — adjust from C* evidence):**
- Modify: `scripts/server/skills/laptop-exec/reference-windows-mcp.md` FAIL-FAST + priority — mount-then-LE; Write=mount-first
- Modify: `laptop-exec-session.sh` + `laptop-exec-guard.sh` `_remote_path_for` to accept `rpath|REMOTE_PATH|remote_path` (parity with `laptop-exec.sh`)
- Modify: guard `ff` + Write NEXT — mount Read/Write fallback; never prefer MCP write over mount in NEXT
- Modify: guard comment ~L144–146 to match ALLOW
- Delete or replace orphan project `.cursor/hooks/laptop-exec-{session,guard}.sh` with DEPRECATED stub pointing to user hooks
- Modify: `parallel-phased-execution/SKILL.md` + `evidence-gated-stages/.../multi-agent.md` paste blocks → skill PRIORITY block
- Modify: `laptop-exec.sh` status `recommend:` hybrid line
- Modify: skill Paths — Desktop-relative warning + `user-windows-mcp` + FileSystem `mode=` schema note
- Optional CLI: trim trailing space on subcommand; friendlier reject for `/mounts/` paths in LE
- Create: `agent-routing-lab/results/FIXES.md` mapping challenge → file:change

**Anti-scope:** Do not redesign hybrid table unless evidence proves table wrong. Do not reintroduce mount denies. Do not “fix” MUX_RECREATE in this lab (separate tunnel ops).

- [ ] **Step 1: From FAIL list, write FIXES.md** with one row per fix (file, before/after intent, challenge id)

- [ ] **Step 2: Apply disjoint comment/docs fixes in parallel waves; serialize shared hook file**

Wave example:
- Worker A owns: SKILL.md Paths + examples
- Worker B owns: laptop-exec.mdc note on abs Windows + `-p`
- Worker C owns: guard.sh stale comments only (same file → alone)

- [ ] **Step 3: Deploy / sync user copies**

```bash
# Prefer project deploy entrypoint already used for laptop-exec
sudo claude-server install
# or narrower: sudo bash scripts/server/commands/deploy-laptop-exec.sh
```

Then confirm live skill/rule/hook snippets match repo for the fixed lines.

- [ ] **Step 4: Re-run failed challenges only**

Update `results/C#.md` with RECHECK PASS.

- [ ] **Step 5: Gate**

No stale “mount Read denied” / “Grep=LE only when MCP ready” left in skill, rule, session, guard (repo + live). `bash -n` on changed shell hooks.

---

### Task 5: Memory + operator handoff (no delete yet)

**Files:**
- Create: `agent-routing-lab/RESULTS-SUMMARY.md`
- Memory MCP entities (not files)

- [ ] **Step 1: Write RESULTS-SUMMARY.md** — table of C1–C12 final status + fixes landed

- [ ] **Step 2: Memory MCP** — entity `agent-routing-lab` type `convention` with observations: path triple for `temp`, Grep=Select-String, Write=mount-first, always `-p`, abs Windows for MCP, `user-windows-mcp` namespace = ready, MCP-down → mount then LE

- [ ] **Step 3: Offer cleanup** — do **not** delete until user says so. Cleanup command when approved:

```bash
# mount-preferred delete of lab only
rm -rf /home/smart/mounts/temp/agent-routing-lab
# or MCP FileSystem delete recursive D:\temp\agent-routing-lab
```

- [ ] **Step 4: Execution choice reminder**

Plan complete. Prefer Subagent-Driven for Task 2–4 waves; keep coordinator for gates.

---

## Review checklist (author)

1. Spec coverage: lab scaffold, happy path, footguns, fixes, memory, cleanup-gated — yes.
2. Placeholder scan: none intentional.
3. Consistency: project id always `temp`; Windows root always `D:\temp\...`.
