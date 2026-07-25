# Decision Trees

## Mode pick

```text
User message
  ├─ plan / stages / smoking guns / evidence packs → author
  ├─ execute stage N / implement / شروع → execute
  ├─ hard audit / تمام شد؟ / closeout → closeout
  ├─ intermittent flake language → intermittent-repro + systematic-debugging
  ├─ ordinary feature, root cause known → writing-plans (skip this skill)
  └─ ambiguous → author stub OR ask once
```

## After GREEN_TEST

```text
Need user-path proof?
  NO + plan waives RUNTIME_GATE → N/A reason=… (forbidden on P0 without waiver)
  YES → can scan live now?
          YES + gun gone → signature_absent=yes + proof
          YES + gun present → NOT candidate; more fix or new hypothesis
          NO (needs relaunch) → pending_reconnect (≠ Product DONE)
```

## Artifact

```text
Stage touches launched bits?
  NO → artifact_sync=n/a reason=repo-only
  YES → full sync_set SHA match?
          YES → artifact_sync=yes
          NO → sync or candidate blocked
```

## Closeout merge (multi-agent)

```text
Any layer FAIL / still_live / DRIFT?
  YES → Product DONE = NO (AND). List next actions.
  NO all four green + release policy → Product DONE = YES on scorecard only
```

## Release

```text
User message contains explicit deploy/publish/ship?
  NO → LOCKED (even if "done"/"تمام")
  YES + site freeze allows → release stage pack deploy_ran=yes
  YES + freeze blocks that site → ask; do not ship frozen target
```
