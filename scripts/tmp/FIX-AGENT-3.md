# FIX-AGENT-3 — Tunnel Windows (2026-07-20)

**Scope:** bugs 25, 77, 78, 79, 80, 84 (+ win banner-miss / softfail).  
**Rules:** laptop-exec only; no deploy; no commit.

## Fixed slugs

| # | Slug | Fix |
|---|------|-----|
| 25 | `win-softfail-budget-no-drop` | After `TunnelSoftFailCount >= 6` on `no_proc_tcp_open`, log `TUNNEL_DROP … reason=no_proc_tcp_open_budget` and `return $false` (Mac parity). Budget checked **before** reattach (reattach resets soft-fail count). |
| 84 | `win-softfail-budget-no-hard-return` | Same hard return as #25 (no fall-through soft-up after budget). |
| 77 | `banner-miss-tcp-softfail-never-drops` | `banner_miss_tcp_open` increments soft-fail budget; at ≥6 logs `TUNNEL_DROP … reason=banner_miss_tcp_open_budget` and returns `$false`. Stopped resetting soft-fail on every miss / every bg-alive tick. |
| 78 | `ensure-reuses-zombie-on-banner-miss` | `Ensure-SessionTunnel` on banner miss + TCP open logs `action=reseed` and falls through to kill/reseed (no `return $true` / no `TUNNEL_REUSED`). |
| 79 | `editor-seen-sticky-skips-mount-clear` | Clear `EditorSeenOpen` when editor window is gone (open/poll/auto-recovery/finally). `skipRecoveryClear` no longer set from sticky alone after Cursor closed. |
| 80 | `win-sticky-forces-editorOpened` | Removed sticky→`editorOpened=$true`. `editorOpened` only from real on-folder evidence. |

## Files touched

- `scripts/client/git-mode.ps1` — `Sync-SessionTunnelProcess`, `Ensure-SessionTunnel`
- `scripts/client/windows/connect.ps1` — session open / poll / auto-recovery / finally sticky handling
- `scripts/tmp/FIX-AGENT-3.md` — this report

## Logging (INFO/WARN)

- `TUNNEL_DROP … no_proc_tcp_open_budget` (WARN)
- `TUNNEL_DROP … banner_miss_tcp_open_budget` (WARN)
- `ENSURE_TUNNEL soft_fail … action=reseed` (WARN)
- `EDITOR_SEEN_CLEAR reason=editor_closed phase=…` (INFO)
- `RECOVERY_SKIP_CLEAR_MOUNT reason=editor_window_open_not_on_folder` (INFO)

## Verify (rg)

```
laptop-exec rg -p claude-code-server "no_proc_tcp_open_budget|banner_miss_tcp_open_budget|action=reseed|EDITOR_SEEN_CLEAR" \
  scripts/client/git-mode.ps1 scripts/client/windows/connect.ps1
```

Verified present after final write.

## Leftover risks

- Soft-fail budget is shared between `no_proc_tcp_open` and `banner_miss_tcp_open` (same `/6` counter).
- Transient CIM failure during auto-recovery may still skip clear via sticky (`editor_check_failed_sticky`) — narrow fallback when check throws.
- Mac Ensure/sync banner-miss owned by Agent 4; this agent only fixed Windows.
- `git-mode.ps1` is shared; concurrent agent writes briefly overwrote an earlier apply — final re-apply verified via rg.
- No runtime connect soak test in this pass (code + rg only).
