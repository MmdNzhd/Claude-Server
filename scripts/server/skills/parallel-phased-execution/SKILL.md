---
name: parallel-phased-execution
description: >-
  Maximum-speed AND maximum-accuracy plan execution via per-step parallel
  agent waves: dependency-free slices only, never same-file parallel writes,
  TDD RED then GREEN, Coordinator→Workers→Verifier gates. Use when executing
  a written plan, heavy-task-plan Stage 4, subagent-driven plan runs, or the
  user asks for multi-agent / phased / wave execution ("maximum speed",
  "maximum accuracy", "wave execution").
---

# Parallel Phased Execution

**Dual objective (both required):**
1. **Speed** — maximize wall-clock via true parallel waves (not fake
   sequential Task calls).
2. **Accuracy** — every wave ends with evidence (tests/diff/review), not
   agent self-praise. Metric = *verified, mergeable change*, not tokens
   generated or agents spawned.

Controller = orchestrator only. Workers = narrow slices. Verifier =
spec/quality gate. Do **not** grind a whole plan Task alone in the parent
when waves can run.

---

## Mental model

```
Plan Task N
  Step 1 wave:  WorkerA ‖ WorkerB ‖ WorkerC     ← ready + disjoint writes
       ↓ all DONE
  Integrate + Verifier gate (must PASS)
  Step 2 wave:  next ready set
       ↓
  …
  Task reviewer (spec + quality) on Task commit range
  Next plan Task
```

A **phase** = one **step** inside a plan Task (not the whole Task).

One step may need **multiple waves** if some slices were deferred
(dependency or same-file write collision).

---

## Roles (Coordinator–Implementor–Verifier)

| Role | Who | Does | Does NOT |
|------|-----|------|----------|
| **Coordinator** | Parent agent | Build wave table, dispatch batch, integrate reports, run/queue verifier, decide retry/replan | Implement the whole Task alone; skip gates |
| **Worker** | `Task` subagent | Own slice only; write only `owns` paths; report to file | Edit outside owns; resolve merge conflicts; invent scope |
| **Verifier** | Fresh `Task` reviewer (or scripted checks) | Spec compliance + quality vs brief/diff; fail loud | Trust worker report; re-run entire suite unless specific doubt |

Inspired by CIV / verifier-driven parallel agents: **prose rules fail at scale**;
gates + write ownership keep speed from destroying accuracy.

---

## Hard rules — SPEED

1. **One batch per wave.** All ready Workers for this wave in **one** parent
   response (multiple `Task` calls together). One Task per turn = serial =
   slow.
2. **Dual parallelization.** (a) N Workers in parallel; (b) each Worker may
   use multiple tools in parallel inside its own turn. Both matter
   (Anthropic Research: up to ~90% wall-clock cut on breadth work).
3. **Cap 3–5 Workers per wave** (sweet spot). Hard cap ~8 on
   laptop-exec/mux projects. Past ~5, merge/review bandwidth usually kills
   the speedup — fewer verified agents beat more conflict generators.
4. **Scale effort to complexity.** Trivial step → 1 Worker. Clear 2–4
   disjoint slices → that many. Never spawn 10+ for a small step.
5. **Fresh context per Worker.** Workers do **not** inherit parent chat
   history. Coordinator pastes only: brief, owns/reads, contracts, done
   criteria, report path, SSH-first block if mounts.
6. **Compress upward.** Workers return short structured reports + artifact
   refs (paths, SHAs, test commands). Not full traces (avoids context
   pollution / telephone game).
7. **No “continue?” between waves** unless BLOCKED or a real user decision.
   Continuous execution until Task done or blocked.

---

## Hard rules — ACCURACY

1. **Independence gate.** Dispatch only slices with **no open dependency**
   on another unfinished slice. If B needs A → B waits next wave.
2. **Same-file writes → serialize.** If write-path sets intersect → not
   parallel. One owner this wave; others deferred. Read-only overlap OK.
   Hotspots (`package.json`, lockfiles, giant `connect.ps1`, shared conf)
   → single writer per wave always.
3. **Shared contract before parallel GREEN.** Before implement waves that
   touch a shared boundary, Coordinator records invariants/API/naming in a
   short contract (in brief or `/tmp/.../contracts.md`). Workers must not
   invent conflicting shapes.
4. **TDD when plan is tests-first.**
   - RED wave(s): Workers write/run **failing** tests only; gate = tests
     fail for the right reason.
   - GREEN wave(s): implement; gate = those tests pass + no unrelated
     breakage you can cheaply check.
5. **Verifier gate between steps.** Do not open Step N+1 until Step N’s
   evidence passes (tests RED/GREEN as required, or review PASS). Failed
   gate → fix wave (same owns) or replan — never “ship and hope”.
6. **Do not trust Worker self-grades.** Verifier reads brief + diff/report
   evidence. Design rationales in reports are claims, not proof.
7. **No agent auto-resolves merge conflicts** across Workers. Coordinator
   or human resolves; Workers stay in owns.
8. **End-state over path.** Judge whether the step’s acceptance criteria
   hold, not whether Workers followed an imagined unique path.
9. **Structural vs semantic.** Scripted checks catch structure (wrong
   paths, missing files, test exit codes). Semantic correctness needs
   Verifier/human. Both layers when stakes are high
   (`evidence-gated-stages`).

---

## Wave planner (before every wave)

Build this table. Dispatch **only** rows that are Ready **and** pairwise
write-disjoint.

```text
| Slice | Owns (write paths) | Reads | Needs | Ready? | Priority |
```

Algorithm:
1. List all unfinished slices for the current step.
2. Mark Ready = Needs all satisfied.
3. Greedy by Priority: add slice if write-set ∩ selected = ∅.
4. Defer the rest to the next wave of this step (or next step if
   dependency is cross-step).
5. If Ready set empty but unfinished remain → dependency bug or
   same-file deadlock → Coordinator serializes or escalates NEEDS_CONTEXT.

---

## Per-Task loop

1. Record `BASE_SHA` before Task work.
2. For each plan Step:
   a. While unfinished slices in step:
      - Plan wave table → dispatch Workers (one batch) → wait.
      - Integrate reports; spot write-path violations (any Worker wrote
        outside owns → reject that slice, restore/fix).
      - Run step gate (tests / checklist).
      - On FAIL: one focused fix wave or BLOCKED — do not proceed.
   b. Step PASS → next Step.
3. Task reviewer on `BASE_SHA..HEAD` (spec + quality).
4. Record minor findings for final branch review; Critical/Important →
   fix wave before next Task.
5. Next plan Task.

**Forbidden default:** one implementer doing Step1→Step2→Step3 alone when
the step has independent parallelizable slices.

---

## Worker prompt minimum (every Worker)

```text
SLICE: <one sentence>
OWNS (write only these paths): …
READS (read-only OK): …
CONTRACTS: <path or bullets — do not contradict>
DONE WHEN: <measurable>
REPORT FILE: /tmp/.../waveW-sliceX.md
IF NEED FILE OUTSIDE OWNS: stop, status NEEDS_CONTEXT — do not edit.
NO MERGE CONFLICT RESOLUTION. NO SCOPE CREEP.
[SSH-first block if ~/mounts/]
```

Report file must include: Status (DONE|DONE_WITH_CONCERNS|BLOCKED|NEEDS_CONTEXT),
files changed, commands run + outcomes, concerns. Final chat ≤15 lines +
report path.

---

## Verifier prompt minimum

- Brief + global constraints + Worker claims + diff (or review-package).
- Spec compliance first, then quality.
- Do not mutate repo.
- Do not blindly re-run full suites Worker already evidenced — only focused
  checks when a named doubt appears.
- Verdict: PASS | FAIL with Critical/Important/Minor.

---

## Failure modes (detect → prevent)

| Failure | Prevention |
|---------|------------|
| Silent overwrite same file | Write-set disjointness; serialize hotspots |
| Locally correct, globally broken | Shared contracts; integration verifier |
| Context pollution | Fresh Worker context; compress reports |
| Over-spawn (50 agents) | Cap 3–5; scale to complexity |
| Duplicate searches/edits | Explicit slice boundaries in prompts |
| Proceed on failed tests | Verifier/test gate blocks next step |
| Game of telephone | Artifacts on disk + short refs upward |
| Fake parallelism (serial Tasks) | One-response multi-Task batch |
| Merge debt > speedup | Fewer agents; measure verified change |

Anthropic note: domains with **heavy shared context / many dependencies**
(typical tightly-coupled coding) fit multi-agent **only** when sliced into
truly independent write-sets. If everything touches one file → **one**
Worker. Parallelism is not optional theatre.

---

## When NOT to parallelize

- Single-file bottleneck for the step.
- Live debug needing one shared mutable state.
- User asked for single-agent.
- Slices cannot be made write-disjoint without a contract you refuse to write.
- Discovery shows only one real unknown.

Then: one capable Worker + Verifier still required for accuracy.

---

## Mounts / laptop-exec

Every Worker/Verifier Task prompt on `~/mounts/` projects must paste the
PRIORITY block from `laptop-exec` skill (Read/Grep mount-first ~16–32;
Write MCP-first ~8–10; Glob MCP; git LE only; no `rg -i/--glob`; LE ≤4,
hard 8). Coordinator may fan out mount/MCP work; prefer ≤4 parallel Tasks
that use laptop-exec.

---

## Relation to other skills

| Skill | Relationship |
|-------|----------------|
| `heavy-task-plan` Stage 4 | **Must** follow this skill end-to-end |
| `subagent-driven-development` | Keep task/final review; replace “one implementer per task” with wave Workers per step |
| `dispatching-parallel-agents` | Pattern for one wave; this skill adds phases, gates, TDD, write ownership |
| `writing-plans` | Steps should name slices + write-sets for waves |
| `evidence-gated-stages` | Use for high-stakes gates (stricter than default step gate) |
| `laptop-exec` | Mandatory on mounts |

---

## Why Task/subagents die mid-wave (Cursor reality)

**Fleet note (Remote SSH / this server):** local laptop multi-agent can run
hours; **on the Claude server they die/restart**. User "continue" is usually
**after** death — not the root cause. Do not blame the user first.

### Primary cause on this server (evidence 2026-07-23)

Remote **Extension Host** dies / reconnects → in-flight Task tool IPC is
orphaned → Workers look dead / restart. Smoking gun in
`~/.cursor-server/data/logs/*/remoteagent.log`:

- Hundreds of `RequestStore#acceptReply was called without receiving a matching request`
- `Extension host terminating: received terminate message from renderer`
- `Extension host terminating: renderer disconnected for too long`
- Many `exthostN/` folders in one day + multiple stale `cursor-server` builds

Matches Cursor bugs: EH restart orphans tool calls
([forum 156362](https://forum.cursor.com/t/agent-hangs-silently-when-extension-host-restarts-during-in-flight-tool-call/156362));
Remote-SSH multiplex zombies
([forum 160611](https://forum.cursor.com/t/remote-ssh-repeatedly-disconnected/160611)).

**Background Task is NOT a silver bullet** on Remote SSH — when SSH degrades,
background subagents can silently run on the **local laptop**
([forum 160392](https://forum.cursor.com/t/security-background-subagent-silently-falls-back-to-local-machine-execution-when-ssh-remote-connection-degrades/160392)).

### Secondary causes (also real)

1. Parent chat message can abort Workers (`User aborted/interrupted manually`) —
   but treat as secondary; verify EH/RequestStore first on this fleet.
2. Auto-cancel ~256s mislabeled as user interrupt (forum).
3. Stale `.git/index.lock` after mid-commit abort.

### Mitigations (mandatory for this skill)

- On Remote SSH: prefer **short Workers**, serialize heavy waves, or
  **Coordinator implements directly**; for multi-hour multi-agent prefer
  **laptop-local Cursor** or **Cloud Agents**, not long Task storms on server.
- Prune stale `~/.cursor-server` builds / extra extensionHosts (one active build).
- Avoid crash-looping MCP (accelerates EH death).
- Do not ask the user mid-wave; if they say continue, resume from last commit
  and check `remoteagent.log` for RequestStore / EH terminate.
- Clear stale `index.lock` only if no live `git`.
- Document `aborted_reason=eh_restart|remote_ssh|parent_message|timeout|unknown`.

## Self-check before claiming a wave/Task done

- [ ] Wave was one multi-Task batch (or justified single Worker)
- [ ] Write-sets disjoint (or serialized with reason logged)
- [ ] Dependencies respected (no premature slice)
- [ ] Step gate evidence attached (test output / review PASS)
- [ ] No Worker wrote outside owns
- [ ] Next step not started on FAIL
- [ ] Dual objective held: fast **and** verified
