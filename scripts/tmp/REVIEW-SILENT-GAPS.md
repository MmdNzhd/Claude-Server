# Residual Silent Failures — Connect Client (post parallel fixes)

Audit date: 2026-07-20  
Scope: `connect.ps1`, `connect.sh`, `connect-update.ps1/sh`, `cursor-auth-laptop.ps1`, `git-mode.ps1/sh` (+ load-bearing `connect-ui.ps1/sh` for durable log ship)  
Focus: errors where **user UI looks OK / exit 0** and/or **server `~/.claude/logs/` never gets the evidence**.

No symbol named `SoftContinue` exists; tunnel **soft_fail → return true** is the equivalent.

---

## P0 — durable log loss or false-success that hides force-needed failures

| # | File:line | Issue | Impact | Suggested fix (one-liner) |
|---|-----------|--------|--------|---------------------------|
| 1 | `scripts/client/connect-ui.sh:267-272` | After `scp` OK, remote `cat >> day.log` is `\|\| true` and **watermark still advances** (also advances if `sshx` missing so cat never runs). | Server day log silently drops chunks forever; local watermark claims synced. | Only bump `CONNECT_LOG_SYNC_OFF` / `.sync-offset` when remote append exit is 0 (mirror Windows `catRes.Ok`). |
| 2 | `scripts/client/windows/connect-update.ps1:236-310` | `Write-UpdateFileLog … 'ERROR'; exit 0` on ssh/scp missing, manifest empty/zero, download fail, incomplete — **ship-to-server block only runs on success** (`applied_ok` ~376+). | UPDATE ERROR lines stay laptop-local; server never sees update failures (user complaint). | Extract ship helper; call it before every `exit 0` after ERROR/WARN (or always `finally` ship). |
| 3 | `scripts/client/mac/connect-update.sh:162-188` | manifest empty / download fail / incomplete: **console only**, `exit 0`, **no `_update_file_log`**, no server ship (Mac has no ship path at all). | Worse than Windows: zero durable local or server evidence of update failure. | `_update_file_log '…' ERROR` then best-effort `scp` chunk of day log before each failure `exit 0`. |
| 4 | `scripts/client/windows/connect.ps1:1435-1437` | `authSync.Skipped` (not AlreadyComplete) → `StepOk 'skipped'` — **no Warn**, even when `ForceCursorAuthSync` was set (recovery). | Post-recovery AUTH looks green while golden missing / golden read failed; force flag may linger without user signal. | If `$script:ForceCursorAuthSync -or -not $authSync.Ok`: `StepFail`/`Warn` + `Write-ConnectLog … 'WARN'` with skip reason. |
| 5 | `scripts/client/mac/connect.sh:816-818` | `CURSOR_AUTH_SYNC_RESULT=skipped` → `step_ok "skipped"` — no warn (pairs with Mac sync returning skipped with no log). | Same false-success after force/recovery on Mac. | On `skipped`: `step_fail` or `warn` + `connect_log 'AUTH_WARN skipped reason=… force=$CURSOR_AUTH_FORCE' WARN`. |

---

## P1 — swallowed errors / weak severity / delayed or missing server visibility

| # | File:line | Issue | Impact | Suggested fix (one-liner) |
|---|-----------|--------|--------|---------------------------|
| 6 | `scripts/client/cursor-auth-laptop.ps1:633-634` | Golden missing logged **DEBUG** + **INFO** only (not WARN); caller StepOk-skipped. | INFO may wait 25 lines before sync; DEBUG never syncs mid-session — server often never sees skip under force. | `Write-AuthSyncLog '… golden_missing' 'WARN'` when `$Force` (else INFO). |
| 7 | `scripts/client/git-mode.sh:2414` | `test -f golden/auth.json` fail → `CURSOR_AUTH_SYNC_RESULT=skipped; return 1` with **zero `connect_log`**. | Skip reason never hits local/server logs. | `connect_log "AUTH_SYNC: skipped reason=golden_missing force=$force" WARN` before return. |
| 8 | `scripts/client/git-mode.sh:2418` | `fetch_golden_auth_payload` fail → skipped, **no log**. | Golden scp/parse failure invisible. | `connect_log "AUTH_SYNC: skipped reason=golden_read_failed" WARN` before return. |
| 9 | `scripts/client/cursor-auth-laptop.ps1:646` | `SshX "cursor-auth-sync --force 2>&1" 2>$null \| Out-Null` — exit/stderr discarded. | Server-side auth sync failure invisible on laptop/server connect log. | Capture output/`$LASTEXITCODE`; on fail `Write-AuthSyncLog "cursor-auth-sync exit=$ec out=…" WARN`. |
| 10 | `scripts/client/git-mode.sh:2415` | `sshx "cursor-auth-sync --force …" 2>/dev/null \|\| true` | Same as Windows Out-Null. | Log non-zero: `connect_log "AUTH_SYNC: server sync failed" WARN`. |
| 11 | `scripts/client/connect-ui.ps1:254` | `Sync-ConnectLogToServer` outer `catch { }` swallows unexpected exceptions (no `LOG_SYNC_FAIL`). | Sync exceptions leave no durable breadcrumb (unlike mkdir/scp fail paths). | In catch: write one local `LOG_SYNC_FAIL ex=…` line (same as mkdir fail path). |
| 12 | `scripts/client/connect-ui.ps1:279-280` | `Ensure-ConnectLogWriter` catch → `return $false`; `Write-ConnectLog` then returns silently. | **All** subsequent logging vanishes with no console/server WARN. | Once: `Write-Host` yellow + try append fallback file under `%TEMP%`. |
| 13 | `scripts/client/git-mode.ps1:649-651` | `Push-ClaudeMountIfChanged`: `scp … 2>$null`; fail does nothing (no `Write-GitModeLog`). | Stale `claude-mount` on server with no ERROR in connect log. | `else { Write-GitModeLog "SCP: claude-mount fail exit=$LASTEXITCODE" 'ERROR' }`. |
| 14 | `scripts/client/git-mode.ps1:514-515` | Tunnel soft-continue: `bg_alive_forward_dead` miss logged **DEBUG** then `return $true` (SoftContinue). | First two misses never sync to server (DEBUG local-only); session can look healthy. | Promote miss lines to WARN (or INFO) so they flush. |
| 15 | `scripts/client/cursor-auth-laptop.ps1:723` | `$null = Merge-CursorStorageJsonFromGolden …` — failure ignored (Mac: `\|\| true` at `git-mode.sh:2420`). | Partial auth (DB ok, storage.json stale) with no WARN. | If merge false: `Write-AuthSyncLog 'storage.json merge failed' WARN` (keep going). |
| 16 | `scripts/client/mac/connect-update.sh:132-134` | Missing ssh/scp/ver file → bare `exit 0` (no log). | Pre-update abort invisible everywhere. | `_update_file_log 'ssh_missing\|…' ERROR` before exit. |
| 17 | `scripts/client/windows/connect-update.ps1:236-237` | ERROR logged locally then `exit 0` without ship (same class as #2). | Covered by #2; listed for exit-0-after-ERROR hunt. | Same ship-before-exit helper. |

---

## Already OK / lower residual (not ranked P0/P1)

| Area | Notes |
|------|--------|
| Windows watermark | `connect-ui.ps1` / `connect-update.ps1` advance offset only when remote `cat` OK — correct contrast to Mac #1. |
| Soft_fail with WARN | `git-mode.ps1:482` / `:506` / `ENSURE_TUNNEL soft_fail` log WARN (syncs); intentional SoftContinue until threshold. |
| `connect.ps1` trap | Writes ERROR then `Wait-ConnectExit` → Sync + Close — OK for durable ship on unhandled. |
| Empty `catch {}` on Dispose/mutex/icacls | Mostly benign; not durable-log gaps. |
| `Out-Null` on icacls / mkdir cosmetic | Not silent failure of session-critical paths. |

---

## Hunt checklist coverage

| Pattern | Residual? |
|---------|-----------|
| `catch {}` empty | Yes — Sync outer catch (#11), Ensure writer (#12), many benign dispose catches |
| `Out-Null` on ssh/scp | Yes — cursor-auth-sync (#9), Push-ClaudeMount scp (#13) |
| `exit 0` after ERROR | Yes — connect-update.ps1/sh (#2,#3,#16,#17) |
| trap without Write-Log/sync | No residual on Windows trap; Mac EXIT flush present (but watermark bug #1 undermines it) |
| SoftContinue swallows | Soft_fail return true — WARN OK; DEBUG miss soft-continue (#14) |
| watermark advance on fail | **Mac only** (#1); Windows OK |
| AUTH skipped without WARN when force needed | Yes (#4,#5,#6,#7,#8) |

---

## Recommended fix order

1. Mac watermark gate on remote append success (#1) — stops permanent server log holes.  
2. Ship update day-log on all ERROR/WARN exits; Mac add ERROR logs (#2,#3,#16).  
3. AUTH skipped under force → WARN + StepFail/Warn UI (#4,#5,#6,#7,#8).  
4. Stop Out-Null / `|| true` on `cursor-auth-sync --force` (#9,#10).  
5. Remaining P1 (#11–#15).
