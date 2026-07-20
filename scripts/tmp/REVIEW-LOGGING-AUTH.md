# REVIEW - Logging + Auth (silent failures)

**Date:** 2026-07-20  
**Scope:** bugs 11, 12, 36-38, 72 + auth 13, 14, 42-46 + AA616 TEMP  
**Sources:** `scripts/client/connect-ui.ps1`, `connect-ui.sh`, `windows/connect.ps1`, `mac/connect.sh`, `cursor-auth-laptop.ps1`, `windows/connect-update.ps1`, `git-mode.sh`, `scripts/tmp/BUGS-SERIOUS-20260720.md`, `scripts/tmp/FIX-PLAN-20260720.md`  
**FIX-AGENT-5.md / FIX-AGENT-7.md:** **NOT PRESENT** (plan assigns agent 5=logging, 7=auth; no agent deliverable files found)

**Overall: FAIL** - user complaint ("errors, no durable server logs") is still explained by live code. Local day logs exist; **server append success is not proven before watermark advance**.

---

## Proof checklist (requested)

| # | Claim to prove | Verdict | Evidence |
|---|----------------|---------|----------|
| 1 | Watermark advances ONLY on successful remote append (no `; true` mask) | **FAIL** | Win+Mac remote cmds end with `; true` -> SSH exit 0 even if `cat >>` failed |
| 2 | Mac does not advance on scp-ok / cat-fail | **FAIL** | Watermark written inside `if scp; then` after `sshx ... \|\| true` - cat result ignored |
| 3 | ERROR/Unexpected triggers sync or local flush before exit | **PARTIAL** | Trap/`ERROR`/`flush` call sync; sync itself lies (see #1-2) |
| 4 | Midnight rollover flushes prior day | **FAIL** | Both platforms switch day file with **no** prior-day sync |
| 5 | Concurrent sync watermark races | **FAIL** | Shared `.sync-offset`; reset-to-0; update + connect; mutex fail-open |
| 6 | All `Remove-Item $tmp` in cursor-auth-laptop.ps1 safe | **PARTIAL PASS** | Golden dir uses `Remove-CursorAuthTempDir`; mid-file still `$env:TEMP` |
| 7 | Golden rotation skip still possible on Win? | **FAIL - YES** | Outer `skipAuth` bypasses `Sync-CursorGoldenAuth` golden stamp |
| 8 | Silent auth skip paths that won't log usefully | **FAIL** | Several skip/DEBUG-only paths; outer skip never hits AUTH_SYNC |

---

## Logging findings

### L1 - Bug 11 `ssh-trailing-true-masks-append-fail` - **OPEN / FAIL**

**Location:** `scripts/client/connect-ui.ps1` `Sync-ConnectLogToServer` (~L207, L227)

```text
$mk = '... find ... -delete 2>/dev/null; true'
$cat = 'cat "$HOME/..." >> "$HOME/..." 2>/dev/null; rm -f ...; chmod ... 2>/dev/null; true'
```

**Issue:** Remote shell always exits 0 because of trailing `; true`. `$catRes.Ok` is therefore true whenever SSH connects, even if `cat >>` failed (disk full, perms, missing tmp after race). Watermark then advances (`$off + $take` + `.sync-offset` write).

**Impact:** Permanent **server-side** log loss while laptop believes bytes are synced. Matches user complaint exactly (ops look at `~/.claude/logs/`).

**Also:** `connect-update.ps1` ship path (~L414) uses the same `; true` on cat (and mkdir).

**Fix:** Remote must be fail-closed, e.g. `cat ... >> ... && rm -f ...` with **no** trailing `true`. Advance watermark only if remote exit != 0 is impossible on append failure. Prefer `ssh ... 'set -e; ...'` or explicit `echo APPEND_OK`.

---

### L2 - Bug 12 `mac-scp-ok-without-cat-advances-watermark` - **OPEN / FAIL**

**Location:** `scripts/client/connect-ui.sh` `sync_connect_log_to_server` (~L265-273)

```bash
if scp ...; then
  if declare -F sshx; then
    sshx "cat ...; true" >/dev/null 2>&1 || true
  fi
  CONNECT_LOG_SYNC_OFF="$(wc -c < "$CONNECT_LOG_PATH" ...)"
  printf '%s' "$CONNECT_LOG_SYNC_OFF" > "${CONNECT_LOG_PATH}.sync-offset"
fi
```

**Issue:** Watermark advances after **scp only**. If `sshx` is missing, cat never runs. If cat fails, `|| true` hides it. Worse than Windows: Windows at least *attempts* to gate on `$catRes.Ok` (but `; true` neuters it).

**Impact:** Same permanent server gap; Mac is the worse offender.

**Fix:** Require successful remote append (check exit / sentinel). Do not write `.sync-offset` unless append confirmed. If `sshx` absent, do not advance.

---

### L3 - Bug 38 `mac-tail-cmdsubst-wc-watermark-loss` - **OPEN / FAIL**

**Location:** `connect-ui.sh` - `chunk="$(tail -c +...)"` then watermark = `wc -c` of **full file**.

**Issue:** Bash command substitution strips trailing newlines from `$chunk`. Uploaded bytes != local size; watermark jumps to full `wc -c`. Trailing newline(s) (and any all-newline remainder edge cases) never re-sync.

**Impact:** Corrupt/truncated server log lines at chunk boundaries; over-advanced watermark.

**Fix:** Use `tail -c +N > chunkfile` (no `$(...)`), or `dd`, then watermark += byte length of **chunk file**.

---

### L4 - Bug 37 `midnight-rollover-abandons-unsynced-day` - **OPEN / FAIL**

**Windows** `Ensure-ConnectLogWriter` (~L259-266): on day change, Flush/Dispose writer, switch `$ConnectLogPath`, read **new** day's watermark - **never** `Sync-ConnectLogToServer` on the old path.

**Mac** `connect_log` (~L222-228): switches `CONNECT_LOG_PATH`, sets `CONNECT_LOG_SYNC_OFF=0` (does not even load new day's `.sync-offset`), **no** flush of prior file.

**Impact:** Overnight sessions leave prior-day unsynced bytes stranded locally; server day file incomplete. Overnight ERROR may never appear on server under yesterday's name.

**Fix:** Before switching: sync old path to completion (or spawn one forced sync with old path/offset). Mac must read new watermark from disk.

---

### L5 - Bug 36 `trace-debug-skip-sync-trigger` - **OPEN / FAIL** (severity depends on ops expectation)

**Location:** `Write-ConnectLog` / `connect_log` - TRACE/DEBUG return before sync; only WARN/ERROR or every 25 INFO lines sync.

**Impact:** Tunnel diagnostics often TRACE - stay laptop-local until session-end flush. Crash/kill before flush ⇒ server has no story. Local durable file exists under `~/.config/claude-connect/logs/` - **not** where docs tell admins to look first.

**Fix:** On ERROR/Unexpected always Force sync (already intended). Optionally force-sync TRACE batches on tunnel DROP / session end (already partially there). Document local path loudly.

---

### L6 - Bug 72 `concurrent-watermark-server-duplication` - **OPEN / FAIL**

**Mechanisms still live:**

1. `if ($off -gt $all.Length) { $off = 0 }` (`connect-ui.ps1`, `connect-update.ps1`) - truncated/rotated local log re-ships from 0 -> **duplicate** server content.
2. Shared day file + `.sync-offset` between `connect-ui` and `connect-update` with no file lock.
3. Win mutex fail-open (`Enter-ConnectSingleInstance` catch -> `return $true`) allows dual connect writers.
4. In-memory `$script:ConnectLogSyncOffset` can diverge from disk watermark under overlap.

**Impact:** Duplicate / interleaved server logs; harder forensics (not silent loss, but silent corruption of timeline).

**Fix:** flock/mutex around read-offset -> upload -> write-offset; don't reset to 0 without logging WARN; single writer.

---

### L7 - ERROR / Unexpected flush - **PARTIAL PASS**

| Path | Behavior |
|------|----------|
| Win `trap` -> `Write-ConnectLog ... ERROR` -> `Wait-ConnectExit` -> `Sync` + `Close-ConnectLog` | Calls sync ✓ |
| Win `Die` -> ERROR + `Close-ConnectLog` | ✓ |
| Win `Register-EngineEvent PowerShell.Exiting` -> `Close-ConnectLog` | ✓ |
| Mac early `trap ... flush_connect_log_to_server` EXIT | ✓ |
| Mac session cleanup + post-menu EXIT flush | ✓ |
| `connect.bat` bootstrap `catch {}` | **FAIL** - silent; no ERROR line if append fails |

**Caveat:** Flush **runs**, but proof #1-2 means "synced" can be a lie. Local day file is the only trustworthy durable store today.

**Empty `catch { }`** around entire `Sync-ConnectLogToServer` (ps1 L251): sync exceptions vanish - no LOG_SYNC_FAIL line.

---

## Auth findings

### A1 - Bug 13 `win-auth-skip-ignores-golden-rotation` - **STILL FAIL** (shifted locus)

`Sync-CursorGoldenAuth` **does** compare `golden-synced-at.txt` to server `exported-at` (L652-658). That part of the original bug is mitigated **inside** the sync function.

**But** `windows/connect.ps1` (~L1420-1423) outer gate:

```powershell
if (-not $Force -and -not $PostTunnelRecovery -and -not $authNeedsRefresh) {
  if ($cursorRunning -and $authComplete) { $skipAuth = $true }
}
```

`Test-CursorAuthNeedsRefresh` (**does not** check `exported-at` / `golden-synced-at` / machineid file):

- reasons: `db_missing`, `sqlite_unavailable`, `serviceMachineId_empty`, `personal_without_profile` only.

So after ~6h golden rotation, with Cursor still open and DB "complete" (stale tokens): **`skipAuth=true` -> never calls `Sync-CursorGoldenAuth` -> never sees rotation.**

Mac `cursor_auth_needs_refresh` **does** set `golden_stale` + `machineid_file_mismatch` - Win parity missing.

**Verdict:** Golden rotation skip **still possible on Win**. Harsh FAIL.

---

### A2 - Bug 45 `win-needs-refresh-misses-machineid-file` - **OPEN / FAIL**

Mac checks Electron `machineid` vs golden; Win `Test-CursorAuthNeedsRefresh` does not. Drift alone won't force refresh; skip path in Sync only heals mid when Sync actually runs (outer skip prevents that).

---

### A3 - Bug 14 `mac-o-key-dead-when-sticky-opened` - **OPEN / FAIL**

`mac/connect.sh` O handler (~L986+): only relaunches when `_editor_opened -eq 0`. If sticky `_editor_opened=1` after failed/wrong folder, **O is a no-op**. Recovery text still says "press O".

---

### A4 - Bug 43 `mac-auth-relaunch-on-skipped-failure` - **OPEN / FAIL**

On `CURSOR_AUTH_SYNC_RESULT=skipped` (golden missing / fetch fail), Mac still `export CURSOR_AUTH_RELAUNCH=1` (~L816-819). Soft-stop/kill path can fire on failure-as-skip.

---

### A5 - Bug 42 `auth-relaunch-unused-when-already-on-folder` - **OPEN** (confirm product intent)

Outer skip when editor already on folder + complete -> no Force sync / no relaunch. Combined with A1, stale tokens persist while "on folder".

---

### A6 - Bug 44 `win-code-no-isolated-profile` - **not re-verified in depth** (out of TEMP/logging core); treat as still open per BUGS unless IDE path proven.

### A7 - Bug 46 `win-build-auth-early-path-drops-auth-json-metadata` - **OPEN / FAIL**

`Build-CursorAuthValuesFromGoldenDir`: if `state-keys.json` yields `$vals.Count -gt 0`, early return copies **only** access/refresh tokens from `auth.json` - drops `cachedEmail`, stripe fields, etc. Full metadata path only when state-keys empty.

---

### A8 - AA616 / TEMP `Remove-CursorAuthTempDir` - **PARTIAL PASS**

| Site | Safe? |
|------|-------|
| `Get-RemoteCursorAuthFromGolden` -> `Remove-CursorAuthTempDir` in `finally` | **YES** - swallows errors; uses `Get-CursorAuthTempRoot` long path |
| `Merge-CursorStorageJsonFromGolden` `Remove-Item $tmp` (`$LocalPath.merge-src`) | **YES** - not 8.3 TEMP; `SilentlyContinue` |
| Skip-path `goldMidFile` under `$env:TEMP` + `Remove-Item -LiteralPath ... SilentlyContinue` | **RESIDUAL** - not routed through `Get-CursorAuthTempRoot` / `Remove-CursorAuthTempDir`; unlikely to terminate with SilentlyContinue, but **not "everywhere"** |

Empty `catch {}` in `Remove-CursorAuthTempDir` is intentional (don't abort disconnect) - OK if callers don't need cleanup failure visibility.

**Not all TEMP cleanups use the helper** -> cannot claim full AA616 closure.

---

### A9 - Silent / weak auth log paths

| Path | Logged? | Problem |
|------|---------|---------|
| Outer `skipAuth` (editor open) | `AUTH_DECISION skip=True` INFO | No `AUTH_SYNC: result ...`; no golden stamp check |
| Sync `AlreadyComplete` skip | DEBUG + INFO AUTH_SYNC | OK if Sync reached |
| `golden_missing` / `golden_read_failed` | INFO AUTH_SYNC | OK |
| `Build-...` JSON parse `catch { }` | none | Silent empty auth -> later skipped |
| `SshX "cursor-auth-sync --force" \| Out-Null` | none on fail | Server sync failure invisible |
| Mac skip editor open | step_ok only | Same outer-skip class |
| Auth messages default `Write-AuthSyncLog` DEBUG | may not sync (#36) | Auth forensics stay local |

---

## Per-bug scorecard

| Bug | Slug | Status |
|-----|------|--------|
| 11 | ssh-trailing-true-masks-append-fail | **FAIL OPEN** |
| 12 | mac-scp-ok-without-cat-advances-watermark | **FAIL OPEN** |
| 36 | trace-debug-skip-sync-trigger | **FAIL OPEN** |
| 37 | midnight-rollover-abandons-unsynced-day | **FAIL OPEN** |
| 38 | mac-tail-cmdsubst-wc-watermark-loss | **FAIL OPEN** |
| 72 | concurrent-watermark-server-duplication | **FAIL OPEN** |
| 13 | win-auth-skip-ignores-golden-rotation | **FAIL OPEN** (outer skip; Sync itself partially fixed) |
| 14 | mac-o-key-dead-when-sticky-opened | **FAIL OPEN** |
| 42 | auth-relaunch-unused-when-already-on-folder | **FAIL OPEN** |
| 43 | mac-auth-relaunch-on-skipped-failure | **FAIL OPEN** |
| 44 | win-code-no-isolated-profile | **OPEN** (not deep-proved here) |
| 45 | win-needs-refresh-misses-machineid-file | **FAIL OPEN** |
| 46 | win-build-auth-early-path-drops-auth-json-metadata | **FAIL OPEN** |
| AA616 TEMP | Remove-CursorAuthTempDir everywhere | **PARTIAL** |

---

## Why people had "no durable logs"

1. **Server** `~/.claude/logs/connect-YYYYMMDD.log` is what admins/docs point to.  
2. Watermark advances without proven `cat >>` -> client stops retrying those bytes.  
3. Mac can advance after scp alone.  
4. Midnight + TRACE gaps + empty sync `catch` deepen the hole.  
5. Local `~/.config/claude-connect/logs/` may still hold the truth - but if nobody collects it, the incident looks "logless".

**Harsh bottom line:** Logging sync is **not production-safe**. Auth TEMP cleanup is **mostly** fixed; **golden rotation skip on Win is still real** via connect.ps1 outer skip + weak `Test-CursorAuthNeedsRefresh`.

**Gate for PASS:** remove `; true` from append path; Mac gate watermark on append OK; midnight flush prior day; Win NeedsRefresh includes `golden_stale` + machineid file (Mac parity); route all auth TEMP deletes through `Remove-CursorAuthTempDir`; stop outer skip from bypassing golden stamp.

