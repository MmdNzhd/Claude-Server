# Execute Checklist (mode=execute)

## Before stage N
- [ ] Pack N-1 exists and `validate-pack.py` → VALID (if N>0)
- [ ] Working tree understood; no destructive clean
- [ ] Sync_set roots known if stage touches client bits

## Loop
- [ ] VERIFY with fresh fingerprint (not yesterday's paraphrase)
- [ ] RESEARCH ≥2 citations logged in pack
- [ ] RED fails for the right reason
- [ ] IMPLEMENT only stage files; `drive_by=none`
- [ ] GREEN same commands
- [ ] RUNTIME_GATE MUST be `signature_absent=yes`+proof OR `pending_reconnect` OR `N/A reason=…` (P0: `N/A` only if plan waives); empty/template = ABORT
- [ ] ARTIFACT_SYNC full set or explicit n/a
- [ ] Pack written; validator VALID
- [ ] Progress line emitted as **candidate_complete** (not product DONE)

## After all fix stages
- [ ] `STAGES_CANDIDATE_COMPLETE deploy=LOCKED`
- [ ] Do **not** say product finished; point to closeout for admission
- [ ] Optional closeout if user asked hard audit
- [ ] No publish/deploy without quote

## If blocked
- [ ] Ask; do not skip gate
- [ ] Do not mark candidate_complete / DONE to unblock N+1 without VALID pack

## Recovery
If wipe / false DONE / partial sync: follow [recovery](recovery.md) before next candidate_complete.
Mid-stop: [session-handoff](session-handoff.md).
