# TEST SCOREBOARD — HARD TEST wave2 Agent S

**When:** 2026-07-20 (collect after ~90s wait)  
**Project:** `-p claude-code-server`  
**Collector:** Agent S (aggregator only; no deploy)  
**Stance:** harsh — missing report ≠ PASS; soft “mostly green” ignored

---

## Overall gate

# **NOT READY TO DEPLOY**

| Gate | Required | Actual |
|------|----------|--------|
| HARD FAIL count | 0 | **3+** (MAC, SERVER, STATIC; pipeline evidence FAIL) |
| MISSING critical agents | 0 | **1** — **pipeline** (`TEST-AGENT-PIPELINE.md` absent) |
| Critical set | pipeline, gitmode, static, parse all present + clean | **BROKEN** |

**Deploy approval: DENIED.**

---

## Counts

| Bucket | Count | Who |
|--------|------:|-----|
| **PASS** | 3 | AUTH, GITMODE, PARSE |
| **HARD FAIL** | 3 | MAC, SERVER, STATIC |
| **MISSING** (no agent report) | 1 critical + fix agents | **PIPELINE** (`TEST-AGENT-PIPELINE.md`); all `FIX-AGENT-*.md` (0 files) |
| Review FAIL (non-agent) | 1 | REVIEW-LOGGING-AUTH |
| Runtime out FAIL without agent md | 1 | `test-pipeline-out.txt` / `TEST-PIPELINE-OUT.txt` exit 1 |

Do **not** treat AUTH scoped PASS as absolution: REVIEW still finds open auth/logging P0s.

---

## Scoreboard

| Agent/Report | Verdict | Failures summary |
|--------------|---------|------------------|
| TEST-AGENT-PIPELINE.md | **MISSING** | Critical agent did not write report. Raw `test-pipeline-out.txt` / `TEST-PIPELINE-OUT.txt`: **EXIT 1**, 1 FAIL — `windows\connect.ps1 has no smart/curly quotes (PS 5.1 break)`. **Cannot PASS.** |
| TEST-AGENT-GITMODE.md | **PASS** | Exit 0, FAIL=0, 154 asserts; softfail DROP / banner / recover regressions held. Out: `TEST-GITMODE-OUT.txt`. |
| TEST-AGENT-STATIC.md | **HARD FAIL** | **4/4 P0 HIT**, 8/9 P1 HIT. Secrets + destructive git restore still in tree. |
| TEST-AGENT-PARSE.md | **PASS** | OK=26 FAIL=0 SKIP=2 (local deploy secrets). Out: `TEST-PARSE-OUT.txt`. |
| TEST-AGENT-AUTH.md | **PASS** *(scoped)* | Runtime auth merge + editor-launch suites green; TEMP dir cleanup + golden-synced-at present. **Overruled for deploy by REVIEW auth FAILs.** |
| TEST-AGENT-MAC.md | **HARD FAIL** | 5/5 static HARD asserts FAIL (nested sshx, tunnel wait seq 1 4, PushConf OR-true mask, CLEAR_MOUNT missing Reason=, abort without --clear). Requested `cmd /c bash` path blocked (exit 127); Git Bash/WSL suite OK but does not cover HARD asserts. |
| TEST-AGENT-SERVER.md | **HARD FAIL** | Watchdog tunnel-down **never** restores `.git.server-session`; mount/automount miss CR strip on `TUNNEL_PORT`; empty `ACTIVE_MOUNT` still first-alpha write. `bash -n` OK (not enough). |
| REVIEW-LOGGING-AUTH.md | **FAIL** | Logging watermark lies (trailing true / scp-without-cat); midnight rollover; races; Win golden skip; Mac O-key / relaunch bugs. FIX-AGENT-5/7 **not present**. |
| FIX-AGENT-*.md | **MISSING** | Zero files under `scripts/tmp/FIX-AGENT-*.md`. |

---

## Artifacts collected

### Present

| Path | Notes |
|------|-------|
| `scripts/tmp/TEST-AGENT-AUTH.md` | PASS (scoped) |
| `scripts/tmp/TEST-AGENT-GITMODE.md` | PASS |
| `scripts/tmp/TEST-AGENT-MAC.md` | HARD FAIL |
| `scripts/tmp/TEST-AGENT-PARSE.md` | PASS |
| `scripts/tmp/TEST-AGENT-SERVER.md` | HARD FAIL |
| `scripts/tmp/TEST-AGENT-STATIC.md` | HARD FAIL |
| `scripts/tmp/TEST-GITMODE-OUT.txt` | exit 0 |
| `scripts/tmp/TEST-PARSE-OUT.txt` | PASS |
| `scripts/tmp/test-pipeline-out.txt` | EXIT 1 — curly quotes |
| `scripts/tmp/TEST-PIPELINE-OUT.txt` | same pipeline FAIL (exists; agent md still missing) |
| `scripts/tmp/REVIEW-LOGGING-AUTH.md` | FAIL |

### Absent (checked)

| Path | Impact |
|------|--------|
| `scripts/tmp/TEST-AGENT-PIPELINE.md` | **CRITICAL MISSING** |
| `scripts/tmp/FIX-AGENT-*.md` | No fix-agent deliverables |
| `scripts/tmp/TEST-STATIC-OUT.txt` | No separate static out (agent md only) |
| `scripts/tmp/TEST-AUTH-OUT.txt` | No separate auth out |
| `scripts/tmp/TEST-SERVER-OUT.txt` | No separate server out |
| `scripts/tmp/TEST-MAC-OUT.txt` | No separate mac out |

---

## Top 20 residual failures (fix before deploy approval)

Ordered by deploy risk (secrets / data loss / mount-git / connect break first):

1. **P0 secret** — `publish/Get-DeployCredentials.ps1`: hardcoded `sepidz@Admin` sudo fallback when env/local empty (STATIC).
2. **P0 secret** — `claude-auth-lib.py` / `update-server.sh`: `CLAUDE_CODE_OAUTH_TOKEN` written to `/etc/environment` **without mode 600** (STATIC).
3. **P0 secret** — `add-user.sh` settings template: literal `"SQLSERVER_PASSWORD": "Mohammad123"` (STATIC).
4. **P0 destructive** — `claude-mount.sh` `restore_try`: `Remove-Item $p/.git -Force` before rename (STATIC) — can wipe real `.git`.
5. **P0 git hide** — `claude-watchdog.sh` tunnel-down path umounts **without** restoring `.git.server-session` to `.git` (SERVER HARD).
6. **P0 connect PS5.1** — `windows/connect.ps1` still contains smart/curly quotes; pipeline self-test **FAIL** exit 1 (PIPELINE).
7. **P0 log loss** — `connect-ui.ps1` / `connect-update.ps1`: remote append ends with trailing `true` so watermark advances on failed append (REVIEW L1 / STATIC P1).
8. **P0 log loss** — `connect-ui.sh`: watermark advances after **scp only**; sshx failure ignored (REVIEW L2).
9. **P0 log loss** — midnight day rollover switches file with **no** prior-day sync (REVIEW L4 / bug 37).
10. **P0 log race** — shared `.sync-offset` / mutex fail-open → duplicate or lost server logs (REVIEW L6 / bug 72).
11. **P0 auth** — Win outer `skipAuth` still bypasses golden stamp / rotation (REVIEW A1 / bug 13); NeedsRefresh misses `golden_stale` + machineid file (A2/45).
12. **P1 Mac recover** — `git-mode.sh` `recover_mounts_if_needed`: nested/broken `sshx` quoting in recover fallback (MAC #1).
13. **P1 Mac tunnel** — `wait_for_tunnel_up` / `poll_tunnel_with_progress` use `seq 1 4` while UI claims /12 (MAC #2).
14. **P1 Mac PushConf** — `push_server_connect_conf` uses `|| true` so `push_ec` always 0 (MAC #3).
15. **P1 Mac abort** — failure Q paths call `push_server_connect_conf` **without** `--clear` → stale server `ACTIVE_MOUNT` (MAC #5).
16. **P1 ACTIVE_MOUNT** — automount/watchdog still persist first-alphabetical project when empty (SERVER + STATIC P1).
17. **P1 TUNNEL_PORT CR** — `claude-mount.sh` / `claude-automount.sh` conf load do not strip CR (SERVER).
18. **P1 tunnel softfail** — `banner_miss_tcp_open` returns true without SoftFail/DROP; SoftFailCount>=6 lacks hard-fail branch (STATIC P1 / git-mode.ps1).
19. **P1 update lies** — `connect-update.ps1` logs ERROR then `exit 0`; ReadAllBytes loads full day log (STATIC P1).
20. **P1 UX/auth** — Mac O-key dead when `_editor_opened=1`; auth relaunch on skipped; CLEAR_MOUNT log missing `Reason=` (REVIEW A3/A4 + MAC #4).

Honorable mentions (still blocking quality): EditorSeenOpen forcing editorOpened; designer KeyChar always-OR; Mac wc watermark cmdsubst; empty catch around sync; Win build-auth early path drops auth.json metadata.

---

## Critical agents checklist

| Critical | Report present? | Verdict |
|----------|-----------------|---------|
| pipeline | **NO** | **MISSING** (+ out FAIL) |
| gitmode | YES | PASS |
| static | YES | **HARD FAIL** |
| parse | YES | PASS |

**Rule:** zero HARD FAIL **and** zero MISSING critical → not met.

---

## Harsh notes

- Green parse/gitmode does **not** wash P0 secrets, curly quotes, or watchdog git restore.
- AUTH agent PASS is narrow (suite + a few statics); REVIEW proves logging/auth user-visible failures still open — treat as **not shippable**.
- Pipeline without `TEST-AGENT-PIPELINE.md` is an automatic gate fail even if outs existed green (they are not green).
- No FIX-AGENT deliverables → wave2 fixes are **unproven on disk**.

**Final: NOT READY TO DEPLOY.**
