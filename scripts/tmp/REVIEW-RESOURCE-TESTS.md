# REVIEW-RESOURCE-TESTS — Harsh verdict (Agent 9/10 scope)

**Date:** 2026-07-20  
**Scope:** Bugs 15, 35, 39, 41, 47–51, 55–64, 69, 73 + FIX-AGENT-9/10  
**Method:** laptop-exec `-p claude-code-server` only; live tree + `git diff --stat`  
**FIX-AGENT-9.md / FIX-AGENT-10.md:** **ABSENT** (plan rows exist in `scripts/tmp/FIX-PLAN-20260720.md` only)

**Diff footprint (conflict fuel):** ~47 files, **+5077 / −898**. Hot overlap: `git-mode.ps1` (+504), `git-mode.sh` (+822), `connect.ps1` (+382), `connect-ui.ps1` (+417), `mac/connect.sh` (+320), `CLAUDE.md` (+416), `docs/client-connect.md` (+137). Any agent still editing logging / PushConf / tunnel / docs will thrash.

---

## Executive verdict

**BLOCK / do not call Agents 9–10 “done.”** Chunking + Kill() + base64 PushConf are partial mitigations. The inventory bugs in this slice are mostly **still open**. Docs actively lie. Official tests still would **not** catch Farzad. Mac PushConf exit handling is still broken.

Verdict: **WARNING → effectively BLOCK for resource/silent/docs closeout.**

---

## Checklist (requested verify)

| # | Question | Result | Evidence |
|---|----------|--------|----------|
| 1 | Log sync no longer full `ReadAllBytes` every time? | **STILL DOES** (partial chunking only) | `connect-ui.ps1` `Sync-ConnectLogToServer`: still `$all = [IO.File]::ReadAllBytes(...)` then copy ≤512KB chunk. Same pattern in `connect-update.ps1`. Watermark helps network; **RAM still loads entire day file every sync.** Bug **15** / **73** open. |
| 2 | Heartbeat still dumps Cursor cmdlines? | **YES** (when editor not “open”) | `connect-ui.ps1` HEARTBEAT → `Get-RemoteEditorStateExplain` → per-main `cmd=$(Format-EditorProcessCommandLine ... MaxLen 180)`. Fires on status ticks while `$EditorOpen` is false. Bug **47** open. |
| 3 | CIM cache TTL exists? | **NO** | `EditorCimCache` is forever-until-`Clear-CursorProcessCache` / `ForceRefresh`. Clear only at launch poll paths, not session heartbeat/soft-fail. Bug **48** open. |
| 4 | Orphan ssh/scp on timeout reaped? | **PARTIAL** | Log-sync: `Invoke-ConnectLogProcTimed` calls `$p.Kill()` on timeout — parent only, no process-tree / no `WaitForExit` after Kill. **Start-Job scp** (`Prepare-ServerSessionParallel`): `Stop-Job` + `Remove-Job` — **native `scp.exe` child can orphan.** Bug **49** partial, **50** open. |
| 5 | PushConf e2e/quoting test exists & would catch Farzad? | **NO** | Official suite: `test-connect-pipeline.ps1` only asserts function exists + `notmatch claude-self-heal`. **Zero** asserts on `base64`, `PUSH_CONF_RESULT`, `AM=` empty, apostrophe, or elif storm. Ad-hoc junk under `scripts/tmp/` / `tmp/` (`test-pushconf-b64.ps1`, `repro-am-quote.ps1`) is **not** in `run-all.bat`. Bug **41** open. |
| 6 | Vacuous `Assert $true` still in tests? | **YES** | `test-publish.ps1:58` `Assert $true "...has no sepidz-fork strings..."` after a loop that already `Assert $false` on hits — pass banner, not a real predicate. `test-editor-launch.ps1:22` `Assert $true "cursor on PATH"` inside a prior `if (Get-Command cursor)` — soft-vacuous. Bug **62** open. |
| 7 | Docs lies (temp wipe, runas) fixed? | **NO — worse, contradictory** | Code: durable day log `~/.config/claude-connect/logs/connect-YYYYMMDD.log`; `Close-ConnectLog` explicitly **keeps** it. Docs/`CLAUDE.md`/`publish/README.txt` still claim temp buffer deleted on exit. `CLAUDE.md` invariant: *“No unconditional RunAs”*; `connect.ps1` lines 26–45: **always elevate** via `RunAs` unless `-AdminFix`. Bugs **35**, **69** open. |
| 8 | `SshX … \| Out-Null` still swallowing critical failures? | **YES** | Hot paths still pipe to `Out-Null` / `2>$null`: recover, `down-others`, known_hosts wipe, chmod, laptop-exec-setup, self-heal. Failures invisible to UI. Bug **39** open. Mac PushConf: `sshx ... \|\| true` then `push_ec=$?` → **exit always 0** — silent “ok” + dedupe. Related **63**/Mac #7 residue. |

---

## Per-bug status (this slice)

### Resource (Agent 9)

| Bug | ID | Status | Notes |
|-----|-----|--------|-------|
| 15 | `log-sync-readallbytes-full-file` | **OPEN** | Chunk upload ≠ streaming read. Multi-MB day log → full alloc every WARN/INFO batch. |
| 47 | `heartbeat-explain-log-growth` | **OPEN** | Cmdline dump still on HEARTBEAT DEBUG path when editor closed. |
| 48 | `session-cim-cache-no-ttl` | **OPEN** | Cache hit path has no age; stale open/closed for whole session after first query. |
| 49 | `log-sync-ssh-kill-orphans` | **PARTIAL** | Kill added; no tree kill; no post-kill wait; orphans possible under OpenSSH mux quirks. |
| 50 | `start-job-scp-orphan-on-timeout` | **OPEN** | `Stop-Job` does not guarantee killing `scp.exe`. |
| 51 | `tunnel-softfail-cim-reattach-storm` | **OPEN** | Soft-fail still `Get-CimInstance Win32_Process` ssh.exe on reattach; session loop sleeps ~800ms and can re-enter. |
| 60 | `session-double-onfolder-check` | **OPEN** | Multiple `Test-RemoteEditorOnCorrectFolder` / window checks per loop iteration + launch polls. |
| 61 | `local-day-log-no-size-cap` | **OPEN** | No truncate/rotate on local day file; only server mtime+1 cleanup. |
| 73 | `warn-sync-storm-amplifies-ram` | **OPEN** | WARN → immediate `Sync-ConnectLogToServer` → full ReadAllBytes + up to 3 timed ssh/scp under flap. |

### Silent / tests / docs (Agent 10)

| Bug | ID | Status | Notes |
|-----|-----|--------|-------|
| 35 | `docs-temp-log-lie` | **OPEN** | `docs/client-connect.md` §Logging, `CLAUDE.md` policy, `publish/README.txt` all wrong vs durable local day logs. |
| 39 | `sshx-swallow-callers` | **OPEN** | Many critical `SshX … \| Out-Null` remain. |
| 41 | `missing-pushconf-quoting-e2e` | **OPEN** | Production Win path uses base64 (good); **tests do not lock it.** Regression can ship silently. |
| 62 | `weak-assert-true` | **OPEN** | See checklist #6. |
| 63 | `win-pushconf-ok-without-result` | **OPEN** | Win: `$pushExit -eq 0` dedupes even when `PUSH_CONF_RESULT` missing (`(no result line)`). Mac: `|| true` forces ec=0. |
| 64 | `update-tests-miss-fail-exit` | **OPEN** | `connect-update.ps1` still `exit 0` on ERROR paths (`ssh_missing`, `manifest_empty`, etc.). Suite does not assert ERROR→nonzero. |
| 69 | `claude-md-no-unconditional-runas-lie` | **OPEN** | Invariant table vs always-elevate code — pick one and fix the other. |

### Parity leftovers (55–59) — spot check

| Bug | Status | Notes |
|-----|--------|-------|
| 55 | likely **OPEN** | Win ENSURE heavily logged; Mac ENSURE quieter (not fully re-audited line-by-line this pass). |
| 56 | **OPEN** (asymmetry) | Win has `reason=recent_success` reuse; Mac rg shows soft_fail but not equivalent 5s recent_success. |
| 57 | **OPEN** (by design debt) | Win ControlMaster=no on log-sync; Mac mux asymmetry called out in inventory — untreated here. |
| 58–59 | **UNVERIFIED deep** | Not blocking this review’s resource/silent core; assume open until proven. |

---

## Concrete failure modes (HIGH bar)

### [HIGH] Full-file ReadAllBytes under WARN storm (15, 73)

**File:** `scripts/client/connect-ui.ps1` (~191)  
**Trigger:** Day log grows to several MB; tunnel flaps → WARN spam → sync every WARN.  
**Outcome:** Repeated multi-MB allocations + 3 remote procs; UI freeze / RAM spike. Chunking only limits **upload** size, not read.  
**Why guards fail:** Watermark/offset skip empty syncs only when `$off -ge $all.Length` — still reads all bytes to know that.

### [HIGH] Docs contradict durable logging (35)

**Files:** `docs/client-connect.md` ~138–145, 173; `publish/README.txt` ~131–138; `CLAUDE.md` ~181  
**vs** `connect-ui.ps1` `Initialize-ConnectLog` / `Close-ConnectLog` (“Keep durable local day log”)  
**Outcome:** Operators delete “temp” paths that no longer exist; miss `~/.config/claude-connect/logs/`; support playbooks wrong.

### [HIGH] CLAUDE.md RunAs invariant lie (69)

**File:** `CLAUDE.md` ~589 vs `connect.ps1` ~26–45  
**Outcome:** Agents/humans “fix” toward AdminFix-only elevation while product **requires** unconditional RunAs — or vice versa. Doc drift guarantees future wrong patches.

### [HIGH] No regression test for Farzad PushConf (41)

**File:** `scripts/client/tests/test-connect-pipeline.ps1` ~74–79  
**Trigger:** Someone “simplifies” PushConf back to nested double-quoted remote shell.  
**Outcome:** `AM=""` → elif syntax storm on server; ACTIVE_MOUNT corruption. Suite stays green.

### [HIGH] Mac PushConf always succeeds (63 / Mac residue)

**File:** `scripts/client/git-mode.sh` ~131–142  
```bash
push_out="$(sshx "echo $b64 | base64 -d | bash" 2>/dev/null || true)"
push_ec=$?   # always 0 because of || true
```
**Outcome:** Failed pushes still set `_LAST_PUSH_CONF_*` dedupe → **8s black hole** with wrong/missing conf. Also Mac heredoc embeds `$prefer`/`$lu` **without** Win-style `'\''` escape before base64.

### [MEDIUM] Heartbeat cmdline growth (47)

**File:** `connect-ui.ps1` HEARTBEAT + `editor-launch.ps1` `Get-RemoteEditorStateExplain`  
**Trigger:** Editor closed / not yet on folder; status loop ~800ms.  
**Outcome:** DEBUG day log fills with truncated Cursor cmdlines + CIM queries (pairs with 48/60).

### [MEDIUM] CIM cache no TTL (48)

**File:** `editor-launch.ps1` `Invoke-CimEditorProcessQuery`  
**Trigger:** Cursor exits after first cached query; session thinks still running until next Clear.  
**Outcome:** Wrong on_folder / skip launch / false “open.”

### [MEDIUM] Start-Job scp orphan (50)

**File:** `git-mode.ps1` `Prepare-ServerSessionParallel` ~671–695  
**Trigger:** scp hangs >30s; `Stop-Job`.  
**Outcome:** Orphan `scp.exe` holding handles / network; next connect fights itself.

### [MEDIUM] Vacuous asserts (62)

**Files:** `test-publish.ps1:58`, `test-editor-launch.ps1:22`  
**Outcome:** Green noise; teaches future tests that `Assert $true` is OK.

### [MEDIUM] SshX Out-Null on recover/down (39)

**File:** `git-mode.ps1` recover / `Unmount-OtherProjects` / known_hosts clear  
**Outcome:** Mount left stale; UI shows success path; only TRACE/DEBUG might hint.

---

## What actually improved (credit, not closure)

- Log sync: watermark + 512KB chunks + timed `Start-Process` + Kill — **better than unbounded scp of whole file**, not a fix for 15/73.
- PushConf Win: base64 remote body + `PUSH_CONF_RESULT` + fail skips dedupe — **addresses Farzad root cause in code**, not in tests (41).
- CIM: shared `EditorCimCache` + launch clears — reduces launch WMI spam; **no TTL** (48).
- HEARTBEAT gated to editor-not-open — reduces spam when healthy; **still dumps cmdlines when unhealthy** (47).

---

## Cross-agent merge / conflict risk

| Collision zone | Agents likely touching | Risk |
|----------------|------------------------|------|
| `connect-ui.ps1` Sync/Heartbeat/CloseLog | 9 (resource), 10 (docs/silent), logging agents | **CRITICAL** — Easy to reintroduce ReadAllBytes “simplifications” or doc comments that fight code. |
| `git-mode.ps1` PushConf / Start-Job scp / tunnel soft-fail | 9 (50/51), 10 (41/63), tunnel agents | **CRITICAL** — PushConf and Prepare-ServerSessionParallel sit adjacent; overlapping hunks. |
| `git-mode.sh` push_server_connect_conf / ENSURE | Mac parity (55–57), 10 (63) | **HIGH** — Mac `|| true` vs Win LASTEXITCODE semantics diverge under “parity” PRs. |
| `connect.ps1` elevation + session loop onfolder | 10 (69), launch/perf agents (60) | **HIGH** — RunAs policy + folder checks both live at top/session. |
| `editor-launch.ps1` CIM cache | 9 (48/47/60) | **HIGH** — TTL patch vs ForceRefresh call-site patches conflict. |
| `docs/client-connect.md` + `CLAUDE.md` + `publish/README.txt` | 10 (35/69), publish agents | **HIGH** — Three docs must move together; currently all three lie the same way. |
| `scripts/client/tests/*` | 10 (41/62/64) | **MEDIUM** — Weak asserts + missing PushConf e2e; parallel test edits easy to conflict. |
| `scripts/tmp/**` junkyard | everyone | **Noise** — hundreds of one-off scripts; do not treat as source of truth; FIX-AGENT-9/10 never written. |

**Merge advice:** Serialize Agent 9 then 10 on `connect-ui.ps1` + `git-mode.ps1`; land doc truth **after** code freeze on log path; add PushConf golden test **before** any further PushConf “cleanup.”

---

## Required fixes before claiming Agent 9/10 done

1. Stream log sync (`FileStream` seek from watermark) — stop `ReadAllBytes` of whole day file.  
2. HEARTBEAT: counts/flags only; no cmdline dump (or VERBOSE-only).  
3. CIM cache: TTL (e.g. 2–5s) or force refresh on session status / soft-fail.  
4. Reap: `taskkill /T` or process-tree kill for log-sync; for scp job kill PID tree before `Remove-Job`.  
5. Official test: base64 PushConf + empty ACTIVE_MOUNT + apostrophe user + require `PUSH_CONF_RESULT` for ok/dedupe.  
6. Remove vacuous `Assert $true`; assert real predicates.  
7. Rewrite docs + CLAUDE invariant to match durable logs **and** pick one elevation story.  
8. Stop `|| true` on Mac PushConf; don’t dedupe without RESULT; audit `SshX|Out-Null` on mount/recover.  
9. Write `FIX-AGENT-9.md` / `FIX-AGENT-10.md` with done/not-done — or stop pretending the plan was executed.

---

## Review Summary

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 0 | (no credential/RCE in this slice) |
| HIGH | 5 | fail — ReadAllBytes, docs lie, RunAs lie, no Farzad test, Mac PushConf `|| true` |
| MEDIUM | 6 | fail — heartbeat cmdlines, CIM TTL, scp orphan, Out-Null, vacuous asserts, soft-fail CIM |
| LOW | parity 55–59 | mostly open / unverified |

**Verdict: WARNING (merge with caution) — treat Agent 9/10 scope as incomplete. Do not close bugs 15, 35, 39, 41, 47–51, 62–64, 69, 73.**

`git diff --stat` alone: multi-agent pileup on the same load-bearing client files; expect conflict, not a clean handoff.
