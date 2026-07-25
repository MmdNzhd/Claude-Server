# Session Handoff

Paste this block (filled) when stopping mid-plan so the next session does not
re-derive state or re-declare false DONE.

```text
EVIDENCE_GATED_HANDOFF
feature: <name>
mode_last: author|execute|closeout
plan_path: <path>
evidence_dir: docs/<feature>-evidence/
packs_VALID: <ids>
packs_INVALID_or_missing: <ids>
candidate_complete_stages: <ids>
product_DONE: NO|YES (scorecard path if YES)
release: LOCKED|UNLOCKED quote=<…|none>
identities: repo=… artifact=… live=…
guns_still_live: <list or none>
pending_reconnect: yes|no relaunch=<path/cmd>
class_A_open: <list>
class_B_debt: <list>
hypotheses_accepted: H# …
next_stage: <id + one sentence>
forbidden: no deploy; no destructive checkout; no Product DONE without closeout
```

## Rules

1. Next session starts in the mode implied by `next_stage`, not by re-authoring
   unless plan is wrong.
2. Re-run `validate-pack.py --dir` before trusting `packs_VALID`.
3. Rebase identities if >1 day stale or version labels changed.
4. If scorecard says YES but guns live → treat as R2 false DONE ([recovery](recovery.md)).
