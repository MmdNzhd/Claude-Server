# Recovery Playbooks

Use when work is mid-failure. Recovery stays **blocked** until a new/addendum
pack re-enters the IRON LAW loop. Closeout stays read-only.

## R1 — Destructive wipe (checkout/reset mid-stage)

1. Stop all edits; freeze parallel agents.
2. Inventory packs still on disk (`STAGE-*.md`).
3. Restore sources of truth in order:
   - IMPLEMENT notes in packs
   - Artifact root that still matches claimed SHA (Desktop/publish)
   - `git reflog` / stash **only if** safe and user-ok
4. Re-run RED → GREEN for affected stages.
5. Write addendum section in pack or `STAGE-<id>-RECOVERY.md` noting wipe.
6. Do not claim candidate_complete until validator VALID again.

## R2 — False DONE / overstep

Symptoms: chat said finished; scorecard missing/red; guns still live.

1. Emit `OVERSTEP_DETECTED` — Product DONE revoked.
2. Run closeout wave; fill scorecard with real verdicts.
3. Open execute stages only for red layers.
4. Never rewrite old packs to invent `signature_absent=yes`.

## R3 — Partial artifact sync

1. List full `sync_set` from IMPLEMENT.
2. Diff SHA12 every file/root vs repo.
3. Copy missing siblings; re-hash.
4. If user-launched process holds old bits → `pending_reconnect` + relaunch protocol.
5. ARTIFACT_SYNC may not flip to yes until entire set matches.

## R4 — `pending_reconnect` / stale live session

1. Document last live version/session label.
2. Give user exact relaunch path (artifact root + command).
3. After relaunch: rescan guns → update RUNTIME_GATE / LIVE_GATE.
4. Product DONE forbidden until `LIVE_GATE=cleared`.

## R5 — Installed lag under release lock

Server PATH binary lags repo while Desktop sync is OK.

1. Report `INSTALLED_DRIFT` as observation.
2. Do not fail ARTIFACT_SYNC solely for installed lag if sync_set roots OK.
3. Clear installed drift only in release stage after unlock + install proof.

## R6 — Class-A appears after candidate_complete

1. Suite or live regresses → Product DONE impossible; revoke soft claims.
2. New stage or reopen stage id with addendum pack.
3. Hypothesis ledger: reopen or add Hn.

## R7 — Validator VALID but closeout FAIL

Expected: structural ≠ admission. Prefer closeout. Fix semantic gaps
(GREEN-without-RED, fake RUNTIME_GATE proof, partial sync) in execute.
