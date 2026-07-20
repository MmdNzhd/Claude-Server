# TEST-AGENT-ADVERSARIAL.md — Agent G (error flush / fault injection)

**Date:** 2026-07-20  
**Scope:** Static adversarial contracts on Windows connect logging (no live deploy).  
**Project:** `-p claude-code-server` via laptop-exec only.  
**Runner:** `scripts/tmp/test-error-flush-contract.ps1`  
**Saved output:** `scripts/tmp/test-error-flush-contract.out`  
**Result:** **CONTRACT FAILED** — exit 1 — **pass=13 fail=3**

---

## Verdict (harsh)

Trap path on `connect.ps1` **does log and flush** (not silent-exit). Two other contracts are **HARD FAIL** and one is a real data-loss footgun:

1. **HARD FAIL — log append remote ends with `; true`**  
   Failed `cat >>` still yields ssh ExitCode 0 → `$scpOk=$true` → **watermark advances** → chunk never retried → **silent server-side log loss**.
2. **HARD FAIL — `connect-update.ps1` ERROR paths `exit 0`**  
   Six ERROR-tagged failure paths exit success (0). Callers cannot distinguish failure from skip/success. Zero ERROR→nonzero pairings found.
3. Trap / Unexpected path: **PASS** (Write-ConnectLog ERROR → Sync; Wait-ConnectExit Sync; Close-ConnectLog Sync).

---

## Contract matrix

| # | Contract | Result | Evidence |
|---|---|---|---|
| 1 | Trap calls `Write-ConnectLog` … `'ERROR'` before exit | **PASS** | `connect.ps1` trap ~L44–53: UNHANDLED + `'ERROR'` then `Wait-ConnectExit -Reason 'unhandled' -Code 1` |
| 2 | Sync/flush reachable from trap | **PASS** | ERROR → `Sync-ConnectLogToServer` in `Write-ConnectLog`; `Wait-ConnectExit` Sync; `Close-ConnectLog` Sync |
| 3 | No `; true` on log-append ssh remote | **HARD FAIL** | `connect-ui.ps1` `$cat = '…; true'` (~L227) |
| 4 | Watermark advances only on `$scpOk` | **PASS (syntax)** / **FAIL (effective)** | Gated by `if ($scpOk)` but `$scpOk` poisoned by `; true` |
| 5 | `connect-update` ERROR → nonzero exit | **HARD FAIL** | L236,237,299,302,308→310,371→372 all `exit 0` |

---

## Trap / Unexpected (code read)

```text
trap {
  Write-Host Unexpected error...
  if (Get-Command Write-ConnectLog ...) {
    Write-ConnectLog "UNHANDLED: ..." 'ERROR'   # immediate Sync for ERROR
  }
  Wait-ConnectExit -Reason 'unhandled' -Code 1  # Sync again + Close-ConnectLog
}
```

Notes:

- Name is `Write-ConnectLog`, not `Write-Log`.
- Trap is registered **before** `connect-ui.ps1` is dot-sourced (~L174). Early failures (pre-UI) skip log/Sync (Get-Command guard) but still hit `Wait-ConnectExit` only if that function exists — **pre-UI Die/Wait may be fragile**. After Initialize-ConnectLog, trap path is sound.
- `Die()` also Write-ConnectLog ERROR + `Close-ConnectLog` + Wait-ConnectExit.

**Missing trap flush?** No (post-UI). **Not a HARD FAIL** for trap itself.

---

## Watermark simulation (failed append)

| Step | Code behavior | Failed append? |
|---|---|---|
| mkdir ssh ends `; true` | mkdir probe always Ok if ssh connects | N/A |
| scp chunk | real exit code | if scp fails → no offset bump **OK** |
| cat append ssh ends `; true` | **always ExitCode 0** | append fail still Ok |
| `if ($scpOk) { offset = off+take; Write watermark }` | advances | **YES — advances on failed append** |

**Documented answer:** Failed append **does advance** the sync-offset under current code, because success is inferred from ssh exit code and the remote command forces success with `; true`. Local day file is kept; server gap is permanent until manual re-ship.

Fix direction (not applied — no live deploy / no prod edit this agent): drop trailing `; true` from `$cat` (and preferably `$mk`); check exit of `cat >>` before `rm`; only then set `$scpOk`.

---

## connect-update.ps1 fail paths

Intentional soft-exit pattern (update is best-effort from bat), but **adversarial contract rejects it**:

- `ssh_missing` / `scp_missing` → ERROR + `exit 0`
- `manifest_empty_or_unreachable` / `manifest_zero_files` → ERROR + `exit 0`
- `download_failed` / `incomplete_files` → ERROR + `exit 0`

Only success-relaunch uses `exit 2`. **No `exit 1` near ERROR.**

---

## Artifacts

| Path | Role |
|---|---|
| `scripts/tmp/test-error-flush-contract.ps1` | Temporary contract runner (exit 1 on fail) |
| `scripts/tmp/test-error-flush-contract.out` | Saved run output |
| `scripts/tmp/TEST-AGENT-ADVERSARIAL.md` | This report |

Skipped `test-git-mode-deep.ps1` (prefer unique script; avoid Agent B conflict).

---

## Reproduce

```bat
cd /d D:\Smart\Claude-Code-Server
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\tmp\test-error-flush-contract.ps1
```

Expect exit code **1** until `; true` removed from append path and update ERROR exits are nonzero (or contract intentionally softened).
