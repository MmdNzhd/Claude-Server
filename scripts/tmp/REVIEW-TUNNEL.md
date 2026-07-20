# DEEP REVIEW - Tunnel/session fixes (harsh)

**Date:** 2026-07-20  
**Scope:** CURRENT `scripts/client/{windows/connect.ps1,git-mode.ps1,mac/connect.sh,git-mode.sh}`  
**Against:** BUGS-SERIOUS-20260720.md slugs 25, 7, 75-84 (+ verify questions)  
**FIX-AGENT-3.md / FIX-AGENT-4.md:** **MISSING** (not present under `scripts/tmp/`)  
**Verdict:** **BLOCK** - Agent 3/4 deliverables absent; core P0/P1 tunnel bugs still live in tree.

Evidence gathered via `laptop-exec -p claude-code-server` reads of the four client files (not SSHFS).

---

## Executive punch list

| # | Slug | Status | One-line |
|---|------|--------|----------|
| 75 | `mac-recover-quote-mangle` | **FAIL** | Line still quote-mangles; nested `sshx` in remote fragment; UI always "Recover done" |
| 76 | `mac-tunnel-wait-4-vs-win-12` | **FAIL** | `seq 1 4` in both wait helpers; UI lies with `N/12` |
| 77 | `banner-miss-tcp-softfail-never-drops` | **FAIL** | Win+Mac: log soft_fail, reset/ignore budget, return healthy |
| 78 | `ensure-reuses-zombie-on-banner-miss` | **FAIL** | Ensure returns success + reused on banner miss + TCP open |
| 79 | `editor-seen-sticky-skips-mount-clear` | **FAIL** | Sticky never cleared on editor close -> skipRecoveryClear |
| 80 | `win-sticky-forces-editorOpened` | **FAIL** | `elseif ($script:EditorSeenOpen) { $editorOpened = $true }` |
| 81 | `mac-abort-no-clear-active-mount` | **FAIL** | Abort: `ACTIVE_MOUNT_ID=""` then `push_server_connect_conf` **without** `--clear` |
| 82 | `mac-post-recover-pid-only` | **FAIL** | Post-recover: `_tunnel_alive` (PID) vs Win `Test-TunnelUp` |
| 83 | `mac-fallthrough-skips-recovery-policy` | **FAIL** | Fallthrough sets `_action=r` then `continue` - **skips** `if r` policy block |
| 84 | `win-softfail-budget-no-hard-return` | **FAIL** | SoftFail>=6: no `return $false` / no `TUNNEL_DROP` |
| 25 | `win-softfail-budget-no-drop` | **FAIL** | Same root cause as 84 (parity with Mac DROP) |
| 7 | `mac-pushconf-or-true-dead-fail` | **FAIL** | `sshx ... || true` -> `push_ec` always 0; fail path dead |

**PASS count:** 0 / 12 reviewed slugs.

---

## Verification answers (requested)

### 1. Mac `recover_mounts_if_needed` - quote-mangle GONE? Server-side `sshx` in fallback?

**FAIL - still mangled. Nested `sshx` still present.**

`git-mode.sh:1004`:

```
timeout 30 sshx "$CM recover-one '$id' 2>/dev/null || timeout 30 sshx "$CM recover-if-needed '$id' 2>/dev/null || timeout 30 sshx "$CM recover" 2>/dev/null || true
```

Quote parse (first `sshx "..."` closes early):

- Remote fragment 1 becomes: `$CM recover-one '$id' 2>/dev/null || timeout 30 sshx `
- Remaining tokens run **on the laptop** as another `timeout 30 sshx "$CM recover-if-needed..."` / `sshx "$CM recover"`.
- The remote payload still contains the string `sshx` as a fallback operator - which does not exist as a server binary.

Contrast Win `Invoke-RecoverIfNeeded` (correct single remote chain, no nested sshx):

`SshX "timeout 30 $CM recover-one ... || timeout 30 $CM recover-if-needed ... || timeout 30 $CM recover ... || true"`

UI always prints Recover done regardless of exit - false confidence.

### 2. Mac tunnel wait - really 12 loops?

**FAIL - still 4.**

| Function | File:line | Loop |
|----------|-----------|------|
| `wait_for_tunnel_up` | git-mode.sh:887 | `for i in $(seq 1 4)` |
| `poll_tunnel_with_progress` | git-mode.sh:905 | `for i in $(seq 1 4)` |
| Ensure uses | git-mode.sh:1128 | `poll_tunnel_with_progress` |
| UI string | git-mode.sh:914-924 | prints `Tunnel check %d/12` |

Win `Wait-ForTunnelUp` (git-mode.ps1:557): `for ($i = 1; $i -le 12; $i++)` - correct.

Dead code smell: Mac has `if [ "$i" -ge 12 ]; then break` inside a loop that never exceeds 4.

### 3. `banner_miss_tcp_open` - eventually DROP on Win AND Mac?

**FAIL on both - never budgets, never DROPs.**

**Mac** `sync_session_tunnel_forward` (git-mode.sh ~852-857):

- On banner miss + TCP open: log `banner_miss_tcp_open`, leave `_TUNNEL_SYNC_FAIL_COUNT=0`, **do not** bump `_TUNNEL_SOFT_FAIL_COUNT`, fall through -> `return 0`.

**Win** `Sync-SessionTunnelProcess` (git-mode.ps1:505-508):

```
Write-GitModeLog "... reason=banner_miss_tcp_open" 'WARN'
$script:TunnelSyncFailCount = 0
$script:TunnelSoftFailCount = 0   # RESETS budget
# no return $false - falls through to return $true
```

Zombie forward with open TCP + empty/wrong banner looks forever healthy.

### 4. Ensure tunnel - still returns success on banner miss?

**FAIL - yes, both platforms.**

**Mac** `ensure_session_tunnel` (git-mode.sh:1100-1107): soft_fail log -> `TUNNEL_REUSED=1` -> `return 0`.

**Win** `Ensure-SessionTunnel` (git-mode.ps1:870-876): `$TunnelReused.Value = $true` -> `return $true`.

### 5. EditorSeenOpen sticky - cleared when editor closed? Win still force `editorOpened`?

**FAIL - not cleared on close. Win still forces.**

| Event | Clears sticky? |
|-------|----------------|
| Editor process/folder gone (session loop) | **No** - Mac sets `_editor_opened=0` only; Win forces `$editorOpened=$true` if sticky |
| Manual R (`gotKey`) | Win yes (1654); Mac does **not** clear `_editor_seen_open` on manual R (only zeros `_editor_opened`) |
| Q quit | Win yes (1704); Mac session end resets at menu (1089) but not mid-loop on close |

**Win force** (connect.ps1:1556-1561, also 1503-1507): `elseif ($script:EditorSeenOpen) { $editorOpened = $true }`.

Recovery uses sticky for skip-clear (1663, 1678-1680) -> stale mount preserved after editor exit.

### 6. Mac PushConf - still `|| true`?

**FAIL - still present; fail path unreachable.**

`git-mode.sh:131`:

```
push_out="$(sshx "echo $b64 | base64 -d | bash" 2>/dev/null || true)"
push_ec=$?
```

`|| true` forces exit 0 into the substitution -> `push_ec` always 0 -> ERROR branch is dead code. Dedupe key still recorded as success.

### 7. Mac abort - PushConf `--clear`?

**FAIL - no `--clear` on abort paths.**

Examples (mac/connect.sh):

- Tunnel fail abort ~651-652: `ACTIVE_MOUNT_ID=""; push_server_connect_conf`
- Auth fail abort ~694-695: same
- Mount fail abort ~759-760: same

`push_server_connect_conf` without `--clear` and empty local active **preserves server ACTIVE_MOUNT** via remote grep (git-mode.sh:88-96). Local clear ≠ server clear.

Win abort correctly uses `Push-ServerConnectConf -ClearActiveMount` (e.g. connect.ps1:1230, 1285, 1296, 1357).

(`clear_session_mount` does call `--clear` - but abort paths do not use it.)

### 8. Mac fallthrough recovery order vs Win

**FAIL - Mac skips policy; Win does not.**

**Win** (connect.ps1:1625-1628 -> then 1648+ `if ($action -eq 'r')`):

1. Fallthrough sets `$action = 'r'`
2. Falls into recovery policy (skip/clear, Begin-ConnectRecovery, preserve vs down)

**Mac** (connect.sh:1058-1062):

```
elif [ "$_tunnel_sync_failed" -eq 1 ] || ! _tunnel_alive "$bg_pid"; then
    _action="r"
    continue   # outer session loop - NEVER enters if [ "$_action" = "r" ]
```

Assigning `_action=r` is **dead**; `continue` restarts ensure/recover without preserve/clear policy. Race: remount/ensure over stale ACTIVE_MOUNT while Win would have cleared or explicitly preserved.

### 9. Win softfail >=6 hard return?

**FAIL - no hard return.**

`git-mode.ps1:480-488`: SoftFailCount++ / log `count=N/6` / if lt 6 return true / **else fall through with no TUNNEL_DROP and no return false**.

May still return `$true` via later `Test-TunnelUp` or debounce. Mac counterpart **does** DROP at >=6 (`TUNNEL_DROP ... no_ssh_proc_tcp_open_budget` + `return 1`).

---

## Residual bugs (still open)

1. **P0 recover mangle (75)** - recover may no-op; mount proceeds on stale SSHFS; "Recover done" lies.
2. **P0 wait 4× (76)** - slow banner / MaxStartups -> spurious Mac tunnel-up fail vs Win.
3. **P1 zombie banner forever (77+78)** - ensure+sync both treat banner-miss+TCP as healthy reuse.
4. **P1 sticky mount (79+80)** - editor closed but recovery preserves mount; Win UI shows "sticky".
5. **P1 Mac abort ACTIVE_MOUNT leak (81)** - server automount keeps pointing at aborted project.
6. **P1 Mac post-recover PID (82)** - zombie ssh PID with dead forward continues into mount.
7. **P1 Mac fallthrough (83)** - auto-recover without clear/preserve decision.
8. **P1 Win softfail budget (25/84)** - never hard DROP after 6; Mac does.
9. **P1 PushConf `|| true` (7)** - silent conf push failure; ACTIVE_MOUNT / GIT_MODE drift.

---

## Race conditions (called out)

| Race | Trigger | Bad outcome |
|------|---------|-------------|
| Recover mangle vs mount-up | Fresh tunnel + recover | Mount races on unrecovered stale mount; UI green |
| Banner-miss ensure reuse vs probe | Flaky MaxStartups / wrong banner | Session loop never enters DROP; laptop-exec half-works |
| Sticky skip-clear vs user quit editor | Close Cursor, tunnel blip | Preserve mount + re-ensure; server thinks editor session live |
| Fallthrough continue vs policy | Sync fail, empty action | Mac remounts without ClearActiveMount; Win would policy |
| PushConf `|| true` vs automount | Failed push during abort | Server ACTIVE_MOUNT stale; next login wrong project |
| SoftFail>=6 fallthrough | no_proc + TCP open | Win keeps returning true; Mac would DROP - cross-OS flake |

---

## Agent deliverable status

| Artifact | Status |
|----------|--------|
| `scripts/tmp/FIX-AGENT-3.md` (Tunnel-Win: 25,77-80,84) | **MISSING** |
| `scripts/tmp/FIX-AGENT-4.md` (Tunnel-Mac: 7,75,76,81-83,...) | **MISSING** |
| Code fixes matching FIX-PLAN ownership | **NOT LANDED** (bugs reproduce in CURRENT sources) |

---

## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL / P0 | 2 | **fail** (75, 76) |
| HIGH / P1 | 10 | **fail** (7, 25, 77-84) |
| PASS slugs | 0 | - |

**Verdict: BLOCK** - Do not treat tunnel/session as fixed. Agents 3/4 either did not write reports or did not land fixes; every requested verification item still fails against CURRENT code. Re-run Agent 3 (Win sticky/softfail/banner/ensure) and Agent 4 (Mac recover quotes, wait 12, PushConf `|| true`, abort `--clear`, fallthrough order, post-recover `tunnel_up`) before any publish/deploy.
