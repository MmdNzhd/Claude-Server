# REVIEW — Mount/git + Update + Designer UX

Date: 2026-07-20  
Method: laptop-exec only (`-p claude-code-server`); live file reads (not agent self-reports).  
FIX reports present: `scripts/tmp/FIX-AGENT-2.md` only (for this scope). **Missing:** `FIX-AGENT-6.md`, `FIX-AGENT-8.md`.

Critical checks:

| Check | Result |
|-------|--------|
| 1. Win restore never deletes real `.git` when both exist | **PASS** (skip / Leaf-only remove) |
| 2. Watchdog restores git on tunnel-down umount | **PASS** (`claude-mount down` before raw umount) |
| 3. Empty `ACTIVE_MOUNT` no longer first-alphabetical | **PASS** |
| 4. Update fail nonzero / rollback / atomic / checksum / BOM / bat bound | **PASS** (Win+Mac+deploy+publish+bat) |
| 5. Designer Persian quit (`useVk`); mutex; `ClearActiveMount` | **PASS** on designer; **FAIL** on `connect-design.ps1` |
| 6. Comment/docs-only or overclaimed fixes | **YES** — Agent-2 claims #22/#24 FIXED; live `git-mode.sh` / `Warn-ForeignServerSession` still broken |

Verdict: **WARNING** — Mount mostly good except #22/#24; Update track PASS; UX partial (design fork + Wait-before-UI).

---

## Mount (bugs 5, 6, 20–24, 67, 68)

| # | Slug | Result | Evidence |
|---|------|--------|----------|
| 5 | `win-restore-deletes-git` | **PASS** | `scripts/server/claude-mount.sh:227` `restore_try`: if `.git` is Container+HEAD → `GIT_HIDE:skip`; `Remove-Item` only for `-PathType Leaf`. Also `:159` `_restore_git_body` Win path. |
| 6 | `watchdog-tunnel-down-no-git-restore` | **PASS** | `scripts/server/claude-watchdog.sh:127-131`: on `! tunnel_up`, calls `"$MOUNT_BIN" down` before `_umount_path` loop (restore via mount path). |
| 20 | `active-mount-first-conf-inference` | **PASS** | `scripts/server/claude-automount.sh:102-109`: LAST_ACTIVE only; comment forbids first alphabetical. `claude-watchdog.sh:74-76`: `_infer_active` returns 1 after mounted scan — no first-conf fallback. |
| 21 | `git-hide-worktree-file-unhandled` | **PASS** | `claude-mount.sh:226` hide_try: `PathType Leaf` → skip; Container-only rename. Mac hide `:208` `-f` skip / `-d` rename. |
| 22 | `mac-banner-false-accept-linux` | **FAIL** | Server `claude-mount.sh:418` tightened (`Fedora|Alpine|…|\bLinux\b` + `OpenSSH_XpY `). **Client** `scripts/client/git-mode.sh:757` still only rejects `OpenSSH_for_Windows|Ubuntu|Debian|el[0-9]+` — Mac connect still false-accepts generic Linux OpenSSH. FIX-AGENT-2 overclaims both files fixed. |
| 23 | `scm-policy-never-reenabled` | **PASS** | `claude-mount.sh:306-380` `_apply_git_scm_policy`: `mode == "server"` clears stuck `git.enabled`/`autoRepositoryDetection` false and pops depth 0. |
| 24 | `foreign-session-ss-false-stale-clear` | **FAIL** | Mac `git-mode.sh` `warn_foreign_server_session`: empty `ss` count → `live=0` → `rm` conf (still). Win `git-mode.ps1:966-975` `Warn-ForeignServerSession`: ss fail leaves `$live=0` → clears conf. No `SS:UNKNOWN` gate in live code. FIX-AGENT-2 overclaims. |
| 67 | `trusted-already-mounted-skips-hide` | **PASS** | `claude-mount.sh` already-mounted path: `_hide_git_and_create_stubs` runs **before** trusted early return (`~586-594`). |
| 68 | `mount-load-global-no-cr-strip` | **PASS** | `claude-mount.sh:26-27` `_load_global`: `v="$(printf '%s' "$v" | tr -d '\r')"`. |

### Mount notes / overclaims

- `FIX-AGENT-2.md` marks **22** and **24** FIXED; live client `git-mode` does not match. Treat as incomplete land, not comment-only.
- Header comments at `claude-mount.sh:65-68` now match executable hide/restore (not docs-only).

---

## Update (bugs 9, 10, 28–34, 40, 65)

| # | Slug | Result | Evidence |
|---|------|--------|----------|
| 9 | `update-exit0-on-error` | **PASS** | Win `connect-update.ps1:274-275,337-340,348,358,451,525` ERROR → `exit 1`. Mac `connect-update.sh:212-213,244,253,259,333,344` same. Unreachable/up-to-date still `exit 0` (intentional skip). |
| 10 | `win-partial-apply-no-rollback` | **PASS** | Stage to `.client-update-new`, swap via `Swap-LiveDir` / `Restore-FromBak` (`connect-update.ps1:399-525`). Fail → rollback + `exit 1`. Mac `_swap_dir` + `apply_rollback` (`connect-update.sh:340-357`). |
| 28 | `non-atomic-live-copy-item` | **PASS** | No live in-place overlay; build new tree then `Move-Item` swap (`:353-354`, `:455-488`). |
| 29 | `copy-errors-swallowed` | **PASS** | `Copy-Tracked` (`:382-396`) `-ErrorAction Stop`, appends `$failed`, logs `copy_fail`. |
| 30 | `no-checksum-after-scp` | **PASS** | Deploy writes `checksums.txt` (`deploy-client-bundle.sh:264-276`). Client `Test-BundleChecksums` / `_verify_checksums` SHA-256; fail → `exit 1`. |
| 31 | `deploy-client-bundle-rm-live` | **PASS** | Stage `STAGE_BUNDLE`, then `mv` live→old, stage→live (`deploy-client-bundle.sh` ~120–130 + rename-swap tail). No mid-download `rm -rf` of live. |
| 32 | `identityagent-gap-on-client-update` | **PASS** | Win `SshCommonOpts` / scp opts include `IdentityAgent=none` (`connect-update.ps1:29`, `:254`). Mac `SSH_EXTRA_OPTS` (`connect-update.sh:9`). |
| 33 | `mac-update-hang-no-process-timeout` | **PASS** | `_run_timed` wraps ssh/scp (`connect-update.sh:103+`, used `:124`, `:134`). |
| 34 | `publish-manifest-utf8-bom` | **PASS** | `publish/publish.ps1:119-120,131-132` UTF8 no BOM; non-patch copy strips EF BB BF (`:141-146`). Deploy manifest via shell redirect (no PS BOM). |
| 40 | `update-server-exit0-on-verify-fail` | **PASS** | `update-server.sh:141-170`: `VERIFY_OK=0` → red message + `exit 1` (not “Update complete”). |
| 65 | `bat-unbounded-relaunch` | **PASS** | `connect.bat:21-36`: `CLAUDE_CONNECT_UPDATE_DEPTH`, stop at `GEQ 3`. |

---

## UX / Designer (bugs 8, 26, 52, 53, 70, 71)

| # | Slug | Result | Evidence |
|---|------|--------|----------|
| 8 | `designer-pushconf-empty-no-clear` | **PASS** | `scripts/client/users/designer/connect.ps1:455,519,603,624` use `Push-ServerConnectConf -ClearActiveMount` (not bare `-ActiveMount ''`). |
| 26 | `designer-design-key-or-vk` | **FAIL** | Designer **PASS** (`useVk` `:564-568`). `connect-design.ps1:288-289,329-331,353-354` still `KeyChar -or Key` (Persian ض → Q). |
| 52 | `designer-no-single-instance-mutex` | **PASS** | Designer `:145-147` `Enter-ConnectSingleInstance` (shared mutex via connect-ui). `connect-design.ps1` still has no mutex (out of slug name but same fight risk). |
| 53 | `wait-connect-exit-before-ui` | **FAIL** | Designer elevates UAC at `:7-12` before any UI; mutex failure calls `Wait-ConnectExit` (`:147`) **without** `Show-ConnectConsoleIfHidden` first → possible invisible Read-Host. |
| 70 | `persian-quit-designer-win` | **PASS** | Designer session loop `:553-568` ASCII letter + `useVk` only for null/control KeyChar. |
| 71 | `persian-quit-connect-design` | **FAIL** | `connect-design.ps1:329-331` still `$kc -eq 'q' -or $ki.Key -eq [ConsoleKey]::Q`. |

### UX notes

- FIX-AGENT-8.md **absent** — no agent self-report to cross-check.
- Main `connect.ps1` already had `useVk`; designer caught up; **connect-design fork left behind**.

---

## Comment / docs-only / false reports

| Item | Severity | Detail |
|------|----------|--------|
| FIX-AGENT-2 #22/#24 | HIGH | Report says FIXED in `git-mode.sh` + foreign helpers; live code still old. |
| Missing FIX-AGENT-6/8 | INFO | Update/UX fixes exist in tree but no agent report files. |

No case found where the **only** change for a reviewed slug was a comment with executable path still broken for #5/#21 (comments now match code). The failure mode is **overclaimed incomplete land** (#22, #24), not comment-only.

---

## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | pass |
| HIGH | 4 | warn (#22, #24, #26/#71 design keys, #53) |
| MEDIUM | 0 | — |
| LOW | 1 | note (missing FIX-AGENT-6/8) |

| Area | PASS | FAIL |
|------|------|------|
| Mount | 7 | 2 (#22, #24) |
| Update | 11 | 0 |
| UX | 3 | 3 (#26, #53, #71) |

**Verdict: WARNING** — do not treat Mount agent as fully done; fix `git-mode` banner + foreign `SS:UNKNOWN` (Win+Mac), and finish `connect-design.ps1` Persian/`useVk` + designer Wait-after-Show. Update track is solid.
