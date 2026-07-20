# SWEEP remaining — 2026-07-20

Scope: leftovers after parent Win banner/ensure + Mac seq/recover.  
Method: `laptop-exec -p claude-code-server` only. **No deploy.**

| Slug | Result | Evidence |
|------|--------|----------|
| `mac-abort-no-clear-active-mount` | **PASS** (fixed this sweep) | Abort Q paths now `ACTIVE_MOUNT_ID=""` + `push_server_connect_conf --clear` (3× in `mac/connect.sh` ~682/726/791). Without `--clear`, empty local id preserved server `ACTIVE_MOUNT`. |
| `mac-fallthrough-skips-recovery-policy` | **PASS** (already fixed) | `Win parity: set action=r before handler` then `fallthrough_recover` sets `_action=r` **without** skipping the preserve/clear recovery block (`mac/connect.sh` ~1012–1016 → `if _action=r` recovery). |
| `ssh-trailing-true-masks-append-fail` / `mac-scp-ok-without-cat-advances-watermark` / ERROR trap flush | **PASS** (already fixed) | Win: `Bug 11: cat must surface append failure (no trailing true)`; `ec=$?; …; exit $ec`; watermark only if `$appendOk`; `ERROR` → `Sync-ConnectLogToServer -Force`; `Close-ConnectLog` Force flush. Mac: `Bug 11/12`; `dd` chunk (no `$(tail)`); advance only if `cat_ok=1`; `sync_connect_log_to_server force` on ERROR + EXIT flush trap. |
| Designer persian quit + mutex + ClearActiveMount | **PASS** (fixed this sweep) | Win: `useVk` gating; tunnel-drop non-command → `$action='r'` (not `q`); `-ClearActiveMount` (not `-ActiveMount ''`); mutex via `Enter-ConnectSingleInstance` **or** inline `Global\ClaudeConnect-{user}` fallback. Mac: `_action=""` (not default `q`); ASCII r/g/q only; `push_server_connect_conf --clear` on disconnect/abort; shared `~/.config/claude-connect/connect.lock` flock. |
| `update-exit0-on-error` + `win-partial-apply-no-rollback` | **PASS** | Win already: ERROR → `exit 1`; staged `.client-update-new` + `Swap-LiveDir` + `apply_rollback`. Mac (this sweep / concurrent refine): validate staging → seed/overlay new tree → `_swap_dir` + `apply_rollback` + `exit 1` on fail; success `exit 2`. |
| `watchdog-tunnel-down-no-git-restore` | **PASS** (already fixed) | Tunnel DOWN: `"$MOUNT_BIN" down` (attempts restore when tunnel briefly usable). Remount path: `"$MOUNT_BIN" recover` then `up`. Direct SSH restore is impossible while tunnel is hard-down; recover on reconnect is the correct design. |
| `active-mount-first-conf-inference` | **PASS** (already fixed) | Automount: `Infer ACTIVE_MOUNT from LAST_ACTIVE only (never first alphabetical conf)`. Watchdog `_infer_active`: `Do NOT pick first alphabetical conf…`. |

## Files touched this sweep

- `scripts/client/mac/connect.sh` — abort `--clear`
- `scripts/client/mac/connect-update.sh` — staged apply / rollback / nonzero ERROR exit
- `scripts/client/users/designer/connect.ps1` — Persian drop→r, mutex fallback, ClearActiveMount (already mostly present)
- `scripts/client/users/designer/connect.sh` — flock, empty `_action`, `--clear`, ASCII key filter

## Not reverted

Mac recover/seq parent fixes left intact (`fallthrough` sets `_action=r` into recovery policy).

## Verdict

All 7 leftover areas: **PASS**.
