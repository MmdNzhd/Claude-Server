# Release Lock

## Model

| Stream | Allowed |
|--------|---------|
| Fix stages 0..N | Repo edits + tests + local artifact sync for verification |
| Release stage D | Deploy/publish/install/ship **only after unlock** |

## Unlock requirements (all)

1. Fix stages packs candidate_complete (or explicit user waiver).
2. **New** user message in the unlocking turn with clear intent:
   - Examples: `deploy کن`, `publish کن`, `ship to production`, `deploy-client-bundle`
3. Quote that message verbatim in release pack VERIFY.
4. Site-specific freezes in the project plan still apply (unlock Smart ≠ unlock frozen site B).

## Non-unlock language (examples)

- execute the plan / شروع کن / تمام / سبز شد / done / LGTM / به نظر اوکیه
- Product DONE / closeout YES (admission ≠ release)

## Pack rules

- Non-release: `deploy_ran=no`; any release cmd ⇒ INVALID + stop
- Release: `deploy_ran=yes` + command list + post-release RUNTIME_GATE

## After unlock

1. Run only planned release commands.
2. Capture post-release identities (artifact/live/installed).
3. RUNTIME_GATE must re-clear guns on the **shipped** path.
4. If ship fails mid-way → blocked; do not claim Product DONE from partial publish.

## Rollback note

If unlock ship regresses: treat as R6 ([recovery](recovery.md)); new stage;
do not silently re-lock without documenting the failed deploy in a pack.

## Helpful publish

Never "helpfully" copy to production share / store as a side effect of fix stages
unless the plan's ARTIFACT_SYNC for that stage explicitly requires a **local**
sync for truth testing (still not production ship).
