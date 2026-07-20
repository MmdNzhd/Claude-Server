# HARD TEST Agent C — Update + Publish

**Date:** 2026-07-20  
**Project:** `-p claude-code-server` (laptop-exec only)  
**Deploy:** none (no `publish.ps1` live deploy, no server deploy)  
**Verdict: HARD FAIL**

---

## 1. `test-publish.ps1`

**Command:**
```
laptop-exec run -p claude-code-server -- cmd /c "powershell -NoProfile -ExecutionPolicy Bypass -File D:\\Smart\\Claude-Code-Server\\scripts\\client\\tests\\test-publish.ps1"
```

| Result | Value |
|--------|-------|
| **Exit code** | **1** |
| Failures | **14** |
| Passes | majority of asserts (see below) |

### Failed asserts (14)

1. `main publish folder has no claude-automount.sh`
2. `main has exactly 18 client files (got 22)`
3. `sepidz publish folder has no claude-automount.sh`
4. `sepidz ...\claude-code\mac\connect.sh` contains forbidden `claude-server-sepidz`
5. `sepidz ...\claude-code\windows\connect.ps1` contains forbidden `claude-server-sepidz`
6. `sepidz ...\designer\mac\connect.sh` contains forbidden `claude-server-sepidz`
7. `connect.ps1 differs only by SERVER_IP`
8. `connect.sh differs only by SERVER_IP`
9. `binary identical: mac\connect-version.txt`
10. `binary identical: mac\git-mode.sh`
11. `binary identical: windows\connect-ui.ps1`
12. `binary identical: windows\connect-version.txt`
13. `binary identical: windows\git-mode.ps1`
14. `connect.ps1 size delta = IP length diff (-1 bytes)`

**Note:** Failures are against Desktop publish folders (`C:\Users\Smart\Desktop\claude-publish\...`), not a fresh `publish.ps1` run in this session. Stale/out-of-policy Zip contents likely.

---

## 2. Update-related tests found

| Script | Purpose | Ran? | Exit |
|--------|---------|------|------|
| `test-connect-update-desktop.ps1` | Version compare + Desktop smoke; optional SSH to `claude-server` bundle | Yes (1st run completed; 2nd hung on optional SSH probe → killed) | **0** (1st run) |
| `test-client-auto-update.sh` | Offline bundle/manifest/version/sim update + bash -n | Yes | **0** (17/17 PASS) |
| `test-connect-update-quick.ps1` | Calls live `connect-update.ps1` via SSH/SCP | **No** — live update path; not required for offline asserts |
| `test-connect-update-e2e.ps1` | Live E2E; expects `exit=2` + hardcoded `20260713.26` | **No** — live SSH + stale expected version; would not validate current `20260719.31` |
| Pipeline (`test-connect-pipeline.ps1` / `test-pipeline-deep.ps1` / `run-all.ps1`) | No matches for `update-exit\|applied_ok\|checksum\|rollback\|connect-update` | N/A — **no update asserts in pipeline** | — |

### Desktop smoke (exit 0)

- PASS version compare `.26 > .25`, `.9 not > .10`
- PASS `connect-update.ps1` on Desktop, `connect.bat` hook, Desktop version sync (`20260714.2`)
- Optional server bundle check: SKIP or hang (SSH `claude-server`); not a hard fail in script when unreachable

### Auto-update integration (exit 0)

- Bundle v`20260719.31`, version sync across ps1/sh/txt
- Manifest required files, simulated update `20260701.1 → 20260719.31`
- Hooks + `bash -n` on deploy/update/connect scripts

---

## 3. `update-exit` / `checksum` / `rollback` / `applied_ok`

**Search:** `laptop-exec rg -p claude-code-server "update-exit|applied_ok|checksum|rollback" scripts/client/tests` → **no matches** in tests (exit 1 / no hits).

| Concept | In implementation? | Asserted by a test? |
|---------|--------------------|---------------------|
| `applied_ok` | Yes — Win `connect-update.ps1` logs `applied_ok need_relaunch exit=2` then `exit 2` | **No** dedicated unit assert (only E2E expects `rc -eq 2`, skipped) |
| Success exit **2** (need relaunch) | Win + Mac (`exit 2`) | E2E only (skipped); desktop/auto-update do **not** assert exit 2 |
| `checksum` | **Not found** in `connect-update.ps1` / `.sh` | **No** |
| `rollback` | **Not found** | **No** |
| `update-exit` string | **Not found** in tests | **No** |

### ERROR → nonzero — is it asserted?

**No. Opposite behavior is implemented and untested for nonzero.**

Windows `connect-update.ps1` logs level `ERROR` then **`exit 0`** on soft failures so connect can continue, including:

- `ssh_missing` / `scp_missing`
- `manifest_empty_or_unreachable` / `manifest_zero_files`
- `download_failed` / `incomplete_files=...`

No test asserts that ERROR log level produces a nonzero process exit. Hard success path is `exit 2` (`applied_ok`), not nonzero-on-ERROR.

Mac `connect-update.sh` similarly exits `0` on unreachable/fail paths; success = `exit 2`.

---

## 4. Summary table

| Suite | Exit | Status |
|-------|------|--------|
| `test-publish.ps1` | **1** | **FAIL** (14 asserts) |
| `test-connect-update-desktop.ps1` | 0 | PASS (local asserts; SSH optional) |
| `test-client-auto-update.sh` | 0 | PASS (17) |
| Update exit/checksum/rollback unit coverage | — | **GAP** (no checksum/rollback; ERROR≠nonzero; applied_ok/exit=2 not unit-tested) |
| Pipeline update asserts | — | **absent** |

---

## HARD FAIL

**Agent C overall: FAIL** because `test-publish.ps1` exited **1** with **14** failures.

Update offline/smoke suites passed; coverage gaps remain for checksum, rollback, and ERROR→nonzero (design is ERROR→exit 0).
