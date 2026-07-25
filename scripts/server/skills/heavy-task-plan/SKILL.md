---
name: heavy-task-plan
description: >-
  Multi-stage planning flow for heavy or ambiguous tasks: discovery, design,
  confirmation, staged execution, wrap-up. Maximizes wall-clock speed via
  parallel subagents while requiring accuracy gates (verified change, not
  agent count). Use ONLY when the user explicitly asks to plan first —
  e.g. says "plan this", "make a plan before doing it", "برنامه بریز", "پلن
  کن", "design this first", or names this skill directly. Do not use for
  routine requests where the user didn't ask for a plan.
---

# Heavy Task Plan

Follow these stages in order for the current task. Do not skip stages.

**Dual objective everywhere:** maximum **speed** (true parallel waves) and
maximum **accuracy** (evidence gates). Metric = verified mergeable change —
not number of agents or tokens burned.

## Maximize Parallelism (applies to every stage)

Optimize for **wall-clock speed via concurrency**, not for doing everything
in one linear agent. Default to more, narrower agents running at once over
one agent grinding through steps serially — **when write-sets and
dependencies allow**.

- At each stage, first ask: "which parts of this are independent (no shared
  write paths, no ordering dependency)?" Split along those lines.
- Dispatch all independent subagents (`Task` tool) **in the same response**
  — multiple tool calls in one batch run in parallel; one call per response
  runs sequentially and wastes time. See
  `dispatching-parallel-agents` and **required**
  `parallel-phased-execution` for execution waves.
- Scale the number of agents to task size, don't just max out blindly:
  small/contained work → 1 agent; a handful of clearly separable areas →
  3-5 agents in parallel (Anthropic Research sweet spot); very large
  fan-out → more only if write-disjoint and review bandwidth exists.
- Only go sequential when there's a real dependency (step B needs step A's
  output) or shared-file **write** conflicts would occur.
- Model for every dispatched subagent: use `inherit` (auto) — do not pin a
  specific model unless the user explicitly asked for one.
- After parallel agents return: integrate reports, enforce owns/write-set
  rules, run the stage/step **verifier gate**, then continue — don't treat
  Worker DONE as proof.

## Stage 1 — Discovery

- If the codebase/context has 2+ independent areas to explore (e.g.
  different subsystems, unrelated files, frontend + backend), dispatch one
  `explore`/`generalPurpose` subagent per area **in parallel**, not one
  subagent walking through all of them in sequence.
- Prefer read-only discovery waves (zero write conflicts).
- List concrete unknowns from their combined results. Ask the user only for
  genuinely ambiguous decisions — don't ask about things you can find
  yourself.

## Stage 2 — Design

- Read `~/.cursor/skills/writing-plans/SKILL.md` and produce a written plan
  in that format: goal, approach, affected files, steps, risks.
- Call out trade-offs explicitly when more than one valid approach exists.
- **Wave-ready plans:** each Task step should name independent **slices**
  and **write-path sets** where possible; call out hotspot single-writer
  files; structure TDD as RED step(s) then GREEN step(s).

## Stage 3 — Confirm

- Show the user a short plan summary (not the full document) and get
  explicit go-ahead before touching code, unless they already said "just
  implement it" when opting into planning.

## Stage 4 — Staged Execution

**REQUIRED — read and follow in full:**
`~/.cursor/skills/parallel-phased-execution/SKILL.md`

That skill is the SoT for: phase=step, wave tables, same-file serialize,
TDD RED→GREEN, Coordinator→Workers→Verifier, caps, failure modes, mounts.

Controller summary (incomplete without the other skill):

- Phase = plan **step**; wave = parallel ready + write-disjoint Workers.
- Dependent / same-write slices wait for the next wave.
- Gate must PASS before the next step.
- Do not grind Step1→Step2→Step3 in one parent when slices can wave.
- High-stakes: `evidence-gated-stages`.
- **Subagent abort:** a new parent chat message aborts running Task Workers
  (`User aborted/interrupted manually`). Do not prompt the user mid-wave;
  if the user is actively chatting, implement in the parent instead of Task.
  Details: `parallel-phased-execution` → "Why Task/subagents die mid-wave".

## Stage 5 — Wrap-up

- Summarize what changed and how it was **verified** (commands, review).
- Flag follow-ups, known gaps, and any Minor findings deferred from wave
  reviews — do not silently omit.
