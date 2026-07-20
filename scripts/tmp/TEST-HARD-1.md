# TEST-HARD-1 — Agent T1 Hard Test Report

**Project:** `claude-code-server` (laptop-exec only, no deploy)  
**Date:** 2026-07-20  
**Tunnel:** UP (Smart / Windows, port 21002)

---

## 1. `test-connect-pipeline.ps1`

**Command:** `powershell -NoProfile -File scripts/client/tests/test-connect-pipeline.ps1`

| Field | Value |
|---|---|
| **Verdict** | **FAIL** (misleading exit code) |
| **Exit code** | `0` |
| **Main pipeline asserts** | All PASS (~90 checks) |
| **Embedded session-log block** | 1 FAIL (dot-sourced) |

**Key FAIL lines:**

```
FAIL silent update fn
FAILED 1
All tests passed.
```

**Notes:**

- Script dot-sources `test-session-log-contracts.ps1`, which reports `FAILED 1`, yet parent prints `All tests passed.` and exits `0`.
- Dot-sourced `exit 1` does not terminate the parent process — exit code is **misleading**.
- Honest result: **FAIL** due to session-log contract failure despite exit 0.

---

## 2. `test-session-log-contracts.ps1`

**Command:** `powershell -NoProfile -File scripts/client/tests/test-session-log-contracts.ps1`

| Field | Value |
|---|---|
| **File exists** | Yes |
| **Verdict** | **FAIL** |
| **Exit code** | `1` |

**Output:**

```
PASS bat RUN_ID
PASS Get-ConnectSessionId
PASS sessions.index
PASS SESSION_FILTER
FAIL silent update fn
PASS win hooks silent
PASS TUNNEL_DROP
PASS mac RUN_ID
PASS mac silent
PASS mac SESSION_FILTER
PASS git silent
FAILED 1
```

**Key FAIL line:** `FAIL silent update fn`

**rg symbol assertions** (`laptop-exec rg … scripts/client/`):

| Symbol | Status | Location |
|---|---|---|
| `Get-ConnectSessionId` | PASS (defined) | `connect-ui.ps1:26` |
| `SESSION_FILTER` | PASS (defined) | `connect-ui.ps1:184`, `connect-ui.sh:525` |
| `Invoke-ConnectSilentUpdateCheck` | **FAIL (not defined)** | Referenced only in `connect.ps1:644-645`; **missing from `connect-ui.ps1`** |

Mac/bash counterpart `invoke_connect_silent_update_check` exists in `connect-ui.sh:261` but Windows `Invoke-ConnectSilentUpdateCheck` was never added to `connect-ui.ps1`.

---

## 3. Static: curly quotes in `connect.ps1`

**Pattern:** `[\u201C\u201D\u2018\u2019]`

| Check | Verdict | Exit |
|---|---|---|
| Python UTF-8 scan of `scripts/client/windows/connect.ps1` | **PASS** | `0` |
| Embedded test in `test-connect-pipeline.ps1` (`has no smart/curly quotes`) | **PASS** | — |

No curly/smart quotes found.

---

## OVERALL VERDICT: **FAIL**

| Test | Exit | Honest |
|---|---|---|
| test-connect-pipeline.ps1 | 0 | **FAIL** (session contract + misleading exit) |
| test-session-log-contracts.ps1 | 1 | **FAIL** |
| Static curly quotes | 0 | **PASS** |
| rg symbol presence | — | **FAIL** (`Invoke-ConnectSilentUpdateCheck` undefined) |

**Root cause:** `connect-ui.ps1` lacks `Invoke-ConnectSilentUpdateCheck` (and likely `UPDATE_SILENT` logging) while `connect.ps1` calls it via `Get-Command`. Mac/bash path is implemented; Windows PowerShell path is not.

**Secondary issue:** `test-connect-pipeline.ps1` reports `All tests passed.` with exit 0 after dot-sourced session-log failures — harness bug.
