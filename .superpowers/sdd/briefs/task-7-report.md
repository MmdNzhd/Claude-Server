# Task 7 Report: Wire tests + docs + incident contract suite

**Status:** DONE  
**Branch:** `fix/zombie-owner-reseed-gap`  
**Commit:** `test(connect): wire Gap suites, incident contract, and docs markers` (branch tip)  
**DoD:** D8 + D9

## Summary

Registered all Gap suites in `run-all.ps1`, added `test-incident-gap-replay-contract.ps1` (S2 Win/Mac tokens + Ensure/Wait order + S6 A–E source contracts), documented Gap daylog markers in `docs/client-connect.md`, extended hard-multi-agent coexistence asserts, and got `run-deploy-gate.ps1` green with **no** `-SkipTests`. No version bump for ship (Task 8); ConnectVersion lockstep restored to `20260729.14` to match `connect-version.txt` / Mac (fixes Task 1 strip drift).

## Changes

| File | Change |
|---|---|
| `scripts/client/tests/run-all.ps1` | Register 6 Gap suites |
| `scripts/client/tests/test-incident-gap-replay-contract.ps1` | **New** — S2 + Ensure gate-before-kill + Wait local-R + S6 A–E |
| `scripts/client/tests/test-hard-multi-agent-regressions.ps1` | Gap tokens coexist with keep-alive |
| `docs/client-connect.md` | Zombie-owner / reseed Gap marker table under Logging |
| `scripts/client/windows/connect.ps1` | `ConnectVersion` → `20260729.14` (lockstep; not a Task 8 bump) |
| `scripts/client/tests/test-never-again-ship-gates.ps1` | HealBlackhole caller asserts → sidecar/BootReap (no connect drive-by) |
| `scripts/client/tests/test-sidecar-front-flap.ps1` | Mac heal/force-clear asserts → connect.sh / sidecar / editor-launch |
| `scripts/client/tests/test-versioned-layout.ps1` | Extract `Test-VersionSrcStructural` before Complete |

## Deploy-gate evidence

```
Command: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\client\tests\run-deploy-gate.ps1
Log:     publish/_task7-deploy-gate.log

=== Deploy gate summary ===
  Passed: 132
  Failed: 0
  Skipped live: *-live.ps1 / *-live-* / harder-live* (not run)
  Skipped EXE-seed / desktop / Sepidz publish suites (scripts-only deploy)
  Skipped slow MCP: storm / chaos / brutal (not run on deploy gate)

Deploy gate passed.
```

New Gap suites in gate log (all PASS):

- `reseed-canbindl-gate` — 26 asserts  
- `wait-local-r-ownership` — 15 asserts  
- `stale-forward-wait-init` — 24 asserts  
- `proxy-owner-service-coupling` — 38 asserts  
- `local-tunnel-ssh-pids` — 32 asserts  
- `incident-gap-replay-contract` — 46 asserts  

## S2 tokens (incident suite)

All six present on Win `git-mode.ps1` + Mac `git-mode.sh`; `foreign_owner_cannot_bind` also in `connect.ps1` bg_init:

`foreign_owner_cannot_bind`, `local_r_not_owned`, `stale_port_busy`, `reason=service_dead`, `stale_non_connect`, `soft_fail_exhausted_zombie_drop`

## Concerns / deferrals

- Live Gap replay daylog quotes (S6 A–E / D10) remain **Task 8**.
- HealBlackhole stays sidecar/boot-owned; Task 7 did not re-wire callers (matches Task 1 strip + brief “no HealBlackhole drive-by”).
- Working tree still has unrelated VerDir/EXE/publish dirt — **not** included in Task 7 commit scope beyond gate-required test lockstep fixes.
