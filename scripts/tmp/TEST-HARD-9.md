# TEST-HARD-9 — Client Auto-Update Hard Verification

| Field | Value |
|---|---|
| Agent | T9 (subagent) |
| Project | `claude-code-server` (`-p claude-code-server`) |
| Date (UTC) | 2026-07-20T08:23:01Z |
| Method | Static + contract scripts; **no deploy**, **no live SSH e2e** |
| Tunnel | UP (port 21002, laptop Smart/windows) |
| active_mount | `ai-gap-summay` (workspace ≠ mount; all I/O via `-p`) |

---

## Executive Summary

**OVERALL (CODE): PASS**

All runnable contract/integration scripts passed. Static inspection confirms checksum verification, staged directory swap with rollback, `IdentityAgent=none`, relaunch depth bounds in both launchers, and quiet-update paths on Windows (`-Quiet`) and Mac (`CLAUDE_CONNECT_UPDATE_QUIET`).

No product (`CODE_FAIL`) issues found. No environment blockers (`ENV_FAIL`) encountered in this run.

---

## 1. Runnable Tests

### 1.1 `scripts/tmp/test-update-exit-contract.ps1`

**Host:** laptop (PowerShell)  
**Exit:** 0  
**Result:** 20 pass, 0 fail

Validates that ERROR log markers in `connect-update.ps1` and `connect-update.sh` are followed by nonzero exits (not `ERROR; exit 0`). Covers: `ssh_missing`, `scp_missing`, manifest failures, `download_failed`, `incomplete_files`, `apply_rollback`, and checksum-fail → caller `exit 1`.

### 1.2 `scripts/client/tests/test-client-auto-update.sh`

| Host | python3 | Exit | Pass/Fail |
|---|---|---|---|
| Linux server (cwd repo mount) | `/usr/bin/python3` present | 0 | 25/0 |
| Laptop via `laptop-exec run … bash` | available (Git Bash) | 0 | 25/0 |

**Note:** If `python3` were missing, version-compare tests inside this script would fail — classify as **ENV_SKIP** (not CODE_FAIL). Both environments had python3; full suite ran.

Integration coverage includes: bundle build, version sync (`20260719.31`), manifest contents, simulated update, hook wiring, static grep guards, and `bash -n` syntax on deploy/update shell scripts.

---

## 2. Static Verification (no live SSH)

### 2.1 Checksums verify

| Layer | Mechanism | Status |
|---|---|---|
| **Deploy** (`deploy-client-bundle.sh`) | Writes `checksums.txt` via `sha256sum`/`shasum`; excludes self | PASS |
| **Win client** (`connect-update.ps1`) | `Test-BundleChecksums`; missing file → WARN skip; mismatch → ERROR + `exit 1` | PASS |
| **Mac client** (`connect-update.sh`) | `_verify_checksums`; same semantics | PASS |

### 2.2 Staged swap / rollback

| Layer | Pattern | Status |
|---|---|---|
| **Deploy** | `STAGE_BUNDLE` → rename-swap → rollback on promote failure | PASS |
| **Win client** | `.client-update-new` / `.client-update-bak`; `Swap-LiveDir` + `Restore-FromBak`; `apply_rollback` → `exit 1` | PASS |
| **Mac client** | `_swap_dir` with inline rollback; windows+mac sequential swap with cross-restore on mac failure | PASS |
| **Comment contract** | PS1: "never in-place Copy-Item" on live tree | PASS |

### 2.3 `IdentityAgent=none`

| File | Occurrences | Status |
|---|---|---|
| `windows/connect-update.ps1` | `$script:SshCommonOpts`, scp opts, log-upload scp | PASS |
| `mac/connect-update.sh` | `SSH_EXTRA_OPTS` | PASS |

### 2.4 `CLAUDE_CONNECT_UPDATE_DEPTH` relaunch bound

| Launcher | Bound | Max relaunches | Status |
|---|---|---|---|
| `windows/connect.bat` | `GEQ 3` after increment on exit code 2 | 2 | PASS |
| `mac/connect.sh` | `_upd_depth -ge 2` before increment+exec on exit 2 | 2 | PASS |

Asymmetry in comparison operator (`GEQ 3` vs `-ge 2`) is intentional equivalent: both cap at two post-update relaunches.

### 2.5 Quiet switch / silent update

| Platform | Mechanism | Wired from UI | Status |
|---|---|---|---|
| Windows | `[switch]$Quiet` → `Write-UpdateMsg` no-op | `connect-ui.ps1` passes `-Quiet` | PASS |
| Mac | `CLAUDE_CONNECT_UPDATE_QUIET=1` → `UPDATE_QUIET` → `_update_msg` no-op | `connect-ui.sh` sets env | PASS |

Mac uses env var instead of CLI switch; both platforms suppress update chatter when invoked from connect UI.

### 2.6 Additional static checks

| Check | Status |
|---|---|
| `connect-update.ps1` PowerShell parse | PASS |
| `connect-update.sh` `bash -n` (laptop) | PASS |
| `update-server.sh` `VERIFY_OK` → `exit 1` on verify failure | PASS |
| `publish/deploy-client-bundles.ps1` manifest UTF-8 no BOM | PASS (via integration grep) |
| Exit code contract documented: 0=continue, 1=ERROR, 2=relaunch | PASS (both update scripts) |

---

## 3. Explicitly NOT Tested (by design)

| Item | Classification |
|---|---|
| Live `scp`/`ssh` download from server bundle | Skipped — flaky e2e; not CODE_FAIL |
| `sudo claude-server deploy-client-bundle` | Skipped — user requested no deploy |
| Post-deploy bundle on `/usr/local/share/claude-client` | Skipped — no deploy |

---

## 4. ENV_FAIL

| Item | Status | Notes |
|---|---|---|
| Tunnel DOWN | **OK** | UP for laptop-exec |
| python3 missing | **OK** | Present on server + laptop; integration tests not skipped |
| Git Bash / bash on laptop | **OK** | `test-client-auto-update.sh` ran via laptop-exec |
| PowerShell on laptop | **OK** | Exit contract script ran cleanly |
| SSHFS stale for `claude-code-server` | **N/A** | SSH-first; `-p` used throughout |

**ENV_FAIL count: 0**

---

## 5. CODE_FAIL

No failures. All contract assertions, integration greps, and static invariants satisfied.

**CODE_FAIL count: 0**

---

## 6. OVERALL (CODE)

```
PASS — safe to treat update hardening as verified offline.
```

Re-run live e2e only when tunnel stability is acceptable; this hard test intentionally avoids that layer.

---

## Commands Executed

```bash
# Exit contract (laptop)
laptop-exec run -p claude-code-server -- powershell -NoProfile -ExecutionPolicy Bypass \
  -File scripts/tmp/test-update-exit-contract.ps1

# Integration (server)
bash scripts/client/tests/test-client-auto-update.sh

# Integration (laptop)
laptop-exec run -p claude-code-server -- bash -lc "bash scripts/client/tests/test-client-auto-update.sh"

# Syntax
laptop-exec run -p claude-code-server -- bash -n scripts/client/mac/connect-update.sh
laptop-exec run -p claude-code-server -- powershell -NoProfile -Command "<Parser.ParseFile connect-update.ps1>"
```

