# HARD Logging Audit — Windows Connect Client

**Date:** 2026-07-20  
**Scope:** `scripts/client/windows/connect.ps1`, `connect-ui.ps1`, `windows/connect-update.ps1`, `windows/connect.bat`, `git-mode.ps1`, `editor-launch.ps1`, `cursor-auth-laptop.ps1`  
**Pass criteria:** Every user-visible or control-flow failure writes a day-log line at **ERROR** (or **WARN** with `FAIL` prefix), including bracketed session id `[session]`.

## Overall Verdict: **FAIL**

The main connect path has **critical logging orphans**: boot continues after laptop SSH setup failure, SSH command failures are INFO-only at `SSH_END`, the server connect retry loop is silent in logs, and several interactive waits lack `DECISION` / `FAIL` lines. Terminal exits via `Wait-ConnectExit` / `StepFail` / `Die` are mostly covered.

---

## Summary Table

| Area | Verdict | Critical orphans |
|------|---------|----------------|
| connect.bat bootstrap / update / outdated | PASS | — |
| connect-update.ps1 fatal exits | PASS* | *Many ERROR lines lack `FAIL` prefix (grep ergonomics only) |
| connect.ps1 trap / Die / StepFail / Wait-ConnectExit | PASS | — |
| connect.ps1 server connect retry (10×) | **FAIL** | No per-attempt or aggregate FAIL before exit |
| connect.ps1 SshX SSH_END | **FAIL** | exit≠0 logged INFO only (systemic) |
| connect.ps1 boot Ensure-LaptopSshReady | **FAIL** | Return value ignored; continues to menu |
| connect.ps1 project menu / Choose-Project | **FAIL** | Menu wait gap; null exit; Add/edit/delete failures Warn-only |
| connect.ps1 session loop retries | PARTIAL | StepFail OK; Warn-only guidance; Read-RetryQuitKey DEBUG-only |
| connect.ps1 OpenSSH install / firewall | PARTIAL | StepFail+Wait-ConnectExit OK; install catch blocks silent |
| git-mode.ps1 foreign session / retry | PARTIAL | DECISION present; Warn lines lack FAIL prefix |
| editor-launch.ps1 IDE prompts | **FAIL** | Read-Host without DECISION |
| cursor-auth-laptop.ps1 merge failures | PARTIAL | WARN `fail …` without FAIL; connect StepFail covers blocking path |
| connect-ui.ps1 Write-ConnectUserFacingError | **FAIL** | Helper defined, never called |
| connect-ui.ps1 Pick-LaptopFolder | **FAIL** | Folder dialog cancel/open unlogged |

---

## CRITICAL — Main Connect Path Orphans

### 1. Boot ignores `Ensure-LaptopSshReady` failure

**File:** `scripts/client/windows/connect.ps1:1146`

```powershell
$null = Ensure-LaptopSshReady -PubB $PubB
```

If admin is denied / UAC fails (`FAIL ADMIN_DENIED`, `FAIL ADMIN_UAC` are logged inside `Invoke-LaptopAdminOps`), the script still prints **Ready** and enters the project menu. User discovers failure only at tunnel/mount — no boot-level `FAIL LAPTOP_SSH_NOT_READY`.

**Recommended tag:** `FAIL LAPTOP_SSH_BOOT: reasons=<…> admin_attempted=<bool>`

---

### 2. `SSH_END exit!=0` logged at INFO (no FAIL)

**File:** `scripts/client/windows/connect.ps1:664-677`

Every `SshX` call writes:

```
SSH_END exit=$exit ms=$ms out=$truncOut
```

at default **INFO**, even when `$exit -ne 0`. Only `SSH_TIMEOUT` (exit 124) gets a separate ERROR. Failures that later cause `StepFail` / mount retry / empty mount list are invisible in log grep unless you correlate STEP lines.

**Recommended tag:** `FAIL SSH_END exit=$exit cmd=$truncCmd` at **ERROR** when `$result.Exit -notin 0,124`

---

### 3. Server connect retry loop — silent in day log

**File:** `scripts/client/windows/connect.ps1:1061-1088`

Ten attempts print console lines (`Connecting N/10`, `no response`, `auth failed`) but **no `Write-ConnectLog`** until final:

```powershell
Warn "Cannot reach $ServerIP after 10 attempts"
Wait-ConnectExit -Reason 'require_fail' -Code 1  # FAIL EXIT logged
```

Operator sees a long console wait with **zero** session-correlated log lines (VPN/server down).

**Recommended tags:**
- Per attempt: `CONNECT_ATTEMPT n=$attempt result=timeout|auth_fail|ok ms=$connT`
- Final: `FAIL CONNECT_UNREACHABLE host=$ServerIP attempts=10`

---

### 4. Project menu wait gap (Loading projects → Choose-Project)

**File:** `scripts/client/windows/connect.ps1:1154-1157`

```
Step "Loading projects" → StepOk → Choose-Project (table + Read-ConnectPrompt '>')
```

`StepOk` ends the step; user may sit at the project table with **no** `INTERACTIVE: project_menu_wait` / `MENU_PROJECT begin` until they type. Matches audit item “stuck waiting with no log”.

**Recommended tag:** `INTERACTIVE: project_menu_shown count=$($mounts.Count) hidden=$hiddenCount`

---

### 5. `Choose-Project` returns null — silent menu abort

**File:** `scripts/client/windows/connect.ps1:1157-1158`

```powershell
if (-not $go) { break }
```

No `FAIL MENU_ABORT` / `DECISION: project_menu=abort`. Script falls through to `Close-ConnectLog` and exits 0.

**Recommended tag:** `FAIL MENU_ABORT: user_cancelled_or_add_failed`

---

### 6. `Read-PostDisconnectKey` — 10s wait, no DECISION

**File:** `scripts/client/git-mode.ps1:213-246`, caller `connect.ps1:1909-1930`

Interactive `M/C/X` (or 10s default) with **no** log at wait start or on choice. Only console output.

**Recommended tags:**
- Begin: `INTERACTIVE: post_disconnect begin timeout_sec=10 default=M`
- End: `DECISION: post_disconnect=$postKey`

---

### 7. `Pick-LaptopFolder` — dialog unlogged

**File:** `scripts/client/connect-ui.ps1:1016-1028`

`FolderBrowserDialog` open/cancel returns `$null` with **no** `DECISION` / `FAIL`. Used from `Add-Project` (`connect.ps1:840`).

**Recommended tags:**
- Open: `INTERACTIVE: folder_picker begin`
- OK: `DECISION: folder_picker path=$path`
- Cancel: `DECISION: folder_picker=cancelled`

---

## HIGH — User-Visible Failures (Warn / `[!]` Only)

### 8. `Warn()` helper — WARN without `FAIL` prefix

**File:** `scripts/client/windows/connect.ps1:93-95`

```powershell
function Warn($m) {
    Write-ConnectLog "WARN: $m" 'WARN'   # no FAIL prefix
}
```

All `Warn` calls on the main path (connect unreachable hints, tunnel/mount/auth guidance, foreign session, git hide, etc.) fail strict grep for `FAIL*`.

**Recommended pattern:** `Write-ConnectLog ("FAIL WARN: {0}" -f $m) 'WARN'` or dual-write USER_ERROR for blocking cases.

**Sample orphan call sites:**

| File:Line | User-visible message |
|-----------|---------------------|
| connect.ps1:1086-1087 | Cannot reach server / VPN hints (before Wait-ConnectExit) |
| connect.ps1:1136 | `[!] server script push failed (continuing)` |
| connect.ps1:320 | sshd not ready within 20s |
| connect.ps1:1296-1300 | Tunnel did not come up hints |
| connect.ps1:1352 | Tunnel auth failed 5 times |
| connect.ps1:1421-1425 | Auto-fix exhausted / path not found |
| connect.ps1:847-865 | Add-Project validation / CM add failure |
| connect.ps1:919,931 | CM edit/delete SSH failure |
| git-mode.ps1:1112-1125 | Foreign session warnings |
| git-mode.ps1:168-174 | Invalid project rpath |

---

### 9. OpenSSH Server install — catch blocks swallow errors

**File:** `scripts/client/windows/connect.ps1:1197-1213`

Capability/winget install failures write **console DarkGray only** inside `catch { }` — no `Write-ConnectLog`. Final red message + `Wait-ConnectExit` (`FAIL EXIT`) exists, but root cause not in day log.

**Recommended tags:**
- `FAIL OPENSSH_CAP_INSTALL: err=$($_.Exception.Message)`
- `FAIL OPENSSH_WINGET_INSTALL: err=$($_.Exception.Message)`

---

### 10. Boot non-fatal script push failure

**File:** `scripts/client/windows/connect.ps1:1135-1137`

```powershell
Write-Host '    [!] server script push failed (continuing)' -ForegroundColor Yellow
```

No day-log line (continuing path — still operator-visible).

**Recommended tag:** `WARN FAIL SCRIPT_PUSH: continuing=1 detail=…`

---

### 11. `Write-ConnectUserFacingError` never used

**File:** `scripts/client/connect-ui.ps1:513-526`

Comment says every red `[X]` MUST land in day log; helper exists but **zero call sites** in scoped files. `[X]` paths rely on Die/trap/manual logging instead — inconsistent.

**Recommended:** Call from `Warn` for blocking cases, or from `[X]` Write-Host sites in connect-update trap / connect.bat paths.

---

## MEDIUM — Interactive Without DECISION (Non-Fatal)

| File:Line | Issue | Recommended tag |
|-----------|-------|-----------------|
| editor-launch.ps1:175 | `Show-EditorPickMenu` uses raw `Read-Host` | `DECISION: editor_pick=$edChoice` via `Read-ConnectPrompt -Tag EDITOR_PICK` |
| editor-launch.ps1:205 | `Configure-EditorPref` raw `Read-Host` | `DECISION: editor_pref=$val` |
| git-mode.ps1:1223-1249 | `Read-RetryQuitKey` logs INTERACTIVE at **DEBUG** only | Promote to INFO on session failures; add `DECISION: retry_quit=$rk` at WARN when preceded by StepFail |
| connect.ps1:1061-1080 | Password prompt for one-time key install | `INTERACTIVE: ssh_password_prompt begin` before `ssh … authorized_keys` |

---

## PASS — Adequately Logged Paths

| Path | Evidence |
|------|----------|
| connect.bat start | `BOOTSTRAP: connect.bat start` with session id (connect.bat:18) |
| connect.bat update fail | `FAIL UPDATE_BAT_EXIT` (connect.bat:27) |
| connect.bat relaunch limit | `FAIL UPDATE_RELAUNCH_LIMIT` (connect.bat:36) |
| connect.bat outdated scripts | `FAIL OUTDATED_SCRIPTS` (connect.bat:58) |
| Pre-ui ssh missing | Manual append `FAIL OpenSSH client` (connect.ps1:60) |
| trap unhandled | `FAIL UNHANDLED` + `Wait-ConnectExit` (connect.ps1:31-46) |
| Die | `FAIL DIE` ERROR (connect.ps1:79-87) |
| StepFail | `FAIL STEP name=…` ERROR (connect.ps1:127-136) |
| Wait-ConnectExit (code≠0) | `FAIL EXIT reason=…` ERROR (connect-ui.ps1:529-538) |
| Admin UAC flow | `FAIL NEED_ADMIN`, `FAIL ADMIN_DENIED`, `FAIL ADMIN_UAC` (connect.ps1:372-399) |
| AdminFix no pending | `FAIL ADMIN_FIX: No admin fix pending` (connect.ps1:507) |
| First-time setup username | `Read-ConnectPrompt SETUP_USER` + `DECISION` (connect.ps1:994-995) |
| Choose-Project menu input | `Read-ConnectPrompt MENU_PROJECT` + `Write-ConnectDecision` (connect.ps1:889+) |
| Foreign session takeover prompt | `Read-ConnectPrompt FOREIGN_SESSION` + `DECISION` (git-mode.ps1:1119-1122) |
| Git mode config | `Read-ConnectPrompt GIT_MODE` (git-mode.ps1:1521-1523) |
| connect-update fatal | ERROR-level `UPDATE:` lines + exit 1 (connect-update.ps1:296+) |
| connect-update unhandled trap | `FAIL UPDATE_UNHANDLED` (connect-update.ps1:77) |
| Auth blocking in session | `StepFail` + `FAIL STEP` for sqlite/merge/editor missing (connect.ps1:1533-1563) |
| Session loop StepFail paths | `FAIL STEP` before R/Q retry (tunnel, mount, auth) |

---

## SSH_END Specific Audit (Item 4)

| Scenario | SSH_END level | Downstream handling | Verdict |
|----------|---------------|---------------------|---------|
| `CM list` fails / empty | INFO exit≠0 | Empty menu → Add flow | **FAIL** — root SSH error not FAIL |
| `CM add/edit/rm` fails | INFO exit≠0 | Warn to user | **FAIL** |
| Mount `Invoke-MountProject` | INFO exit≠0 | StepFail + FAIL STEP | **FAIL** at SSH_END; PASS at StepFail |
| Benign grep empty | INFO exit=1 | Normal | Borderline OK if tagged `SSH_END exit=1 benign` |

**Fix:** In `SshX`, after line 677:

```powershell
if ($result.Exit -ne 0 -and $result.Exit -ne 124) {
    Write-ConnectLog ("FAIL SSH_END exit=$($result.Exit) cmd=$truncCmd out=$truncOut") 'ERROR'
}
```

---

## Recommended FAIL Tag Catalog (New / Missing)

| Tag | When |
|-----|------|
| `FAIL CONNECT_UNREACHABLE` | 10× server connect timeout |
| `FAIL CONNECT_AUTH` | Key copy / verify still fails |
| `FAIL SSH_END exit=N` | Any SshX non-zero (except 124 timeout path) |
| `FAIL LAPTOP_SSH_BOOT` | Ensure-LaptopSshReady false at boot |
| `FAIL MENU_ABORT` | Choose-Project null |
| `FAIL SCRIPT_PUSH` | boot PushOk false |
| `FAIL OPENSSH_*` | Auto-install catch paths |
| `FAIL WARN: …` | Prefix on operator-facing Warn for grep |
| `INTERACTIVE: project_menu_shown` | After Loading projects StepOk |
| `DECISION: post_disconnect=*` | After disconnect key |
| `DECISION: folder_picker=*` | Folder browser result |
| `DECISION: editor_pick=*` | Show-EditorPickMenu |
| `FAIL UPDATE_*` | Prefix on connect-update ERROR lines (consistency) |

---

## File-by-File FAIL List

### connect.ps1 — FAIL (critical orphans on main path)

See sections 1–5, 8–10 above.

### connect-ui.ps1 — PARTIAL FAIL

- PASS: `Write-ConnectLog`, `Wait-ConnectExit`, `Read-ConnectPrompt`, session init
- FAIL: `Pick-LaptopFolder` (1016), unused `Write-ConnectUserFacingError` (513)
- Acceptable: many `catch { }` in log sync/cleanup (non user-facing)

### connect.bat — PASS

All `[X]` paths paired with `FAIL …` file append including session id.

### connect-update.ps1 — PASS (level) / WARN prefix gap

- `[X] Update error` paired with `FAIL UPDATE_UNHANDLED` in trap
- Fatal exits use ERROR; recommend `FAIL UPDATE_SSH_MISSING`, `FAIL UPDATE_MANIFEST`, etc.
- `SSH_STAGE cat FAIL` uses WARN without FAIL prefix (220) — minor

### git-mode.ps1 — PARTIAL FAIL

- PASS: `Read-ConnectPrompt` foreign session, git mode, `Write-GitModeLog DECISION`
- FAIL: `Warn()` messages without FAIL prefix; `Read-PostDisconnectKey` no log; `Read-RetryQuitKey` DEBUG-only
- `Invoke-SshXChecked` logs `{Label} fail exit=N` at WARN without FAIL (1140-1146)

### editor-launch.ps1 — FAIL (interactive)

- Raw `Read-Host` at 175, 205 without session DECISION lines
- `Show-EditorAutoPick` console-only (non-blocking — lower severity)

### cursor-auth-laptop.ps1 — PARTIAL

- Internal failures: `Write-AuthSyncLog 'fail …'` at **WARN** without `FAIL` prefix (735, 744, 760)
- Blocking path covered by connect.ps1 `StepFail` (1533-1543) — PASS for terminal failure
- Many `catch { }` on JSON/IO — acceptable if non user-facing

---

## Main Connect Path Trace (Orphan Highlights)

```
connect.bat [PASS bootstrap FAIL tags]
  → connect-update.ps1 [PASS ERROR exits]
  → connect.ps1
       ssh client check [PASS manual FAIL or Wait-ConnectExit]
       dot-source + Initialize-ConnectLog [FAIL if writer open fails — console [WARN] only, 153-155]
       setup username [PASS Read-ConnectPrompt]
       connect retry ×10 [FAIL silent]
       boot Initialize-ServerSession [SSH_END orphans]
       Ensure-LaptopSshReady ignored [FAIL critical]
       menu: Loading projects [FAIL menu wait gap]
       Choose-Project [PASS prompts; FAIL null abort / Add failures]
       editor resolve [FAIL editor-launch Read-Host if ask mode]
       sshd check / install [PARTIAL]
       session loop: tunnel/mount/auth [PARTIAL StepFail OK, Warn orphans, SSH_END orphans]
       disconnect menu [FAIL Read-PostDisconnectKey]
  → Close-ConnectLog
```

---

## Conclusion

**Do not mark PASS** until at minimum:

1. Boot honors `Ensure-LaptopSshReady` failure (`FAIL LAPTOP_SSH_BOOT` + exit or blocking retry)
2. `SSH_END` promotes non-zero exits to `FAIL SSH_END` at ERROR
3. Server connect retry loop writes `CONNECT_ATTEMPT` / `FAIL CONNECT_UNREACHABLE`
4. Project menu shows `INTERACTIVE: project_menu_shown` after load
5. `Choose-Project` null → `FAIL MENU_ABORT`
6. `Read-PostDisconnectKey` → `DECISION: post_disconnect=…`

Secondary: wire `Write-ConnectUserFacingError`, replace raw `Read-Host` in editor-launch, add `FAIL` prefix to `Warn()` for operator-blocking messages.
