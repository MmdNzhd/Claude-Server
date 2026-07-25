# Closeout Scorecard — <feature> — <YYYY-MM-DD>

## Verdicts
| Layer | Verdict | Notes (grade=supported\|case-study\|unsupported) |
|-------|---------|--------------------------------------------------|
| Evidence drift | EVIDENCE_DRIFT_OK / FAIL | |
| Suite | SUITE_OK / FAIL | class A=`n` B=`n` C=`n` |
| Live | LIVE_GATE=cleared / pending_reconnect / still_live | last session/ver= |
| Artifact | ARTIFACT_SYNC_OK / DRIFT | |

## φ admission checklist (all must hold for YES)
- [ ] Common ground / success criteria still match
- [ ] Packs on disk for required stage ids; structural VALID
- [ ] Suite + marker checks ran **this** closeout turn
- [ ] RUNTIME/LIVE guns rescanned outside pack prose
- [ ] Owner named for any pending_reconnect / release
- [ ] Identities rebased (not stale plan labels)
- [ ] Class A = 0; blockers listed or none
- [ ] No active recovery / wipe / mid-sync
- [ ] Release LOCKED or unlock quote in Stage D pack
- [ ] No veto / freeze conflict

## Product DONE?
`YES` only if all green and release policy satisfied. Else `NO`.

**This filled file is the canonical completion signal.** Chat/todos must derive from it.

## Class A gaps
- …

## Class B debt
- …

## Smoking guns remaining
- …

## Artifact drift paths
- …

## Installed observe (optional)
- INSTALLED_DRIFT: …

## Next actions
1. …
