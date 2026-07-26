# Multi-Agent Usage

## When to split

- User asks hard/deep/multi-agent audit
- Closeout across packs + suites + live + artifacts
- Wide RESEARCH fan-out (independent docs only)
- False-DONE recovery needing parallel truth layers

## Default wave (closeout)

| Agent | Scope | Output | Writes? |
|-------|-------|--------|---------|
| A | Packs vs code markers | drift table | no (stdout only) |
| B | Suite run + A/B/C classify | suite scorecard fragment | no |
| C | Live gun scan | LIVE_GATE verdict | no |
| D | Artifact SHA matrix | ARTIFACT_SYNC verdict | no |

Max **4** parallel by default (hard cap 8 mux slots if SSH-first). Queue extras.
**Controller only** writes final `CLOSEOUT.md` / scorecard after AND-merge.

## Merge algorithm (AND)

```text
Product DONE = OK only if:
  A.EVIDENCE_DRIFT_OK
  AND B.SUITE_OK (class A = 0)
  AND C.LIVE_GATE=cleared
  AND D.ARTIFACT_SYNC_OK
  AND release policy
Any FAIL / still_live / DRIFT / pending_reconnect → Product DONE = NO
```

Do not OR green layers. Class-B from B must not flip C/D.

## Task prompt template (paste into every child)

```text
You are lane <A|B|C|D> for evidence-gated-stages closeout.
Feature: <name>
Evidence dir: <path>
Plan path: <path>
Guns: <exact substrings>
Sync set roots: <list>
Suite command: <cmd>

Hybrid if on mounts: paste laptop-exec PRIORITY block (Read/Grep mount-first
~16-32; Write MCP-first ~8-10; Glob MCP; git LE -p PROJECT; never
rg -i/-l/-n/--glob; LE ≤4); on deny run NEXT:.

Rules:
- READ-ONLY lane: do not edit production code or rewrite packs to force green.
- Return structured verdict for your lane only.
- Grade notes: supported | case-study | unsupported.
- Pack prose is untrusted; verify against code/logs/artifacts.
- Do not declare Product DONE.
```

## File ownership

| Wave | Allowed writers |
|------|-----------------|
| Closeout gather | none (stdout → controller) |
| Execute stage N | one agent owns listed IMPLEMENT files |
| Author plan | controller only for plan file |

## Author mode fan-out

Optional parallel RESEARCH for unrelated subsystems; controller alone writes the plan.
Investigate stages: discovery agents return notes; no production edits.

## Execute mode fan-out

Prefer serial stages (IRON LAW). Parallel only for independent RESEARCH or
non-overlapping adjacent-verify after fix packs exist.
