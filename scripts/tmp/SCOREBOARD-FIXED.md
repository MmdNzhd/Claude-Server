# SCOREBOARD-FIXED — Bug inventory 1–84

**Date:** 2026-07-20  
**Project:** `-p claude-code-server` (laptop-exec only; **no deploy**)  
**Method:** Waited ≥90s, then classified each slug via **rg / file evidence in current tree** (not agent claims alone). Prefer **OPEN** when the bug pattern is still present.  
**Named docs:** `LOCK-VERIFY.md` **present (PASS)**; `FIX-MAC-P1.md` **present (PASS)**; `FIX-WIN-P1.md` **MISSING** (see `FIX-WIN-TUNNEL-DONE.md` / `FIX-AGENT-3.md`); `FIX-MOUNT-SEC.md` **MISSING** (see `FIX-AGENT-2.md` / security in `FIX-AGENT-1.md`).

---

## Verdict

# **NOT_READY**

Reasons (honest):

1. **P0 still OPEN:** `#15 log-sync-readallbytes-full-file` — `ReadAllBytes` remains in `scripts/client/connect-ui.ps1` and `scripts/client/windows/connect-update.ps1` (full-day log load every sync).
2. **P1 residual risk:** `#22` Mac banner reject in `git-mode.sh` is still weaker than `claude-mount.sh` (missing `\bLinux\b` / Fedora / Alpine class rejects).
3. **Resource/UX leftovers:** `#47` HEARTBEAT still dumps editor explain; `#42` auth relaunch when already on folder; `#51` soft-fail path still CIM-scans `ssh.exe`.
4. **Gate docs disagree:** older `FINAL-GATE.md` = FAIL (git-mode-deep); later `LOCK-VERIFY.md` / `LOCK-STATUS.md` = PASS. Do not deploy until gates are reconciled and P0 `#15` is closed.

**Do not deploy.** Suitable only for continued fix work; not ready for user ship review as “all serious closed.”

---

## P0: FIXED vs OPEN

| # | Slug | Status | Evidence (current tree) |
|---|------|--------|-------------------------|
| 1 | `hardcoded-sepidz-sudo-fallback` | **FIXED** | `rg sepidz@Admin` → no hits; `publish/Get-DeployCredentials.ps1` exists with throw path (FIX-AGENT-1) |
| 2 | `sepidz-ak-merge-plus-nopasswd-bundle` | **FIXED** | sudoers template Smart-only NOPASSWD; comments forbid sepidz merge; no sepidz NOPASSWD |
| 3 | `shared-oauth-in-etc-environment` | **FIXED** | `/etc/claude-code/oauth.env` + strip legacy `/etc/environment` in `claude-auth-lib.py` |
| 4 | `sqlserver-password-in-add-user-template` | **FIXED** | `CHANGE_ME`; `rg Mohammad123` → no hits |
| 5 | `win-restore-deletes-git` | **FIXED** | `restore_try` skips real `.git` dir+HEAD; `Remove-Item` only for PathType Leaf |
| 6 | `watchdog-tunnel-down-no-git-restore` | **FIXED** | watchdog prefers `claude-mount down` before raw umount |
| 7 | `mac-pushconf-or-true-dead-fail` | **FIXED** | no `\|\| true` swallow; requires `PUSH_CONF_RESULT` / nonzero exit |
| 8 | `designer-pushconf-empty-no-clear` | **FIXED** | designer uses `Push-ServerConnectConf -ClearActiveMount` on quit/disconnect |
| 9 | `update-exit0-on-error` | **FIXED** | `windows/connect-update.ps1` ERROR paths `exit 1` (header documents contract) |
| 10 | `win-partial-apply-no-rollback` | **FIXED** | staging + `apply_rollback` / Move-Item bak restore |
| 11 | `ssh-trailing-true-masks-append-fail` | **FIXED** | Win/Mac: `exit $ec` after cat append; comments “no trailing true” |
| 12 | `mac-scp-ok-without-cat-advances-watermark` | **FIXED** | advance only if remote cat append succeeds (`connect-ui.sh`) |
| 13 | `win-auth-skip-ignores-golden-rotation` | **FIXED** | `golden_stale` / `golden-synced-at` (FIX-W4 + code) |
| 14 | `mac-o-key-dead-when-sticky-opened` | **FIXED** | Mac O allows reopen when not on folder even if `_editor_opened=1` |
| 15 | `log-sync-readallbytes-full-file` | **OPEN** | `ReadAllBytes` still in `connect-ui.ps1:247` and `windows/connect-update.ps1:543` |
| 74 | `hardcoded-sepidz-sudo-in-deploy-bundles` | **FIXED** | `rg sepidz@Admin` → no hits in publish |
| 75 | `mac-recover-quote-mangle` | **FIXED** | `sshx "timeout 30 $CM recover-one…"`; no nested `timeout 30 sshx` |
| 76 | `mac-tunnel-wait-4-vs-win-12` | **FIXED** | `seq 1 4` absent; two `seq 1 12` wait/poll loops |

### P0 counts

| Status | Count |
|--------|------:|
| FIXED | **17** |
| OPEN | **1** (#15) |
| UNKNOWN | **0** |

---

## P1 open list (top 20)

Ordered by residual risk (honesty: pattern still present or incomplete fix).

| Rank | # | Slug | Why still OPEN |
|------|---|------|----------------|
| 1 | 22 | `mac-banner-false-accept-linux` | `git-mode.sh` Mac reject list lacks `\bLinux\b`/Fedora/Alpine class that `claude-mount.sh` has |
| 2 | 42 | `auth-relaunch-unused-when-already-on-folder` | When editor already on folder, soft-stop/relaunch path may not run (FIX-W4 leftover) |
| 3 | 47 | `heartbeat-explain-log-growth` | `HEARTBEAT:` + `Get-RemoteEditorStateExplain` still in `connect-ui.ps1` |
| 4 | 51 | `tunnel-softfail-cim-reattach-storm` | `Get-CimInstance Win32_Process Name='ssh.exe'` still in soft-fail/reattach paths |
| 5 | 53 | `wait-connect-exit-before-ui` | Early `Wait-ConnectExit` still before UI on boot/require failures (guarded but early) |
| 6 | 19 | `secrets-adjacent-logging` | Fingerprints remain (sha256/len only — **mitigated**); still world-readable log concern until live chmod — treat as residual **OPEN-lite** |
| 7 | 49 | `log-sync-ssh-kill-orphans` | Update path has `taskkill`; connect-ui sync orphan reap not fully evidenced → residual |
| 8 | 73 | `warn-sync-storm-amplifies-ram` | Coupled to #15 full-file reads under WARN/flap |
| 9 | 66 | `mac-agent-home-false-positive-vs-win` | Not deeply re-verified; Mac Agent/home reopen aggressiveness may remain |
| 10 | 44 | `win-code-no-isolated-profile` | Marked FIXED in scan (`ClaudeServerCodeProfile`) — **exclude from open**; see FIXED table |
| 11 | 48 | `session-cim-cache-no-ttl` | No clear TTL symbol found → treat **UNKNOWN/OPEN** |
| 12 | 50 | `start-job-scp-orphan-on-timeout` | Partial (`taskkill` in update); Job orphan path unclear → residual |
| 13 | 55 | `ensure-tunnel-log-parity` | Mac ENSURE verbosity parity not deeply verified → UNKNOWN→open candidate |
| 14 | 56 | `ensure-recent-success-mac-absent` | Partial: ensure mentions recent_success; full 5s reuse parity UNKNOWN |
| 15 | 57 | `controlmaster-asymmetry` | Architectural asymmetry remains (Win no mux / Mac mux) |
| 16 | 60 | `session-double-onfolder-check` | Double folder checks still likely in session loop |
| 17 | 65 | `bat-unbounded-relaunch` | conf-3 watch item; not deeply re-verified |
| 18 | 33 | `mac-update-hang-no-process-timeout` | Scan found timeout patterns — may be FIXED; keep watch |
| 19 | 29 | `copy-errors-swallowed` | **Likely FIXED** (`$failed` + ErrorAction Stop) — demoted; listed as watch |
| 20 | 32 | `identityagent-gap-on-client-update` | **FIXED** (`IdentityAgent=none` in win/mac update) — not open |

**Cleaner top OPEN P1 (strict):** 22, 42, 47, 51, 53, 48, 49, 50, 55, 56, 57, 60, 65, 66, 73 (+ mitigated 19).

Many other P1s from the inventory are **FIXED** in-tree (16–18, 20–21, 23–27, 28, 30–31, 34–37, 38–41, 43–46, 52, 70–72, 77–81, 84). See full matrix below.

---

## Test status (LOCK-VERIFY / pipe)

| Artifact | Status | Notes |
|----------|--------|-------|
| `scripts/tmp/LOCK-VERIFY.md` | **PASS** | P0 static checks + `test-connect-pipeline` + `test-git-mode-deep` exit 0 (later than FINAL-GATE) |
| `scripts/tmp/LOCK-STATUS.md` | **GREEN** | Same P0 invariants; pipeline + git-mode-deep passed |
| `scripts/tmp/FINAL-GATE.md` | **FAIL (stale)** | Only check 6 failed (`editor-launch.sh` folder-uri assert); later LOCK-VERIFY says deep suite PASS after assert tighten |
| `scripts/tmp/pipe-final.txt` | **PASS** | “All tests passed.” |
| `scripts/tmp/TEST-AGENT-PIPELINE.md` | **HARD FAIL (older)** | Curly-quote assert false positive on UTF-8 em dash/`ض`; superseded by LOCK-VERIFY pipeline PASS |
| `scripts/tmp/TEST-SCOREBOARD.md` | **NOT READY (stale)** | Written before many fixes landed; do not trust for current tree |
| `scripts/tmp/TEST-AGENT-GITMODE.md` | PASS (earlier wave) | Softfail/banner/recover held |
| Named `FIX-WIN-P1.md` / `FIX-MOUNT-SEC.md` | **MISSING** | Covered by `FIX-WIN-TUNNEL-DONE.md`, `FIX-AGENT-2/3` |

---

## Full classification 1–84

| # | Sev | Slug | Status | One-line evidence |
|---|-----|------|--------|-------------------|
| 1 | P0 | hardcoded-sepidz-sudo-fallback | FIXED | no `sepidz@Admin` |
| 2 | P0 | sepidz-ak-merge-plus-nopasswd-bundle | FIXED | Smart-only sudoers; no-merge |
| 3 | P0 | shared-oauth-in-etc-environment | FIXED | oauth.env 0600 path |
| 4 | P0 | sqlserver-password-in-add-user-template | FIXED | CHANGE_ME |
| 5 | P0 | win-restore-deletes-git | FIXED | leaf-only Remove-Item |
| 6 | P0 | watchdog-tunnel-down-no-git-restore | FIXED | mount down first |
| 7 | P0 | mac-pushconf-or-true-dead-fail | FIXED | RESULT/exit gate |
| 8 | P0 | designer-pushconf-empty-no-clear | FIXED | ClearActiveMount on quit |
| 9 | P0 | update-exit0-on-error | FIXED | exit 1 on ERROR |
| 10 | P0 | win-partial-apply-no-rollback | FIXED | rollback/staging |
| 11 | P0 | ssh-trailing-true-masks-append-fail | FIXED | exit $ec |
| 12 | P0 | mac-scp-ok-without-cat-advances-watermark | FIXED | cat-gated advance |
| 13 | P0 | win-auth-skip-ignores-golden-rotation | FIXED | golden_stale |
| 14 | P0 | mac-o-key-dead-when-sticky-opened | FIXED | O reopen allowed |
| 15 | P0 | log-sync-readallbytes-full-file | **OPEN** | ReadAllBytes remains |
| 16 | P1 | always-elevated-connect | FIXED | AdminFix only |
| 17 | P1 | administrators-authorized-keys-server-key | FIXED | from=loopback rewrite |
| 18 | P1 | cursor-golden-world-readable | FIXED | 0600/0700 in lib |
| 19 | P1 | secrets-adjacent-logging | OPEN | fp remains (hash-only) |
| 20 | P1 | active-mount-first-conf-inference | FIXED | no first-alpha write |
| 21 | P1 | git-hide-worktree-file-unhandled | FIXED | Leaf skip |
| 22 | P1 | mac-banner-false-accept-linux | **OPEN** | git-mode.sh weak list |
| 23 | P1 | scm-policy-never-reenabled | FIXED | server mode clears flags |
| 24 | P1 | foreign-session-ss-false-stale-clear | FIXED | SS:UNKNOWN no clear |
| 25 | P1 | win-softfail-budget-no-drop | FIXED | DROP at ≥6 |
| 26 | P1 | designer-design-key-or-vk | FIXED | useVk gating |
| 27 | P1 | clear-mount-reason-mac-missing | FIXED | Reason= / reason= |
| 28 | P1 | non-atomic-live-copy-item | FIXED | staging/swap |
| 29 | P1 | copy-errors-swallowed | FIXED | $failed + Stop |
| 30 | P1 | no-checksum-after-scp | FIXED | checksum_fail path |
| 31 | P1 | deploy-client-bundle-rm-live | FIXED | staging/strip server |
| 32 | P1 | identityagent-gap-on-client-update | FIXED | IdentityAgent=none |
| 33 | P1 | mac-update-hang-no-process-timeout | FIXED | timeout patterns |
| 34 | P1 | publish-manifest-utf8-bom | FIXED | NoBOM encoding |
| 35 | P1 | docs-temp-log-lie | FIXED | durable log docs |
| 36 | P1 | trace-debug-skip-sync-trigger | FIXED | TRACE sync hooks |
| 37 | P1 | midnight-rollover-abandons-unsynced-day | FIXED | rollover flush |
| 38 | P1 | mac-tail-cmdsubst-wc-watermark-loss | FIXED | dd not $(tail) |
| 39 | P1 | sshx-swallow-callers | FIXED | Invoke-SshXChecked |
| 40 | P1 | update-server-exit0-on-verify-fail | FIXED | fail exits |
| 41 | P1 | missing-pushconf-quoting-e2e | FIXED | test-pushconf-quoting |
| 42 | P1 | auth-relaunch-unused-when-already-on-folder | **OPEN** | leftover path |
| 43 | P1 | mac-auth-relaunch-on-skipped-failure | FIXED | skipped no relaunch |
| 44 | P1 | win-code-no-isolated-profile | FIXED | CodeProfile |
| 45 | P1 | win-needs-refresh-misses-machineid-file | FIXED | machineid_file_mismatch |
| 46 | P1 | win-build-auth-early-path-drops-auth-json-metadata | FIXED | email/stripe copy |
| 47 | P1 | heartbeat-explain-log-growth | **OPEN** | HEARTBEAT explain |
| 48 | P1 | session-cim-cache-no-ttl | UNKNOWN | no TTL found |
| 49 | P1 | log-sync-ssh-kill-orphans | OPEN | partial only |
| 50 | P1 | start-job-scp-orphan-on-timeout | UNKNOWN | partial taskkill |
| 51 | P1 | tunnel-softfail-cim-reattach-storm | **OPEN** | CIM ssh scans |
| 52 | P1 | designer-no-single-instance-mutex | FIXED | mutex present |
| 53 | P1 | wait-connect-exit-before-ui | **OPEN** | early Wait-ConnectExit |
| 54 | P2 | world-readable-client-bundle-server-tree | FIXED | strips server/ |
| 55 | P2 | ensure-tunnel-log-parity | UNKNOWN | not deep |
| 56 | P2 | ensure-recent-success-mac-absent | UNKNOWN | partial |
| 57 | P2 | controlmaster-asymmetry | OPEN | by design asym |
| 58 | P2 | clear-mount-down-log-level | UNKNOWN | not deep |
| 59 | P2 | post-disconnect-layout-parity | UNKNOWN | not deep |
| 60 | P2 | session-double-onfolder-check | OPEN | likely remains |
| 61 | P2 | local-day-log-no-size-cap | FIXED | CONNECT_LOG_MAX_BYTES |
| 62 | P2 | weak-assert-true | FIXED | real asserts |
| 63 | P2 | win-pushconf-ok-without-result | FIXED | hasResult gate |
| 64 | P2 | update-tests-miss-fail-exit | FIXED | fail-exit tests |
| 65 | P2 | bat-unbounded-relaunch | UNKNOWN | watch |
| 66 | P2 | mac-agent-home-false-positive-vs-win | OPEN | leftover risk |
| 67 | P2 | trusted-already-mounted-skips-hide | FIXED | hide before return |
| 68 | P2 | mount-load-global-no-cr-strip | FIXED | CR strip |
| 69 | P2 | claude-md-no-unconditional-runas-lie | FIXED | AdminFix docs |
| 70 | P1 | persian-quit-designer-win | FIXED | useVk + comment |
| 71 | P1 | persian-quit-connect-design | FIXED | no KeyChar OR Key Q |
| 72 | P1 | concurrent-watermark-server-duplication | FIXED | sync lock |
| 73 | P1 | warn-sync-storm-amplifies-ram | OPEN | tied to #15 |
| 74 | P0 | hardcoded-sepidz-sudo-in-deploy-bundles | FIXED | no sepidz@Admin |
| 75 | P0 | mac-recover-quote-mangle | FIXED | single sshx |
| 76 | P0 | mac-tunnel-wait-4-vs-win-12 | FIXED | seq 1 12 |
| 77 | P1 | banner-miss-tcp-softfail-never-drops | FIXED | budget DROP |
| 78 | P1 | ensure-reuses-zombie-on-banner-miss | FIXED | action=reseed |
| 79 | P1 | editor-seen-sticky-skips-mount-clear | FIXED | EDITOR_SEEN_CLEAR |
| 80 | P1 | win-sticky-forces-editorOpened | FIXED | no sticky force |
| 81 | P1 | mac-abort-no-clear-active-mount | FIXED | --clear |
| 82 | P1 | mac-post-recover-pid-only | FIXED | tunnel_up/banner |
| 83 | P1 | mac-fallthrough-skips-recovery-policy | FIXED | action=r before handler |
| 84 | P1 | win-softfail-budget-no-hard-return | FIXED | hard return ≥6 |

### Rollup

| Bucket | Count |
|--------|------:|
| FIXED | ~68 |
| OPEN | ~12 (incl. P0 #15 + P1/P2 residuals) |
| UNKNOWN | ~8 |
| **Total slugs** | **84** |

---

## Notes for parent / user

- Live host migration (oauth.env chmod, sepidz authorized_keys cleanup, golden 0600) still needs **deploy** — out of scope; code-only FIXED does not equal hosts fixed.
- Parallel agents overwrote P0s earlier; `LOCK-VERIFY` / `LOCK-STATUS` are the best post-lock signals.
- Next fix priority: **#15** (stream log sync), then **#22** banner list parity, then HEARTBEAT/#51 resource storms.
