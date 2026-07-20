# Connect Edge-Case Matrix (post P0+sticky) — v20260719.22

Legend: COVERED = coded+asserted or coded with clear log markers; ACCEPT = known residual risk; PREEXIST = unrelated fail.

## A. Recovery / lifecycle (Win + Mac)

| # | Case | Win | Mac |
|---|------|-----|-----|
| 1 | Auto-R + editor on folder → no CLEAR_MOUNT | COVERED `RECOVERY_SKIP_CLEAR_MOUNT` + sticky | COVERED sticky `_editor_seen_open` |
| 2 | Auto-R + editor closed → CLEAR + STOP tunnel | COVERED | COVERED |
| 3 | Auto-R + transient detect miss after seen open | COVERED `EditorSeenOpen` | COVERED `_editor_seen_open` |
| 4 | Auto-R + editor check throws | COVERED keep skip if sticky | COVERED |
| 5 | Auto-R skip path re-ENSURE tunnel immediately | COVERED `Initialize-SessionBgTunnel` | COVERED ensure path |
| 6 | Manual R (user) full reconnect | COVERED clears sticky | COVERED |
| 7 | Q disconnect always clear+stop | COVERED | COVERED |
| 8 | finally + editor sticky → keep tunnel | COVERED `FINALLY_KEEP_TUNNEL` | COVERED |
| 9 | finally + Q alreadyDown → no double clear mount | COVERED | COVERED |
| 10 | Window force-close mid-session | COVERED finally sticky | COVERED |

## B. Sync / tunnel health

| # | Case | Win | Mac |
|---|------|-----|-----|
| 11 | ¬P + TCP open → soft_fail (bounded) | COVERED soft≤5 then escalate | COVERED |
| 12 | ¬P + TCP closed → debounce 3 → tunnel_down | COVERED | COVERED |
| 13 | P alive + banner miss + TCP open → soft_fail | COVERED | COVERED |
| 14 | P alive + forward dead → 3 miss → DROP | COVERED | COVERED |
| 15 | MaxStartups banner | COVERED soft_fail empty | COVERED |
| 16 | Reattach CIM before declare down | COVERED | COVERED |
| 17 | Exit code logged on ssh -R death | COVERED | ACCEPT (less) |

## C. ORPHAN / ENSURE

| # | Case | Win | Mac |
|---|------|-----|-----|
| 18 | Do not kill SessionBgTunnel orphan | COVERED protected PIDs | COVERED TCP soft on ensure |
| 19 | Ensure banner miss + TCP open → reuse | COVERED | COVERED |
| 20 | Recent spawn guard keyed by port+pid | COVERED `LastTunnelSpawnSuccessPort` | ACCEPT |
| 21 | Healthy tunnel_up reuse | COVERED | COVERED |

## D. Push / noise

| # | Case | Status |
|---|------|--------|
| 22 | PUSH_CONF no self-heal | COVERED Win+Mac |
| 23 | TRACE sync ≥30s | COVERED |
| 24 | PERF gated | COVERED |

## E. Residual (ACCEPT / later)

| # | Case | Notes |
|---|------|--------|
| 25 | Sticky forever until Q/manual R | If user closes Cursor without Connect noticing, sticky may preserve mount longer — intentional safety bias |
| 26 | Soft-fail 6 then may still CLEAR if editor not sticky | Correct least-damage tradeoff |
| 27 | alreadyDown overloaded semantics | Partially mitigated; full state machine split still later |
| 28 | git menu option test fail | PREEXIST unrelated |
| 29 | Slot churn mid-session | Later P1 |
| 30 | Fleet version skew / wrong package boot-guard | Later P3 |

