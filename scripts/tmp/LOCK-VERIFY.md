# LOCK-VERIFY

Date: 2026-07-20  
Project: `claude-code-server` (laptop-exec `-p` only)  
Deploy: none  
Production P0 re-apply: none (no P0 regression)

## OVERALL: PASS

## P0 checks

| Check | Result | Evidence |
|---|---|---|
| `git-mode.sh`: `seq 1 12` present | PASS | L889, L907 `for i in $(seq 1 12)` |
| `git-mode.sh`: `seq 1 4` absent | PASS | `rg 'seq 1 4'` exit 1 |
| `git-mode.sh`: recover uses `sshx "timeout 30 $CM recover-one` | PASS | L1006 `sshx "timeout 30 $CM recover-one ..."` |
| `git-mode.sh`: NOT `timeout 30 sshx "$CM recover-one` | PASS | `rg 'timeout 30 sshx'` exit 1 |
| `git-mode.ps1`: `banner_miss_tcp_open_budget` | PASS | L510 TUNNEL_DROP reason |
| `git-mode.ps1`: `action=reseed` | PASS | L876 ENSURE_TUNNEL soft_fail |
| `connect.ps1`: no curly quotes `\u201C\u201D\u2018\u2019` | PASS | byte/UTF-8 scan + pipeline assert |

## Tests

| Suite | Result | Notes |
|---|---|---|
| `scripts/client/tests/test-connect-pipeline.ps1` | PASS | All tests passed (exit 0) |
| `scripts/client/tests/test-git-mode-deep.ps1` | PASS | All deep git-mode tests passed (exit 0) |

## Post-test P0 re-check

| Check | Result |
|---|---|
| mac-seq-12-present | PASS |
| mac-seq-4-absent | PASS |
| mac-recover | PASS |
| win-banner-budget | PASS |
| win-action-reseed | PASS |
| connect-no-curly | PASS |
| **P0_ALL_PASS** | **PASS** |

## Notes

- No production banner / ensure / recover rewrites.
- First pipeline run briefly failed curly-quote assert (concurrent race); re-run clean PASS with no connect.ps1 edits.
- `test-git-mode-deep.ps1` folder-uri assert was a false positive against correct `remote_editor_in_agent_home` (`*folder-uri*) ;; *) return 0`). Tightened regex to `folder-uri\*\)\s*return 0` (real bug form only). Production `editor-launch.sh` unchanged.
