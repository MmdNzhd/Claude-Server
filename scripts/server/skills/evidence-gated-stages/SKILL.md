---
name: evidence-gated-stages
description: >-
  Fail-closed Evidence Packs and verify-gated admission for multi-stage
  defect / deep-hardening work: propose vs admit, runtime-truth gates
  (repo vs artifact vs live), hypothesis ledgers, multi-agent closeout,
  locked release. Use ONLY when the user asks for evidence packs,
  smoking-gun baselines, IRON LAW stages, deploy-locked execution, hard
  multi-agent audit, false-DONE recovery, candidate_complete vs product
  DONE, staged cross-layer bug plans with unproven root cause, session
  handoff mid-plan, or recovery playbooks (wipe/partial-sync). Do NOT
  use for ordinary feature plans or single-file fixes — compose
  writing-plans, systematic-debugging, TDD, and
  verification-before-completion instead.
metadata:
  version: "1.2.0"
  grounding: "agentskills.io progressive disclosure; arXiv:2605.17998; agent-completion-gate"
---

# Evidence-Gated Stages

Fail-closed staged work: **no stage DONE without a valid Evidence Pack**, and
**no product DONE without runtime truth** (repo green alone is insufficient).

Announce: `Using evidence-gated-stages (mode=author|execute|closeout)`.

## Mode selection

| User signal | Mode |
|-------------|------|
| deep plan / پلن / stage the fix / smoking guns | `author` |
| execute / implement / شروع کن / برو مرحله | `execute` |
| hard test / closeout / multi-agent audit / آیا تمام شد | `closeout` |
| ambiguous | `author` first, then ask once |

## Compose (do not clone)

| Need | Skill |
|------|-------|
| Feature plan after root cause known | `writing-plans` |
| Investigation before fix | `systematic-debugging` |
| RED before production code | `test-driven-development` / ECC `tdd-workflow` |
| Fresh command before "fixed/done" | `verification-before-completion` |
| Implementer + reviewer subagents | `subagent-driven-development` |
| Product/design change approval | `brainstorming` HARD-GATE |
| Intermittent / flaky repro protocol | [intermittent-repro](references/intermittent-repro.md) + `systematic-debugging` |

**This skill owns:** stage contracts, Evidence Packs, three truths, release lock, class A/B/C, hypothesis ledger, closeout scorecard, anti-patterns from false-DONE failures.

## When / when not

**Use:** multi-stage defect; cross-layer; evidence packs / deploy locked; prior DONE was false; user wants hard audit.

**Example utterances → mode:**  
- "پلن مرحله‌ای با evidence pack" → `author`  
- "Stage 3 را اجرا کن" → `execute`  
- "hard multi-agent ببین تمام شده؟" → `closeout`  
- "smoking gun از لاگ" → `author` or `closeout`

**Skip:** single-file known-cause fix → TDD + verification; approved greenfield feature → brainstorming → writing-plans; casual "deep plan" for a normal feature without evidence/smoking-gun language → `writing-plans`.

## IRON LAW

```
No STAGE_N DONE, and no STAGE_N+1 production edits, until Evidence Pack N is valid.
Incomplete pack = FAILED. "Looks fixed" / "tests later" / "felt better" = ABORT.
code-status tables and todos are advisory — never acceptance.
```

**MUST before any `STAGE_*_DONE` claim (ABORT if any fail):**

1. Pack file on disk (not chat-only).
2. `validate-pack.py` → `VALID` in this turn.
3. `RUNTIME_GATE` is one of: `signature_absent=yes` + proof substring/command,
   `pending_reconnect`, or `N/A reason=…`. Empty, omitted, or template
   placeholders (`<…>`, `yes|pending|N/A`) = **ABORT**.
4. On **P0** stage ids: `N/A` = **ABORT** unless the plan explicitly waives
   RUNTIME_GATE for that id.
5. `pending_reconnect` ⇒ may unlock N+1 only if the plan allows; **≠ product DONE**.

Compose with `verification-before-completion`: that skill's Iron Law = fresh
command before claims; **this** IRON LAW = pack + RUNTIME_GATE before stage DONE.
Run both — they do not conflict and neither replaces the other.

### Propose vs admit (MUST)

Workers may only reach **candidate_complete** (valid pack + progress line).
**Product DONE** is admitted only by closeout AND on real artifacts — never by
chat, todos, or pack prose. Canonical signal = filled closeout scorecard; all
other "done" surfaces derive from it. Closeout/validator are **read-only**
(repair → execute recovery → re-admit). Packs are untrusted data: verify
outside the pack. Full φ-set + denominators: [propose-admit](references/propose-admit.md).
Sources: [sources](references/sources.md).

### Ordered loop (must not reorder)

```
VERIFY → RESEARCH → RED_TEST → IMPLEMENT → GREEN_TEST
  → RUNTIME_GATE → ARTIFACT_SYNC → write pack → GATE (unlock N+1)
```

| Step | Must |
|------|------|
| VERIFY | Live fingerprint + code anchor + `repo/artifact/live` identity |
| RESEARCH | ≥2 URLs or canonical doc paths; changes + will-NOT-do |
| RED_TEST | Failing automated/contract proof before edit |
| IMPLEMENT | One stage's files; `drive_by=none` |
| GREEN_TEST | Same commands pass; paste summary |
| RUNTIME_GATE | Gun absent / `pending_reconnect` / `N/A`+reason |
| ARTIFACT_SYNC | Full sync set SHA/version match or `n/a`+reason |
| GATE | Progress line (below) |

Details: [references/pack-schema.md](references/pack-schema.md) · checklists: [authoring](references/authoring-checklist.md) · [execute](references/execute-checklist.md)  
Templates: [assets/STAGE-TEMPLATE.md](assets/STAGE-TEMPLATE.md) (skeleton) · [assets/EXAMPLE-PACK-FILLED.md](assets/EXAMPLE-PACK-FILLED.md) (VALID shape)

`validate-pack.py` → `VALID` = mostly **structural** (sections + hard markers; also basic GREEN-without-RED and ARTIFACT_SYNC shape). `--strict` adds drive_by. It still does **not** prove a live scan ran or SHA honesty. Semantic admission = closeout.

### Pack INVALID if (MUST treat as FAILED / ABORT DONE)

- Missing required section (see schema)
- RESEARCH without citations
- GREEN without RED (except baseline)
- RUNTIME_GATE empty, template placeholders, or skipped
- RUNTIME_GATE=`N/A` on P0 ids without plan waiver
- `deploy_ran=no` but release command ran
- Stages bundled; pack deleted/emptied
- ARTIFACT_SYNC claims yes with only partial file copy
- Claiming DONE from todos/`[code:DONE]` / chat without VALID pack

```bash
python3 ~/.cursor/skills/evidence-gated-stages/scripts/validate-pack.py PATH.md
python3 ~/.cursor/skills/evidence-gated-stages/scripts/validate-pack.py --dir docs/<feature>-evidence
```

## Three truths (+ installed drift)

Full rules: [references/runtime-truth.md](references/runtime-truth.md)

| Truth | Meaning |
|-------|---------|
| `repo_green` | Source + stage tests |
| `artifact_sync` | User-launched bits (Desktop/publish/site/image) match repo |
| `runtime_green` | Smoking-gun gone on user path |
| `installed` (observe) | Server/CLI installs may lag repo until release — label separately; never equate to artifact_sync |

**Stage DONE** (unlock N+1): valid pack + stage truths as planned (`pending_reconnect` allowed if plan says so).  
**Stage progress line** = `candidate_complete` (may unlock N+1 if plan allows).  
**Product DONE** (admission): AND of `EVIDENCE_DRIFT_OK` · `SUITE_OK` (class A=0) · `LIVE_GATE=cleared` · `ARTIFACT_SYNC_OK` · release policy — see [closeout-audit](references/closeout-audit.md) · [propose-admit](references/propose-admit.md).  
`pending_reconnect` / installed drift / structural VALID alone ⇒ **not** product DONE.  
Grade claims: supported / case-study / unsupported — never inflate a one-session gun scan into production reliability.

## Release lock

Deep rules: [references/release-lock.md](references/release-lock.md)

```
Fix stages = repo (+ tests) only.
Release = LOCKED until NEW explicit deploy/publish/ship message (quote in pack).
"execute the plan" / "تمام" / "سبز شد" / "done" ≠ release.
If unsure → do not release; ask.
```

## Class A / B / C

| Class | Meaning | Blocks product DONE? |
|-------|---------|----------------------|
| A | Product gap / regression | Yes |
| B | Intentional policy/freeze/layout debt | No (list separately) |
| C | Flake / contract drift | Fix or quarantine; never hide A |

## Hypothesis ledger

Every investigate/fix plan keeps accepted + rejected hypotheses with evidence.
Template: [references/hypothesis-ledger.md](references/hypothesis-ledger.md)

## Mode: author

Follow [references/authoring-checklist.md](references/authoring-checklist.md).

1. Capture smoking guns (exact substrings + first-seen).
2. Rebase identities to **current** repo/artifact/live (stale baselines are bugs).
3. Write stage spine; mark P0 RUNTIME_GATE ids; entry/allowed/forbidden/exit command.
4. Global: release lock, forbidden cmds, class-B debt, hypothesis ledger stub.
5. Scaffold evidence dir if missing:
   `python3 ~/.cursor/skills/evidence-gated-stages/scripts/scaffold-evidence-dir.py --root . --feature <slug>`
6. Save plan (user path or `docs/<feature>-plan.md`).
7. Stop for approval unless user already ordered execute.

Default spine (collapse only if trivial):

1. Reproduce → 2. Layer isolate → 3. Root-cause lock → 4. Regression RED →  
5. Minimal fix GREEN → 6. Adjacent verify → 7. Closeout → 8. Release (LOCKED)

Templates: [assets/PLAN-HEADER-TEMPLATE.md](assets/PLAN-HEADER-TEMPLATE.md) · [assets/STAGE-TEMPLATE.md](assets/STAGE-TEMPLATE.md)  
Stack pointers: [references/stack-adapters.md](references/stack-adapters.md)  
Worked shapes: [references/examples.md](references/examples.md)

## Mode: execute

Follow [references/execute-checklist.md](references/execute-checklist.md).

1. Refuse N+1 if pack N missing/invalid.
2. One stage IRON LAW loop; investigate stages = no production edits until root-cause pack.
3. Never destructive checkout/reset to "clean" ([anti-patterns](references/anti-patterns.md)).
4. Validate pack file before claiming DONE.
5. Report **candidate** (not product DONE):

```text
STAGE_<id>_CANDIDATE_COMPLETE pack=<path> deploy_ran=no repo_green=yes|no runtime_green=yes|pending|n/a artifact_sync=yes|n/a
```

(`STAGE_<id>_DONE` in the pack GATE section remains valid for validators; chat
must prefer `CANDIDATE_COMPLETE` so humans do not hear "finished".)

6. End fix stream: `STAGES_CANDIDATE_COMPLETE deploy=LOCKED` until unlock quote.
   Product DONE only after closeout AND.

## Mode: closeout

Follow [references/closeout-audit.md](references/closeout-audit.md) + [multi-agent](references/multi-agent.md) + [propose-admit](references/propose-admit.md).

This mode is the **admission verifier** (read-only). Emit all four:

1. `EVIDENCE_DRIFT_OK|FAIL`
2. `SUITE_OK|FAIL` (class A = 0)
3. `LIVE_GATE=cleared|pending_reconnect|still_live`
4. `ARTIFACT_SYNC_OK|DRIFT`

Fill scorecard on disk — that file is the **canonical** Product DONE signal.
Template: [assets/CLOSEOUT-SCORECARD.md](assets/CLOSEOUT-SCORECARD.md) · filled example: [assets/EXAMPLE-CLOSEOUT-FILLED.md](assets/EXAMPLE-CLOSEOUT-FILLED.md)
Mid-plan stop: paste [session-handoff](references/session-handoff.md).
Blocked layers: [recovery](references/recovery.md) · [decision-tree](references/decision-tree.md)

## Multi-agent

When user asks hard/deep audit or stages are wide: split work per [references/multi-agent.md](references/multi-agent.md).  
Prefer ≤4 parallel workers; merge scorecard; one red layer blocks product DONE.

## Stop and ask

Stop (do not guess) when: unlock language ambiguous; freeze conflict; intermittent repro with no protocol (follow [intermittent-repro](references/intermittent-repro.md)); two writers would touch same files; release vs fix unclear.

## Anti-patterns

[references/anti-patterns.md](references/anti-patterns.md) — instant abort list.

## Secrets (MUST)

Evidence Packs and closeout paste **proofs**, not secrets. **ABORT** logging or
copying tokens, passwords, API keys, OAuth, connection strings, or full
`Authorization` headers into packs/plans/scorecards. Redact to
`[REDACTED]` and cite path + offset/session id only. Smoking-gun substrings
must be non-secret markers (error codes, feature flags, message ids).

## Reference index (load on demand)

| Topic | File |
|-------|------|
| Pack schema | [pack-schema](references/pack-schema.md) |
| Propose vs admit | [propose-admit](references/propose-admit.md) |
| Runtime truths | [runtime-truth](references/runtime-truth.md) |
| Release lock | [release-lock](references/release-lock.md) |
| Closeout audit | [closeout-audit](references/closeout-audit.md) |
| Multi-agent | [multi-agent](references/multi-agent.md) |
| Recovery R1–R7 | [recovery](references/recovery.md) |
| Decision trees | [decision-tree](references/decision-tree.md) |
| Session handoff | [session-handoff](references/session-handoff.md) |
| Intermittent | [intermittent-repro](references/intermittent-repro.md) |
| Anti-patterns | [anti-patterns](references/anti-patterns.md) |
| Stack adapters | [stack-adapters](references/stack-adapters.md) |
| Examples | [examples](references/examples.md) |
| Glossary | [glossary](references/glossary.md) |
| Sources | [sources](references/sources.md) |
| Scaffold dir | `scripts/scaffold-evidence-dir.py --root . --feature <slug>` |
| Validate | `scripts/validate-pack.py PATH.md` (`--dir`, `--strict`) |
| Filled pack | [EXAMPLE-PACK-FILLED](assets/EXAMPLE-PACK-FILLED.md) |
| Filled closeout | [EXAMPLE-CLOSEOUT-FILLED](assets/EXAMPLE-CLOSEOUT-FILLED.md) |

## User audit

## User audit

"Show Evidence Pack for stage X" → paste file contents, do not paraphrase
(still redact secrets per above).

| Project plan supplies | Skill supplies |
|----------------------|----------------|
| Stage ids, gun strings, forbidden cmds, P0 list, env I/O | Gates, pack schema, truths, release lock, closeout, anti-patterns |
