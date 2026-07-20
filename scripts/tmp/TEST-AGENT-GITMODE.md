# HARD TEST Agent B — git-mode deep

| Field | Value |
|---|---|
| Command | `laptop-exec run -p claude-code-server -- cmd /c "powershell ... test-git-mode-deep.ps1"` (captured via RedirectStandardOutput helper) |
| Project | `-p claude-code-server` |
| Deploy | **NONE** (not run) |
| Full output | `scripts/tmp/TEST-GITMODE-OUT.txt` |
| **Exit code** | **0** |
| PASS count | 154 |
| FAIL count | 0 |
| Verdict | **PASS** (not HARD FAIL) |

## Failures

**None.** No `FAIL` assert lines. Script ended with `All deep git-mode tests passed.`

## Bug-fix regressions (softfail DROP, banner, recover)

All targeted regressions **held** (assert PASS):

### softfail DROP (tunnel sync when TCP open, no process)

| Assert | Result |
|---|---|
| `mac tunnel sync soft-fails when TCP is open without a process handle` | PASS |
| `mac tunnel sync debounces consecutive failures` | PASS |
| `git-mode.sh honors Q on tunnel drop` | PASS |

### banner

| Assert | Result |
|---|---|
| `git-mode.ps1 has tunnel banner cache` (`Clear-TunnelBannerCache`) | PASS |

### recover

| Assert | Result |
|---|---|
| `cmd_recover loads global config` | PASS |
| `claude-mount has recover-one command` | PASS |
| `mac auto recovery logs RECOVERY_SKIP_CLEAR_MOUNT when editor stays open` | PASS |
| `mac\connect.sh calls begin_connect_recovery on reconnect` | PASS |
| `mac\connect.sh forces cursor auth after recovery` | PASS |
| `mac\connect.sh logs recovery tags` | PASS |
| `git-mode.sh has begin_connect_recovery` | PASS |
| `claude-mount recover-if-needed applies off restore` | PASS |
| `git-mode.ps1 recover applies off when mount ok` | PASS |

## HARD FAIL gate

HARD FAIL if any assert fails → **not triggered** (exit 0, FAIL=0).

