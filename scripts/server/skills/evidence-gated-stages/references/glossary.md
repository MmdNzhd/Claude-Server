# Glossary

| Term | Meaning |
|------|---------|
| Evidence Pack | `STAGE-*.md` claim + evidence packet for one stage |
| IRON LAW | No N+1 production edits without valid pack N |
| candidate_complete | Worker max; pack VALID + progress line |
| Product DONE | Closeout AND admitted; scorecard on disk |
| Canonical signal | Filled closeout scorecard — only surface that means finished |
| Three truths | repo_green · artifact_sync · runtime_green |
| installed | Fourth observe label (server/PATH); ≠ artifact |
| Smoking gun | Exact non-secret substring/metric that must go absent |
| RUNTIME_GATE | Pack section: gun proof / pending_reconnect / waived N/A |
| LIVE_GATE | Closeout live verdict (alias of runtime truth at audit) |
| P0 stage | Plan-marked; RUNTIME_GATE `N/A` forbidden without waiver |
| Class A/B/C | Product gap / intentional debt / flake |
| Release lock | Deploy/publish forbidden until explicit unlock quote |
| sync_set | Files/roots that must SHA-match for artifact_sync=yes |
| Structural VALID | `validate-pack.py` sections OK — advisory only |
| Admission | Closeout read-only accept/reject of completion claim |
| Overstep | Worker claimed complete / finished without admission |
| Hypothesis ledger | Accepted/rejected claims with evidence |
| Drive-by | Out-of-stage file edits — prefer `drive_by=none` |
| Fail-closed | Ambiguity → blocked, never soft success |
| Hostile pack | Pack prose must not steer the verdict |
