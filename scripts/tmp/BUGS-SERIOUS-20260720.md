# Connect / Claude-Code-Server â€” Serious bugs (multi-agent, confidence â‰¥4)

Date: 2026-07-20  
Method: 10 parallel agents; only items with confidence â‰¥4 kept; duplicates merged.  
Scope: client + server mount/auth/deploy (not style nits).

Legend: **P0** = data loss / security / silent wrong behavior; **P1** = serious reliability/UX; **P2** = important debt.

---

## P0 (must fix)

| # | Slug | Area | Conf | Problem |
|---|------|------|------|---------|
| 1 | `hardcoded-sepidz-sudo-fallback` | security | 5 | `Get-DeployCredentials.ps1` falls back to hardcoded Sepidz sudo if local file missing |
| 2 | `sepidz-ak-merge-plus-nopasswd-bundle` | security | 5 | Every user key merged into `sepidz` + NOPASSWD install-client-bundle â†’ root install via any laptop key |
| 3 | `shared-oauth-in-etc-environment` | security | 5 | `CLAUDE_CODE_OAUTH_TOKEN` in `/etc/environment` mode 644 â€” any local user can read |
| 4 | `sqlserver-password-in-add-user-template` | security | 5 | SQL password embedded in every new `~/.claude/settings.json` (+ docs) |
| 5 | `win-restore-deletes-git` | mount | 5 | Windows `restore_try` `Remove-Item .git` when both `.git` and `.git.server-session` exist â€” can destroy real git |
| 6 | `watchdog-tunnel-down-no-git-restore` | mount | 5 | Watchdog umounts on tunnel DOWN without restoring `.git` from `.git.server-session` |
| 7 | `mac-pushconf-or-true-dead-fail` | parity/silent | 5 | `|| true` makes PushConf always â€œokâ€; fail path unreachable |
| 8 | `designer-pushconf-empty-no-clear` | parity | 5 | Designer `ActiveMount ''` does not clear; stale ACTIVE_MOUNT |
| 9 | `update-exit0-on-error` | update/silent | 5 | Failed client update logs ERROR then exit 0 â€” looks up-to-date |
| 10 | `win-partial-apply-no-rollback` | update | 5 | Partial Copy-Item then â€œusing local copyâ€ without rollback â†’ mixed versions |
| 11 | `ssh-trailing-true-masks-append-fail` | logging | 5 | Remote `; true` â†’ watermark advances even if `cat >>` failed â†’ permanent log loss |
| 12 | `mac-scp-ok-without-cat-advances-watermark` | logging | 5 | Mac advances sync offset after scp even if sshx/cat fails |
| 13 | `win-auth-skip-ignores-golden-rotation` | auth | 5 | Windows never checks golden-synced-at; can skip auth while tokens rotate |
| 14 | `mac-o-key-dead-when-sticky-opened` | auth | 5 | Mac O handler blocked when `_editor_opened=1` after failed relaunch |
| 15 | `log-sync-readallbytes-full-file` | resource | 5 | Full day log ReadAllBytes every sync â†’ RAM spike |

---

## P1 (serious)

| # | Slug | Area | Conf | Problem |
|---|------|------|------|---------|
| 16 | `always-elevated-connect` | security | 5 | Entire connect session always Admin (UAC + attack surface) |
| 17 | `administrators-authorized-keys-server-key` | security | 5 | Server key in `administrators_authorized_keys` (from=loopback mitigates) |
| 18 | `cursor-golden-world-readable` | security | 5 | Golden auth.json 644 under `/etc/cursor-auth` |
| 19 | `secrets-adjacent-logging` | security | 4 | Token fingerprint in world-readable log; diagnose pulls private key; sudo echo in cmdline |
| 20 | `active-mount-first-conf-inference` | mount | 5 | Empty ACTIVE_MOUNT â†’ first alphabetical conf written as active |
| 21 | `git-hide-worktree-file-unhandled` | mount | 4 | Worktree `.git` file not skipped despite comments |
| 22 | `mac-banner-false-accept-linux` | mount | 4 | Mac banner check accepts generic OpenSSH Linux as Mac |
| 23 | `scm-policy-never-reenabled` | mount | 4 | hideâ†’server leaves `git.enabled:false` stuck |
| 24 | `foreign-session-ss-false-stale-clear` | mount | 4 | `ss` fail â†’ live=0 â†’ deletes connect conf while tunnel up |
| 25 | `win-softfail-budget-no-drop` | tunnel/parity | 5 | After 6 soft_fails Win never DROP; Mac does |
| 26 | `designer-design-key-or-vk` | ux | 5 | Designer/design still KeyChar OR Key â€” Persian false triggers |
| 27 | `clear-mount-reason-mac-missing` | parity | 5 | Mac CLEAR_MOUNT has no Reason= |
| 28 | `non-atomic-live-copy-item` | update | 5 | In-place Copy-Item/cp mid-update tears package |
| 29 | `copy-errors-swallowed` | update | 5 | Copy failures not in `$failed`; can still `applied_ok` |
| 30 | `no-checksum-after-scp` | update | 5 | No hash verify after bundle download |
| 31 | `deploy-client-bundle-rm-live` | update | 5 | `rm -rf` live bundle during deploy â†’ race for clients |
| 32 | `identityagent-gap-on-client-update` | update | 4 | Client update SSH lacks IdentityAgent=none (deploy has it) |
| 33 | `mac-update-hang-no-process-timeout` | update | 4 | Mac update ssh/scp no process kill timeout |
| 34 | `publish-manifest-utf8-bom` | update | 4 | PS5.1 UTF8 BOM breaks first manifest line |
| 35 | `docs-temp-log-lie` | docs/silent | 5 | Docs say temp wipe; code keeps durable day logs |
| 36 | `trace-debug-skip-sync-trigger` | logging | 5 | TRACE tunnel diagnostics never sync until session end |
| 37 | `midnight-rollover-abandons-unsynced-day` | logging | 5 | Day rollover without flushing previous file |
| 38 | `mac-tail-cmdsubst-wc-watermark-loss` | logging | 5 | bash `$(tail)` strips newlines; watermark over-advances |
| 39 | `sshx-swallow-callers` | silent | 4 | Hot-path `SshX â€¦ \| Out-Null` ignores failures |
| 40 | `update-server-exit0-on-verify-fail` | silent | 5 | `update-server.sh` always â€œcompleteâ€ even if verify fails |
| 41 | `missing-pushconf-quoting-e2e` | silent | 5 | No e2e for the bug that caused Farzad elif storm |
| 42 | `auth-relaunch-unused-when-already-on-folder` | auth | 5 | Auth sync wonâ€™t soft-stop Cursor if already on folder |
| 43 | `mac-auth-relaunch-on-skipped-failure` | auth | 5 | `skipped` auth still sets AUTH_RELAUNCH kill |
| 44 | `win-code-no-isolated-profile` | auth | 5 | VS Code on Win lacks ClaudeServerCodeProfile |
| 45 | `win-needs-refresh-misses-machineid-file` | auth | 4 | machineid file drift doesnâ€™t force refresh |
| 46 | `win-build-auth-early-path-drops-auth-json-metadata` | auth | 4 | Early merge drops email/stripe fields |
| 47 | `heartbeat-explain-log-growth` | resource | 5 | 30s HEARTBEAT dumps all Cursor cmdlines â†’ huge day log |
| 48 | `session-cim-cache-no-ttl` | resource | 5 | Editor CIM cache never expires â†’ stale open/closed |
| 49 | `log-sync-ssh-kill-orphans` | resource | 4 | Timed-out log-sync ssh/scp not reaped |
| 50 | `start-job-scp-orphan-on-timeout` | resource | 4 | Stop-Job leaves native scp child |
| 51 | `tunnel-softfail-cim-reattach-storm` | resource | 4 | Soft-fail path CIM-scans all ssh.exe every ~800ms |
| 52 | `designer-no-single-instance-mutex` | ux | 5 | Designer lacks connect lock â†’ fights main connect |
| 53 | `wait-connect-exit-before-ui` | ux | 4 | Early Wait-ConnectExit/UAC before UI ready |

---

## P2 (important)

| # | Slug | Area | Conf | Problem |
|---|------|------|------|---------|
| 54 | `world-readable-client-bundle-server-tree` | security | 5 | Bundle includes server scripts world-readable |
| 55 | `ensure-tunnel-log-parity` | parity | 5 | Mac ENSURE almost silent |
| 56 | `ensure-recent-success-mac-absent` | parity | 4 | Mac lacks 5s recent_success reuse |
| 57 | `controlmaster-asymmetry` | parity | 4 | Mac mux stale risk; Win no mux |
| 58 | `clear-mount-down-log-level` | parity | 5 | Mac CLEAR down DEBUG vs Win INFO |
| 59 | `post-disconnect-layout-parity` | parity | 4 | Mac ASCII-only post menu under Persian |
| 60 | `session-double-onfolder-check` | resource | 5 | Double folder test every 2s |
| 61 | `local-day-log-no-size-cap` | resource | 5 | No max size on day log |
| 62 | `weak-assert-true` | silent | 4 | Vacuous Assert $true in tests |
| 63 | `win-pushconf-ok-without-result` | silent | 4 | Exit 0 without PUSH_CONF_RESULT still deduped as ok |
| 64 | `update-tests-miss-fail-exit` | silent | 4 | Tests never assert ERRORâ†’nonzero exit |
| 65 | `bat-unbounded-relaunch` | update | 3* | connect.bat recursion on exit 2 (conf 3 â€” watch) |
| 66 | `mac-agent-home-false-positive-vs-win` | auth | 4 | Mac kills more aggressively on URI-less window |
| 67 | `trusted-already-mounted-skips-hide` | mount | 3* | Trusted tunnel early return may skip re-hide |
| 68 | `mount-load-global-no-cr-strip` | mount | 4 | CRLF in TUNNEL_PORT breaks mount (watchdog strips, mount doesnâ€™t) |
| 69 | `claude-md-no-unconditional-runas-lie` | docs | 5 | CLAUDE.md contradicts always-elevate |

\* conf 3 listed for completeness; treat as P2 candidates pending re-verify.

---

## Already fixed in main `.31` (do not re-count as open)

- Main Win/Mac Persian quit / useVk gating for session keys  
- Main PushConf base64 + RESULT (Win); Mac still has `|| true` (#7)  
- Dual-instance mutex on main connect  

Still broken on **designer / connect-design** forks (#8, #26, #52).

---

## Counts

| | Count |
|--|------:|
| P0 open | 15 |
| P1 open | 38 |
| P2 open | ~14 |
| **Total listed** | **~67** |
| Confidence â‰¥5 | majority of P0/P1 |
| Professor â€œâ‰¥50 seriousâ€ | **Supported** by this inventory |

---

## Agents

- tunnel â€” completed ([Tunnel session bugs](174fa2c0-eab1-4719-99f8-6f3a33ab60a4))  
- logging, update, auth, mount, security, parity, resource, ux, silent â€” completed  


---

## Addendum (agents completed after first merge)

| # | Slug | Area | Conf | Problem |
|---|------|------|------|---------|
| 70 | `persian-quit-designer-win` | ux | 5 | Designer still default action=q + always-VK Ã¢â‚¬â€ Persian Ã˜Â¶ disconnects |
| 71 | `persian-quit-connect-design` | ux | 5 | connect-design.ps1 KeyChar OR Key -eq Q under Persian |
| 72 | `concurrent-watermark-server-duplication` | logging | 4 | Overlapping syncs / offset reset re-ships bytes Ã¢â€ â€™ duplicate server log |
| 73 | `warn-sync-storm-amplifies-ram` | resource | 4 | WARN path triggers full ReadAllBytes + 3 SSH under flap |
| 74 | `hardcoded-sepidz-sudo-in-deploy-bundles` | security | 5 | Also `deploy-client-bundles.ps1` fallback `sepidz@Admin` if sudo pw missing |

Agents fully landed: [security](80b6791b), [parity](2c2976a2), [resource](332a6b53), [logging](9edf1cea), [auth](5e75497b), [mount](efccd90d), [update](9481c125), [ux](0a5a974e), [silent](0df5937f).

Updated total open serious Ã¢â€°Ë† **70+**.

### Tunnel/session ([Tunnel session bugs](174fa2c0-eab1-4719-99f8-6f3a33ab60a4))

| # | Slug | Sev | Conf | Problem |
|---|------|-----|------|---------|
| 75 | `mac-recover-quote-mangle` | P0 | 5 | Mac `recover_mounts_if_needed` quote-mangles remote cmd; fallbacks call missing server `sshx`; UI still says Recover done |
| 76 | `mac-tunnel-wait-4-vs-win-12` | P0 | 5 | Mac tunnel wait loops 4Ã— while UI says N/12; Win waits 12 â€” spurious tunnel-up fail on Mac |
| 77 | `banner-miss-tcp-softfail-never-drops` | P1 | 5 | `banner_miss_tcp_open` never budgets/DROPs â€” zombie forward looks healthy forever |
| 78 | `ensure-reuses-zombie-on-banner-miss` | P1 | 5 | Ensure returns success / TUNNEL_REUSED on banner miss + TCP open |
| 79 | `editor-seen-sticky-skips-mount-clear` | P1 | 5 | After editor closed, sticky EditorSeenOpen still skipRecoveryClear â†’ stale mount preserved |
| 80 | `win-sticky-forces-editorOpened` | P1 | 5 | Win forces editorOpened=true from sticky even when not on-folder |
| 81 | `mac-abort-no-clear-active-mount` | P1 | 5 | Mac abort clears local ACTIVE_MOUNT_ID but PushConf without --clear |
| 82 | `mac-post-recover-pid-only` | P1 | 5 | Mac post-recover checks PID only; Win checks Test-TunnelUp banner |
| 83 | `mac-fallthrough-skips-recovery-policy` | P1 | 4 | Mac fallthrough `r` can skip preserve/clear recovery block |
| 84 | `win-softfail-budget-no-hard-return` | P1 | 4 | Win soft_fail â‰¥6 does not hard-return unlike Mac TUNNEL_DROP |

Updated open serious â‰ˆ **80+** (was ~70+). Tunnel agent complete.

