# REVIEW — Cross-agent gaps, conflicts, completeness

**Date:** 2026-07-20  
**Method:** `laptop-exec -p claude-code-server` only (git diff --stat, hot-file hunks, pattern rg, line slices)  
**Against:** `scripts/tmp/BUGS-SERIOUS-20260720.md` slugs 1–84  
**Harsh verdict:** **DO NOT DEPLOY.** Working tree is a half-merged multi-agent storm. Several “fixes” re-introduce or paper over the original bugs. Agent deliverables mostly absent.

---

## 0. Working tree snapshot

```
47 files changed, 5077 insertions(+), 898 deletions(-)
```

Hottest overlap (by diff size — concurrent-edit risk):

| File | Δ | Owned by (FIX-PLAN) | Also touched by |
|------|---|---------------------|-----------------|
| `scripts/client/git-mode.sh` | +822 | Agent 4 (Tunnel-Mac) | 5 logging, 7 auth, 2 mount helpers |
| `scripts/client/git-mode.ps1` | +504 | Agent 3 (Tunnel-Win) | 5, 7, 2 |
| `scripts/client/connect-ui.ps1` | +417 | Agent 5 / 9 | Update agent (watermark copy) |
| `scripts/client/windows/connect.ps1` | +382 | Agent 3 + 7 + 8 | sticky vs clear vs auth |
| `scripts/client/windows/connect-update.ps1` | +353 | Agent 6 | 5 (log flush), 9 (ReadAllBytes) |
| `scripts/client/mac/connect.sh` | +320 | Agent 4 | 7 AUTH_RELAUNCH, sticky |
| `scripts/server/cursor-hooks/laptop-exec-guard.sh` | +284 | (out of plan) | — |
| `scripts/server/claude-watchdog.sh` | +211 | Agent 2 | — |
| `scripts/server/laptop-exec.sh` | +199 | (out of plan) | — |

Tunnel was briefly DOWN mid-review (`Connection refused` on 21002); rechecked UP. Prefer `-p` always (active_mount flipped to `<none>` during review).

---

## 1. FIX-AGENT-*.md / REVIEW-*.md under `scripts/tmp/`

### FIX-AGENT-*.md

**NONE.** Plan (`FIX-PLAN-20260720.md`) required `scripts/tmp/FIX-AGENT-<N>.md` for agents 1–10.  
Zero files match `FIX-AGENT*.md`.

Only plan file present:

- `FIX-PLAN-20260720.md` (1955 bytes) — ownership table only

### REVIEW-*.md (present at review time)

| File | Size | Notes |
|------|------|-------|
| `REVIEW-TUNNEL.md` | 10205 | Independent tunnel review: **0/12 PASS** for 7,25,75–84 |
| `REVIEW-LOGGING-AUTH.md` | 13752 | Logging+auth: watermark/`; true` still FAIL |
| `REVIEW-GAPS-CONFLICTS.md` | (this file) | Cross-agent merge risk |

No `REVIEW-SECURITY.md`, `REVIEW-MOUNT.md`, `REVIEW-UPDATE.md`, `REVIEW-UX.md`, etc.

**Implication:** Fix agents either did not finish, did not write reports, or were still mid-edit when reviews ran. Treat claimed “fixed” status as **unproven** unless code evidence below says otherwise.

---

## 2. Conflict / race risks (evidence-based)

### C1 — Mac tunnel wait: **12 → 4 REGRESSION** (Agent 4 vs bug #76)

Diff hunk (current tree):

```diff
-    for i in $(seq 1 12); do
+    for i in $(seq 1 4); do
```

in **both** `wait_for_tunnel_up` and `poll_tunnel_with_progress` (`git-mode.sh`).

Win still waits **12** (`Wait-ForTunnelUp` `for ($i = 1; $i -le 12)`).  
Mac UI still prints `Tunnel check %d/12` while looping only 4 times — **internal contradiction** in the same function.

**Race read:** Someone “sped up” Mac wait while slug #76 explicitly requires parity with Win 12. This is not a partial fix; it **cements** the bug (and lies to the user about N/12).

### C2 — PushConf: RESULT plumbing + dead fail path (Agent 4 half-fix)

Same edit added:

- base64 remote body + `PUSH_CONF_RESULT`
- `push_ec` check / ERROR log / `return $push_ec`

**and left:**

```bash
push_out="$(sshx "echo $b64 | base64 -d | bash" 2>/dev/null || true)"
push_ec=$?
```

`|| true` forces `push_ec=0` always → fail path **unreachable**. Classic “fix + keep the mask” conflict inside one function. Slug #7 still FAIL.

Win side: `ClearActiveMount` switch + RESULT parsing looks real; Mac lagging with a broken fail gate.

### C3 — Sticky editor: clear intent vs force-open (Agent 3)

`connect.ps1` still:

```powershell
} elseif ($script:EditorSeenOpen) {
    $editorOpened = $true
}
...
$skipRecoveryClear = [bool]($editorOpened -or $script:EditorSeenOpen)
...
if ($skipRecoveryClear) {
    $editorOpened = $true
    $script:EditorSeenOpen = $true
```

Comments mention “Sticky safety evidence…” while recovery still **forces** `editorOpened` from sticky and skips mount clear (#79/#80). Any agent that added “clear sticky on close” did not win; force path still dominates.

### C4 — SoftFailCount theater (Agent 3 vs Agent 4)

Win (`git-mode.ps1`):

- Increments `TunnelSoftFailCount` for `no_proc_tcp_open`
- If `< 6` → `return $true`
- If `≥ 6` → **falls through** with **no** `TUNNEL_DROP` log and no hard `return $false` for that reason
- `banner_miss_tcp_open` path: logs soft_fail then **`$script:TunnelSoftFailCount = 0`** and stays healthy

Mac (`git-mode.sh`): **does** `TUNNEL_DROP` + budget for `no_ssh_proc_tcp_open` at ≥6 — Win parity claim in FIX-PLAN is false.

Agents added soft_fail **logging** (looks fixed in greps) while **resetting** the budget on banner-miss — opposite of #77/#84 intent.

### C5 — Mac recover quote-mangle still live (Agent 4)

```bash
timeout 30 sshx "$CM recover-one '$id' 2>/dev/null || timeout 30 sshx "$CM recover-if-needed '$id' 2>/dev/null || timeout 30 sshx "$CM recover" 2>/dev/null || true
```

Nested `sshx` inside the remote fragment; first quote closes early; UI always prints “Recover done”. #75 FAIL. Diff churn elsewhere in git-mode.sh did not fix this line.

### C6 — Duplicate push of same hook file

`git-mode.sh` `initialize_server_session` (diff):

```bash
push_remote_file_if_changed ".../laptop-exec-session.sh" ...
push_remote_file_if_changed ".../laptop-exec-session.sh" ...  # duplicate
```

Looks like two agents pasted the same line. Harmless but proves uncoordinated edits.

### C7 — Designer fork abandoned (Agent 8 missing)

Designer still:

- `Push-ServerConnectConf -ActiveMount ''` (empty string, not `-ClearActiveMount`) — #8
- `KeyChar -or Key` Persian false triggers — #26/#70
- No single-instance mutex — #52

Main connect got mutex / ClearActiveMount / VK gating; designer did not. Cross-product skew.

### C8 — Logging “chunked ReadAllBytes” ≠ fix (#15 / Agent 9)

`connect-ui.ps1` still:

```powershell
$all = [System.IO.File]::ReadAllBytes($script:ConnectLogPath)
```

then copies a 512KB chunk. **Full file still loaded into RAM** every sync. Cap only limits scp size, not the ReadAllBytes spike. Partial “fix” that leaves the P0 resource bug.

Remote append still ends with `; true` (#11) — `$catRes.Ok` can be true when `cat >>` failed.

### C9 — Mount P0 untouched while client churns

`claude-mount.sh` `restore_try` **still**:

```powershell
if (Test-Path $p/.git) { Remove-Item $p/.git -Force -ErrorAction SilentlyContinue }
```

Watchdog on tunnel DOWN: umount all sshfs, **no** `.git.server-session` restore (#5/#6). Mount agent deliverable absent; client agents did not own these files so P0 git-loss paths remain while 5k LOC of tunnel cosmetics land.

### C10 — Security: some PASS, inventory not updated

`publish/Get-DeployCredentials.ps1` now **throws** if Sepidz sudo missing — “No hardcoded fallback is allowed.”  
`add-user.sh` SQL password template is `CHANGE_ME` (was `Mohammad123` in original inventory — **may be fixed or mid-edit**).

OAuth still documented/used via `/etc/environment` (#3). Golden `chmod 644` still in import path (#18). Do not treat security as done without Agent 1 report.

---

## 3. Slugs still FAIL in tree (pattern + line evidence)

Legend: **FAIL** = bad pattern/behavior still present · **PARTIAL** = code moved but bug class remains · **PASS?** = looks fixed, no FIX-AGENT proof · **UNVERIFIED** = not re-probed this pass (assume open unless proven)

### P0 (1–15)

| # | Slug | Status | Evidence |
|---|------|--------|----------|
| 1 | `hardcoded-sepidz-sudo-fallback` | **PASS?** | `Get-DeployCredentials.ps1` throws; no `sepidz@Admin` rg hit |
| 2 | `sepidz-ak-merge-plus-nopasswd-bundle` | **UNVERIFIED** | install.sh still mentions NOPASSWD client-deploy; needs Agent 1 proof |
| 3 | `shared-oauth-in-etc-environment` | **FAIL** | add-user/diagnose/update-server still `/etc/environment` token model |
| 4 | `sqlserver-password-in-add-user-template` | **PARTIAL** | now `CHANGE_ME` not real pw — still embeds password field in every user settings |
| 5 | `win-restore-deletes-git` | **FAIL** | `claude-mount.sh` `restore_try` still `Remove-Item $p/.git` |
| 6 | `watchdog-tunnel-down-no-git-restore` | **FAIL** | watchdog umount-only on `! tunnel_up`; no restore |
| 7 | `mac-pushconf-or-true-dead-fail` | **FAIL** | `sshx ... \|\| true` then check `$push_ec` |
| 8 | `designer-pushconf-empty-no-clear` | **FAIL** | designer `Push-ServerConnectConf -ActiveMount ''` |
| 9 | `update-exit0-on-error` | **FAIL** | `connect-update.ps1`: ERROR then `exit 0` (ssh_missing, manifest_empty, …) |
| 10 | `win-partial-apply-no-rollback` | **FAIL** | incomplete → “using local copy”; no rollback of partial Copy-Item |
| 11 | `ssh-trailing-true-masks-append-fail` | **FAIL** | `$cat = '...; true'` in connect-ui.ps1 / .sh |
| 12 | `mac-scp-ok-without-cat-advances-watermark` | **FAIL** | see REVIEW-LOGGING-AUTH; watermark after soft-fail ssh |
| 13 | `win-auth-skip-ignores-golden-rotation` | **FAIL** | REVIEW-LOGGING-AUTH: outer skipAuth bypasses golden stamp |
| 14 | `mac-o-key-dead-when-sticky-opened` | **UNVERIFIED** | sticky still sticky; O-path not re-sliced this pass |
| 15 | `log-sync-readallbytes-full-file` | **FAIL** | full `ReadAllBytes` then 512KB chunk |

### P1 (16–53) — high-confidence FAILs from this pass

| # | Slug | Status | Note |
|---|------|--------|------|
| 16 | `always-elevated-connect` | **PARTIAL?** | AdminFix path exists; inventory claimed always-admin — re-verify session elevation policy |
| 20 | `active-mount-first-conf-inference` | **FAIL** | watchdog `_infer_active` when ACTIVE_MOUNT empty |
| 25 | `win-softfail-budget-no-drop` | **FAIL** | SoftFail≥6 no TUNNEL_DROP (Mac does DROP) |
| 26 | `designer-design-key-or-vk` | **FAIL** | designer KeyChar OR Key |
| 31 | `deploy-client-bundle-rm-live` | **FAIL** | `rm -rf "$BUNDLE_ROOT"` in deploy-client-bundle.sh |
| 35 | `docs-temp-log-lie` | **UNVERIFIED** | docs churn large; not re-audited |
| 39 | `sshx-swallow-callers` | **FAIL** | widespread `SshX … \| Out-Null` / `\|\| true` |
| 40 | `update-server-exit0-on-verify-fail` | **FAIL** | always prints “Update complete.” |
| 47 | `heartbeat-explain-log-growth` | **UNVERIFIED** | |
| 52 | `designer-no-single-instance-mutex` | **FAIL** | mutex only on main connect |

### Tunnel addendum (75–84) — all still FAIL

| # | Slug | Status | Smoking gun |
|---|------|--------|--------------|
| 75 | `mac-recover-quote-mangle` | **FAIL** | nested sshx + always “Recover done” |
| 76 | `mac-tunnel-wait-4-vs-win-12` | **FAIL** | **regressed** 12→4 in diff; UI still /12 |
| 77 | `banner-miss-tcp-softfail-never-drops` | **FAIL** | soft_fail log + SoftFailCount=0 |
| 78 | `ensure-reuses-zombie-on-banner-miss` | **FAIL** | ENSURE soft_fail banner_miss path |
| 79 | `editor-seen-sticky-skips-mount-clear` | **FAIL** | skipRecoveryClear ← EditorSeenOpen |
| 80 | `win-sticky-forces-editorOpened` | **FAIL** | `elseif (EditorSeenOpen) { editorOpened=$true }` |
| 81 | `mac-abort-no-clear-active-mount` | **FAIL** | `ACTIVE_MOUNT_ID=""` then `push_server_connect_conf` w/o `--clear` (connect.sh ~651–760) |
| 82 | `mac-post-recover-pid-only` | **FAIL** | (per REVIEW-TUNNEL; not re-sliced) |
| 83 | `mac-fallthrough-skips-recovery-policy` | **FAIL** | (per REVIEW-TUNNEL) |
| 84 | `win-softfail-budget-no-hard-return` | **FAIL** | same as #25 |

### Known-bad pattern checklist (user request)

| Pattern | Still present? | Where |
|---------|----------------|-------|
| `\|\| true` near PushConf | **YES** | `git-mode.sh` push_out=sshx … \|\| true |
| SoftFailCount without DROP | **YES (Win)** | git-mode.ps1 banner_miss resets; ≥6 no DROP |
| `Remove-Item .git` | **YES** | claude-mount.sh restore_try |
| `; true` log append | **YES** | connect-ui.ps1/sh cat cmd |
| `sepidz@Admin` | **NO hit** | likely fixed in Get-DeployCredentials |
| `ReadAllBytes` | **YES** | connect-ui.ps1 + connect-update.ps1 |
| `seq 1 4` tunnel wait | **YES** | git-mode.sh wait + poll |
| `ActiveMount ''` | **YES** | designer connect.ps1 (main uses `-ClearActiveMount`) |

---

## 4. Approximate scorecard

| Bucket | Approx |
|--------|--------:|
| Clearly still FAIL (this pass) | **~35+** including all of 75–84, most P0 logging/mount/update |
| PASS? / likely fixed | **~2–4** (sudo fallback #1/#74 area; SQL literal #4 softened) |
| UNVERIFIED / assume open | rest of 1–84 |
| FIX-AGENT reports filed | **0 / 10** |

Professor bar (≥50 serious): **still supported** — inventory not retired by this tree.

---

## 5. Recommended merge / order before user deploy approval

**Gate:** No deploy / publish / `claude-server install` until green below.

### Phase A — STOP the bleeding (serialize hot files)

1. **Freeze** concurrent writes to: `git-mode.sh`, `git-mode.ps1`, `connect.ps1`, `connect.sh`, `connect-ui.*`, `claude-mount.sh`, `claude-watchdog.sh`, `connect-update.ps1`.
2. Require every agent to land **`FIX-AGENT-N.md`** or mark CANCELLED with reason.
3. Re-run `git diff --stat`; if two agents claim same file without coordination, **rebase onto one owner**.

### Phase B — P0 order (must ship before anything cosmetic)

| Order | Slugs | Owner | Why first |
|------:|-------|-------|-----------|
| 1 | 5, 6 | Mount | Data loss (delete .git / hide left behind) |
| 2 | 7, 81 | Tunnel-Mac | Silent wrong ACTIVE_MOUNT / dead PushConf fail |
| 3 | 11, 12, 15 | Logging+Resource | Server log loss + RAM; ops blind |
| 4 | 9, 10 | Update | Mixed client versions in the wild |
| 5 | 1–4, 74 | Security | Confirm throw paths; oauth/golden still open |

### Phase C — Tunnel correctness (before UX)

| Order | Slugs | Action |
|------:|-------|--------|
| 6 | **76** | Revert Mac `seq 1 4` → **12**; stop printing /12 while looping 4 |
| 7 | 75 | One remote chain, no nested `sshx`; fail UI if recover fails |
| 8 | 25, 77, 78, 84 | Win: SoftFail≥6 → TUNNEL_DROP + `return $false`; banner_miss must budget, not reset |
| 9 | 79, 80 | Clear sticky when editor not on-folder; never force `editorOpened` from sticky alone |
| 10 | 82, 83 | Mac post-recover banner check; fallthrough must hit recovery policy |

### Phase D — Fork parity + debt

11. Designer/design: #8, #26, #52, #70, #71 (copy ClearActiveMount + useVk + mutex)  
12. Remaining P1/P2 from inventory with FIX-AGENT evidence  
13. Tests: kill `Assert $true` (#62); add PushConf fail e2e (#41); update exit nonzero (#64)

### Phase E — Approval checklist (user)

```
[ ] All FIX-AGENT-1..10.md present OR explicit skip list
[ ] rg clean: Remove-Item .git (restore), seq 1 4, PushConf || true, cat ...; true, ActiveMount ''
[ ] Win SoftFail≥6 emits TUNNEL_DROP and returns false
[ ] Mac wait loops == 12 and matches UI
[ ] Watchdog restores .git.server-session before/with umount on tunnel DOWN
[ ] connect-update ERROR → nonzero exit
[ ] REVIEW-TUNNEL + REVIEW-LOGGING-AUTH re-run → PASS
[ ] User explicit deploy approval
```

---

## 6. Bottom line

Agents produced **thousands of lines** of overlapping edits and **zero** FIX-AGENT reports. Worst conflict signature: **cosmetic/partial patches that preserve the failure mode** (`|| true` + fail check; soft_fail log + budget reset; ReadAllBytes + chunk cap; wait UI /12 with `seq 1 4`).

**Deploy approval: REJECT** until Phase B+C green and agent reports exist.
