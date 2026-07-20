# TEST-AGENT-MOUNT-HARD — Agent P (wave2)

**Verdict: HARD PASS**

Date: 2026-07-20  
Project: `-p claude-code-server`  
Tooling: laptop-exec only

## 1. bash -n (Git bash)

| Script | Result |
|--------|--------|
| `scripts/server/claude-mount.sh` | PASS |
| `scripts/server/claude-watchdog.sh` | PASS |
| `scripts/server/claude-automount.sh` | PASS |

## 2. `scripts/tmp/test-mount-contracts.ps1`

Runner exit: **0** — HARD PASS (all contracts)

| Contract | Result | Evidence |
|----------|--------|----------|
| Restore must NOT `Remove-Item -Recurse` `.git` (protect real git) | PASS | No `-Recurse` on `.git`; `_restore_git_body` is rename-only |
| Watchdog tunnel DOWN restores `.git` from `.git.server-session` before/with umount | PASS | DOWN branch calls `"$MOUNT_BIN" down` before fallback umount loop |
| Empty `ACTIVE_MOUNT` does not pick first alphabetical project conf | PASS | No alphabetical last-resort in watchdog `_infer_active` / automount infer |
| `TUNNEL_PORT` CR strip in mount load path | PASS | `_load_global` strips via `tr -d '\r'` (parity with watchdog) |
| Worktree `.git` file skipped in hide | PASS | `hide_try` uses `Test-Path ... -PathType Leaf` → `GIT_HIDE:skip` |

## 3. `test-server-tunnel-check.sh`

- Location: `scripts/client/tests/test-server-tunnel-check.sh`
- Ship file has CRLF (`set -o pipefail\r` breaks raw bash); runnable after LF normalize
- Ran LF copy `scripts/client/tests/_tsc-lf.sh` → **OK test-server-tunnel-check.sh** (exit 0)

## Summary

- bash -n: PASS (3/3)
- mount contracts: PASS (5/5)
- tunnel static check: PASS (after CRLF strip)

**HARD PASS** — no contract misses.
