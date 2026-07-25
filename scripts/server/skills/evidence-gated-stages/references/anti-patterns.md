# Anti-Patterns — instant abort

| Anti-pattern | Failure mode | Required behavior |
|--------------|--------------|-------------------|
| DONE from todos/`[code:DONE]` | False acceptance | DONE ⇔ valid pack + truths |
| Empty/template RUNTIME_GATE | False DONE via section skimming | ABORT; proof, `pending_reconnect`, or waived `N/A` |
| Paste secrets/tokens into pack | Credential leak in docs/git | Redact; path+offset only |
| Partial artifact sync | Stale sibling scripts run | Full sync_set + SHA |
| Destructive `git checkout`/`reset --hard` mid-stage | Wipe uncommitted work | Targeted reapply from packs/artifact |
| Bulk encoding/ASCII strip | Parse break | Surgical edit + parse proof |
| GREEN without RED | Wrong test | Fail first |
| Skip RESEARCH | Wrong fix shape | ≥2 citations |
| Bundle two stage ids | Evidence attribution lost | One stage / change set |
| Vague release unlock | Accidental ship | Quote explicit deploy/publish |
| Soften freeze without ask | Policy undo | Ask; leave frozen |
| Shrink remote log/db | Silent loss | Append/merge only |
| Class-B ⇒ product FAIL | Noise | Split A/B/C |
| Ignore class-A because pack GREEN | False DONE | Closeout re-check markers |
| Live fixed while `pending_reconnect` | Guns remain | Relaunch then rescan |
| Delete/empty pack | Audit gap | Never |
| Clone writing-plans into this skill | Bloat | Compose by reference |
| Parallel writers on same files | Conflicts | Partition by file owner |
| "Felt better" manual smoke as GREEN | No machine evidence | Command + excerpt |
| Equate installed server binary with repo | Drift | Label installed separately |

| Worker writes Product DONE / "finished" without closeout AND | Overstep / self-admit | Max = candidate_complete; scorecard admits |
| Repair code during closeout to force green | Verifier became worker | Stop; execute recovery pack; re-closeout |
| Trust pack prose over suite/SHA/gun scan | Hostile artifact steering | Deterministic external proofs first |
| Equate structural VALID with Product DONE | Denominator confusion | VALID = advisory structure only |
| One-session gun absence → "production reliable" | Unsupported claim | Grade case-study; do not inflate |
| Chat/todo says done while scorecard red/missing | Bypass canonical signal | Scorecard is sole Product DONE signal |

## Recovery from wipe

1. Stop editing.
2. List stage packs that still describe IMPLEMENT.
3. Restore from: pack notes, Desktop/artifact SHA match, reflog only if safe.
4. Re-run RED→GREEN; new pack addendum noting recovery.

Playbooks: [recovery](recovery.md) · [decision-tree](decision-tree.md) · [session-handoff](session-handoff.md)
