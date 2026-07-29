# Task 6 Report: Harden Get-LocalTunnelSshPids regex

## Status: DONE

## Summary

Implemented a shared local ssh `-R` forward matcher on Windows and Mac so `Get-LocalTunnelSshPids` / Mac pid enumeration accept all required reverse-forward forms and reject wrong-port and non-forward matches. Foundation for Wait Gate A (Task 2).

## DoD checklist

| Requirement | Status | Evidence |
|---|---|---|
| Accept `-R PORT:localhost:22` | PASS | test pass row `space localhost` |
| Accept `-R PORT:127.0.0.1:22` | PASS | test pass row `space 127.0.0.1` |
| Accept `-R=PORT:localhost:22` | PASS | test pass row `equals localhost` |
| Reject wrong port | PASS | test fail row `wrong port`; behavioral pid=103 |
| Reject without `-R` | PASS | fail rows `-L`, bare, hostkey |
| Win+Mac shared matcher | PASS | `Test-LocalTunnelSshCommandLine` + `test_local_tunnel_ssh_command` |
| Used by Get-LocalTunnelSshPids | PASS | Win CIM scan uses matcher; Mac `get_local_tunnel_ssh_pids` |

## Implementation

### Windows (`scripts/client/git-mode.ps1`)

Added:

- `Get-LocalTunnelSshReverseRegex` — regex for `-R(?:\s*=\s*|\s+)PORT:(localhost|127.0.0.1):22`
- `Test-LocalTunnelSshCommandLine` — shared matcher (rejects `ssh-keygen` false positives)
- `Get-LocalTunnelSshReversePortFromCommandLine` — port extraction for pid map

Updated consumers:

- `Get-LocalTunnelSshPids` — uses `Test-LocalTunnelSshCommandLine`
- `Get-LocalTunnelPortPidMap` — uses port extractor
- `Get-TunnelSshProcess` — uses matcher
- legacy `-D` cleanup — broadened any-port `-R` regex

### Mac (`scripts/client/git-mode.sh`)

Added:

- `test_local_tunnel_ssh_command` — case-based matcher (3 required forms + ssh-keygen reject)
- `get_local_tunnel_ssh_pids` — pgrep ssh + filter via matcher

Replaced inline `pgrep -f "ssh.*-R ${port}:localhost:22"` at:

- `remove_local_orphan_tunnel`
- `stop_session_tunnel_cleanup`
- `tunnel_port_has_local_reverse`
- hygiene scan loops (2 sites)
- legacy `-D` cleanup host check broadened

## Tests

### New suite: `scripts/client/tests/test-local-tunnel-ssh-pids.ps1`

- 4 static asserts (function presence Win+Mac)
- 4 pass rows (required forms + double-space tolerance)
- 7 fail rows (wrong port, wrong dest, `-L`, bare, ssh-keygen, wrong host, `-R` concat)
- 5 behavioral asserts with stubbed `Get-CimInstance`

### Run result

```
All local-tunnel-ssh-pids tests passed (20 asserts).
```

RED→GREEN: initial run failed on `ssh-keygen -R` false positive; fixed by excluding `ssh-keygen` in both matchers. Re-run GREEN.

### Not run (out of scope for Task 6)

- Full `run-all.ps1` (registration deferred to Task 7)
- `run-deploy-gate.ps1`
- Version bump / deploy (Task 8)

## Commit

```
c3a5a86 fix(connect): harden local ssh -R PID matcher for all forward forms
```

Files committed (only task scope):

- `scripts/client/git-mode.ps1`
- `scripts/client/git-mode.sh`
- `scripts/client/tests/test-local-tunnel-ssh-pids.ps1`

## Concerns / follow-ups

1. **run-all.ps1 registration** — deferred to Task 7 per plan.
2. **`-R=PORT:127.0.0.1:22`** — not in brief required list; Mac case matcher does not accept it (Win regex would). Low risk; actual spawn uses `-R PORT:localhost:22`.
3. **Mac bash syntax** — `bash -n` unavailable on this Windows shell; manual review of `remove_local_orphan_tunnel` fi nesting after edit.

## Self-review vs brief

All three brief steps complete. Matcher hardened before Task 2 Wait Gate A. No connect.ps1, version, or unrelated test changes.

---

## Task 6 review fix (2026-07-29)

### Status: DONE

Addressed Critical/Important findings from task-6-review.md.

| Finding | Fix |
|---|---|
| CRITICAL: out-of-scope Complete-CursorProxy HealBlackhole/force-clear in c3a5a86 | Reverted `Complete-CursorProxyAfterTunnel` (ps1) and `complete_cursor_proxy_after_tunnel` (sh) to match BASE `2bcc983`; matcher helpers retained |
| IMPORTANT: Mac test was name-only static assert | Added WSL bash harness in `test-local-tunnel-ssh-pids.ps1` — same 11 pass/fail rows exercised via extracted `test_local_tunnel_ssh_command` |
| Mac `-R=PORT:127.0.0.1:22` parity | Mac matcher switched to `grep -E` regex aligned with Win `\b` boundary semantics |

### Sanity check vs BASE 2bcc983

- `Complete-CursorProxyAfterTunnel`: function body matches BASE (line offset only); no `HealBlackhole` / force-clear references remain
- `complete_cursor_proxy_after_tunnel`: `fc` vs BASE — no differences

### Test run

```
All local-tunnel-ssh-pids tests passed (32 asserts).
```

(20 Win asserts + 11 Mac harness asserts + 1 Mac harness clean exit)

### Commit

```
c5fc940 fix(connect): scope Task 6 matcher commit; Mac table coverage
```
