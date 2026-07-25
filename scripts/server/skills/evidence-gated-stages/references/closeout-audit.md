# Closeout Audit

Use after stages claim candidate_complete, or on user "hard/deep" request.

This mode is the **read-only admission verifier** ([propose-admit](propose-admit.md)).
It may not patch code/logs/packs to force a green verdict. Repair → execute → re-admit.

## Four mandatory verdicts

### 1) Evidence drift — `EVIDENCE_DRIFT_OK|FAIL`
For each pack: GREEN markers exist in claimed files; named tests still pass; `deploy_ran` sane.

### 2) Suite — `SUITE_OK|FAIL`
Run project suite entry. Classify each failure A/B/C.  
`SUITE_OK` only if **class A count = 0**. List B separately.

### 3) Live — `LIVE_GATE=cleared|pending_reconnect|still_live`
Rescan gun list on current logs/metrics. Record last session/version label.

### 4) Artifact — `ARTIFACT_SYNC_OK|DRIFT`
SHA/version compare sync_set roots vs repo.

## Product DONE predicate

```text
EVIDENCE_DRIFT_OK
AND SUITE_OK
AND LIVE_GATE=cleared
AND ARTIFACT_SYNC_OK
AND (release LOCKED or release pack valid with quote)
```

The filled scorecard on disk is the **canonical completion signal**. Chat/todos/progress
lines must derive from it — never the reverse.

Grade each verdict note: **supported** (checkable this turn) / **case-study**
(bounded subset) / **unsupported** (no scan — do not claim). Do not treat
`validate-pack.py VALID` as admission.

## Procedure

1. Inventory packs (`STAGE-*.md`).
2. Validate each: `validate-pack.py --dir …` (structural advisory only).
3. Marker grep vs **code** (not pack prose alone) from IMPLEMENT/GREEN claims.
4. Suite run → classify A/B/C.
5. Live gun scan on current logs/metrics (outside packs).
6. Artifact SHA matrix vs sync_set roots.
7. Fill scorecard on disk (`CLOSEOUT.md` or copy of `assets/CLOSEOUT-SCORECARD.md`).
8. If any red: `blocked` + next actions; never soft-success. Product DONE only if AND holds.

## Multi-agent

See [multi-agent.md](multi-agent.md). Merge without OR-logic on DONE.

## Example

Filled shape: [assets/EXAMPLE-CLOSEOUT-FILLED.md](../assets/EXAMPLE-CLOSEOUT-FILLED.md)

Blocked? See [recovery](recovery.md). Mid-session stop? [session-handoff](session-handoff.md).
