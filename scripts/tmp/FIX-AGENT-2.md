# Fix Agent 2 (Mount/git) — results

Project: `claude-code-server` via laptop-exec only. No deploy/publish/commit.

| # | Slug | Status | Change |
|---|------|--------|--------|
| 5 | `win-restore-deletes-git` | **FIXED** | Win `restore_try` / `_restore_git_body`: never `Remove-Item` on a real `.git` dir; skip when both exist + HEAD; only remove worktree pointer (`PathType Leaf`) before rename. Mac restore similarly skips dir clash. |
| 6 | `watchdog-tunnel-down-no-git-restore` | **FIXED** | `claude-watchdog.sh` tunnel-DOWN path calls `"$MOUNT_BIN" down` before raw umount (restore `.git` from `.git.server-session` when possible). |
| 20 | `active-mount-first-conf-inference` | **FIXED** | Removed first-alphabetical conf fallback in `claude-automount.sh` and `claude-watchdog.sh` `_infer_active`. Empty `ACTIVE_MOUNT` stays empty unless LAST_ACTIVE / already-mounted. |
| 21 | `git-hide-worktree-file-unhandled` | **FIXED** | Win hide uses `-PathType Container` only; Leaf → `GIT_HIDE:skip`. Mac hide: `-f` skip, `-d` rename. |
| 22 | `mac-banner-false-accept-linux` | **FIXED** | Tightened Mac banner reject list (Fedora/Alpine/CentOS/…/`Linux`) + reject `OpenSSH_XpY <distro>` space-suffix in `claude-mount.sh` and `git-mode.sh`. |
| 23 | `scm-policy-never-reenabled` | **FIXED** | `_apply_git_scm_policy` now runs on `server` mode and clears stuck `git.enabled`/`autoRepositoryDetection` false (and depth 0). |
| 24 | `foreign-session-ss-false-stale-clear` | **FIXED** | `warn_foreign_server_session` / `Warn-ForeignServerSession`: `SS:UNKNOWN` on ss failure → do **not** clear conf; only clear on confirmed `SS:0` / no port. |
| 67 | `trusted-already-mounted-skips-hide` | **FIXED** | Already-mounted + trusted path always calls `_hide_git_and_create_stubs` before early return. |
| 68 | `mount-load-global-no-cr-strip` | **FIXED** | `_load_global` in `claude-mount.sh` strips `\r` from conf values (parity with watchdog). |

## Files touched

- `scripts/server/claude-mount.sh`
- `scripts/server/claude-watchdog.sh`
- `scripts/server/claude-automount.sh`
- `scripts/client/git-mode.sh`
- `scripts/client/git-mode.ps1`
- `scripts/tmp/FIX-AGENT-2.md` (this report)

## Notes

- Restore over SSH still needs a reachable tunnel; watchdog now uses the same `claude-mount down` path as intentional disconnect.
- No deploy performed (agent scope).
