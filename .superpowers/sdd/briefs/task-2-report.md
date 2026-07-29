# Task 2 Report: Wait-ForTunnelUp local `-R` ownership (Gate A)

**Status:** DONE  
**Branch:** `fix/zombie-owner-reseed-gap`  
**Commit:** `91bda73` — `fix(connect): require spawn pid owns local -R before Wait success`

## Summary

`Wait-ForTunnelUp` / Mac `wait_for_tunnel_up` (+ `poll_tunnel_with_progress`, which Ensure actually calls) no longer treat banner/`Test-TunnelUp` alone as success. Spawn pid must appear in `Get-LocalTunnelSshPids` / `get_local_tunnel_ssh_pids`. Empty local PID list is fail-closed. Fail path logs `reason=local_r_not_owned`.

## Changes

| File | Change |
|---|---|
| `scripts/client/git-mode.ps1` | Gate A inside `Wait-ForTunnelUp`; empty/foreign locals continue 12-attempt loop then fail with token |
| `scripts/client/git-mode.sh` | Same Gate A in `wait_for_tunnel_up` and `poll_tunnel_with_progress` |
| `scripts/client/tests/test-wait-local-r-ownership.ps1` | Static + behavioral (empty => false; owned => true; foreign => false) |

## Contracts satisfied

- **D3:** `Test-TunnelUp=$true` + empty local PIDs => Wait `$false`
- **S2 token:** `local_r_not_owned` on Win Wait and Mac wait/poll
- **S4:** Behavioral stub path; Start-Sleep stubbed for speed; Gate A not removed
- **S5:** No banner-only success path remains in Wait

## Tests

| Suite | Result |
|---|---|
| `test-wait-local-r-ownership.ps1` | PASS (15 asserts) — TDD red then green |
| `test-reseed-canbindl-gate.ps1` | PASS (26 asserts) |
| `test-local-tunnel-ssh-pids.ps1` | PASS (32 asserts) |

## Concerns

- Not registered in `run-all.ps1` (Task 7 owns registration).
- No version bump / deploy in this task.
- Mac Ensure calls `poll_tunnel_with_progress` (not `wait_for_tunnel_up`); both got Gate A for runtime parity.

## Review fix (Mac timeout WARN parity)

**Issue:** Task 2 review — Mac `wait_for_tunnel_up` / `poll_tunnel_with_progress` dropped pure-timeout final WARN when Gate A never tripped; Win still emits `TUNNEL_WAIT fail=1 reason=timeout`.

**Fix:** Both Mac wait functions now mirror Win `if/else`: `local_r_not_owned` => fail token; else => `reason=timeout` before `release_stale_tunnel_port`. Gate A unchanged.

**Commit:** `46f7acc`

**Re-test:** `test-wait-local-r-ownership.ps1` PASS (15 asserts).
