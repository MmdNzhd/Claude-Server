# Deep forensic — Farzad + Sepidz fleet (2026-07-19)

## Fleet versions now
- Sepidz bundle: **20260719.28** (useVk Persian fix + base64 PushConf)
- Smart: **20260717.22** frozen
- Farzad server log still ends at `.21→.24 need_relaunch` — **no .26/.28 session synced yet**

## Farzad day timeline (connect-20260719.log, 3229 lines, 0 consecutive dupes)

| Sid | Ver | Start | Project | Launch | Verdict | STATUS_OK | End |
|-----|-----|-------|---------|--------|---------|-----------|-----|
| (boot) | .4 | 12:19 | — | — | — | 0 | bumped to .21 |
| c8b5dcbbf9ea | .21 | 14:38 | frontend | OK | CURSOR_ON_FOLDER_OK | 110 | quit `keychar=q` (intentional) |
| 6f4ec092447e | .21 | 15:47 | frontend | OK | CURSOR_ON_FOLDER_OK | 50 | quit `keychar=ض` **accidental** |
| 0e44cba4960a | .21 | 16:14 | frontend | OK | CURSOR_ON_FOLDER_OK | 12 | relaunch without clear |
| e8d13f00fd71 | .21 | 16:43 | frontend | OK | CURSOR_ON_FOLDER_OK | 16 | quit `keychar=ض` **accidental** → update `.21→.24` |

## Decision classification (3 quits)
1. `keychar=q` — English quit, intentional
2. `keychar=ض` ×2 — physical Q under Persian layout → **false quit**

## Structural bugs evidenced in log
- **PushConf quote-eat**: 11× `syntax error near unexpected token elif` (`AM="` → broken). ACTIVE_MOUNT stuck `backend` while client pushed `frontend` (4× mismatch lines). Conf on server still `ACTIVE_MOUNT=backend` until .28 PushConf runs.
- **No tunnel_down / soft_fail / RECOVERY_SKIP** in Farzad day — original "Cursor connection fail" smoking gun was NOT this user's today pattern; today was false quit + conf push fail.
- **373× menu WARN** — Persian typing in project menu
- **STATUS_OK gaps** 208s / 1431s — likely laptop sleep or TRACE sync hole; tunnel was up before/after, not CLEAR_MOUNT auto-recovery

## Fleet contrast (same day logs)
| User | Size | Syntax elif | Quit q | keychar=ض | AM mismatch | .28 in log |
|------|------|-------------|--------|-----------|-------------|------------|
| farzadb | 379K | **11** | **3** | **2** | 4 | 0 |
| aminb | 6.5M | 0 | 0 | 0 | 1 | 0 |
| hosseinb | 10M | 0 | 0 | 0 | 2 | 0 |
| smart (sepidz) | 5.4M | 0 | 0 | 0 | 27 | 0 |
| zahrak | 12K | 0 | 0 | 0 | 0 | 0 |

Farzad is the only user with elif syntax storm + Persian false quit. Others have AM mismatch lines (read-only observation) but 0 syntax errors — may be older client path or different PushConf timing.

## Fix layers
| Ver | What |
|-----|------|
| .24 | P0 recovery skip CLEAR_MOUNT when editor open |
| .26 | base64 PushConf + action='' default (incomplete Persian fix) |
| .28 | **useVk**: VK fallback only for null/control KeyChar; ض ignored; fallthrough recover normalized to full `action=r` path |

## Residual risks
1. Farzad must relaunch connect to pick up .28 (log still at need_relaunch .24)
2. Project menu Persian WARN spam still open
3. Mac PushConf parity not re-audited this pass
4. AM_MIS on other users — verify after they update whether base64 PushConf clears it
5. Long TRACE gaps — consider heartbeat INFO every N minutes for sleep detection
