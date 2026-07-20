# FIX-AGENT-4 — Tunnel Mac + PushConf

Date: 2026-07-20  
Scope: `scripts/client/mac/connect.sh`, `scripts/client/git-mode.sh`  
No deploy / no commit.

## Fixed slugs

| # | Slug | Status | Where |
|---|------|--------|-------|
| 7 | `mac-pushconf-or-true-dead-fail` | Fixed | `git-mode.sh` `push_server_connect_conf`: removed `\|\| true`; require `PUSH_CONF_RESULT`; empty RESULT → `return 1` (not 0); no dedupe on fail |
| 27 | `clear-mount-reason-mac-missing` | Fixed | `clear_session_mount` 6th arg `reason` → `Reason=` in CLEAR_MOUNT log; callers pass `unexpected_disconnect` / `auto_recovery` / `user_quit` |
| 55 | `ensure-tunnel-log-parity` | Fixed | `ENSURE_TUNNEL` start / killing / spawned / ok=1 / ok=0 / reused tunnel_up logs |
| 56 | `ensure-recent-success-mac-absent` | Fixed | `_LAST_TUNNEL_SPAWN_*` + 5s `reason=recent_success` reuse |
| 58 | `clear-mount-down-log-level` | Fixed | CLEAR down begin/end at **INFO** (+ `ms=`) |
| 75 | `mac-recover-quote-mangle` | Fixed | Single remote `sshx "timeout 30 $CM recover-one … \|\| … \|\| recover …"`; INFO/WARN recover logs; UI warns on ssh fail |
| 76 | `mac-tunnel-wait-4-vs-win-12` | Fixed | `wait_for_tunnel_up` + `poll_tunnel_with_progress` loop **12**; `TUNNEL_WAIT` logs |
| 77 | `banner-miss-tcp-softfail-never-drops` | Fixed (Mac) | `sync_session_tunnel_forward` budgets `banner_miss_tcp_open` → DROP at 6 |
| 78 | `ensure-reuses-zombie-on-banner-miss` | Fixed (Mac) | Ensure soft_fail logs `action=reseed` and does **not** set `TUNNEL_REUSED` / return success |
| 81 | `mac-abort-no-clear-active-mount` | Fixed | Abort Q paths: `push_server_connect_conf --clear` |
| 82 | `mac-post-recover-pid-only` | Fixed | Post-recover: `tunnel_up` (banner) not `_tunnel_alive` PID |
| 83 | `mac-fallthrough-skips-recovery-policy` | Fixed | Set `_action=r` **before** r handler; removed continue-past-policy elif |

## Files touched

- `scripts/client/git-mode.sh`
- `scripts/client/mac/connect.sh`
- `scripts/tmp/FIX-AGENT-4.md` (this report)

## Leftover risks

- Concurrent agents also edited these files during this run; re-verify markers if another agent rewrites `git-mode.sh` / `connect.sh`.
- Win-side 77/78/84 owned by Agent 3 — Mac parity done here only.
- Recover remote cmd still ends with `|| true` (Win parity) so mount-tool soft failures inside SSH stay exit 0; only SSH transport failures surface as RECOVER fail WARN.
- `push_server_connect_conf` still used without checking return at many call sites (fail is logged; callers may ignore).
- No e2e run (no deploy); `bash -n` only on patched copies.

## Verify snippets (laptop)

```
laptop-exec rg -p claude-code-server 'PUSH_CONF fail|reason=\$reason|recent_success|banner_miss_tcp_open_budget|RECOVER: fail|ENSURE_TUNNEL ok=|seq 1 12' scripts/client/git-mode.sh
laptop-exec rg -p claude-code-server 'push_server_connect_conf --clear|if ! tunnel_up|fallthrough_recover|unexpected_disconnect|auto_recovery|user_quit' scripts/client/mac/connect.sh
```
