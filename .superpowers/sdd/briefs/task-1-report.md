# Task 1 Report: ReseedEffective / CanBindL gate

**Status:** DONE  
**Branch:** `fix/zombie-owner-reseed-gap`  
**Commit:** `6a178c2` — `fix(connect): skip proxy reseed kill when foreign owner cannot bind -L`

## Summary

Under Gap (`ReseedRaw AND NOT CanBindL`), Ensure and bg_init no longer kill `-R` / set `needReseed` for proxy reseed. Kill only proceeds when `Test-ProxyReseedShouldKill` / `proxy_reseed_should_kill` is true (ReseedRaw + CanClaim).

## Changes

| File | Change |
|---|---|
| `scripts/client/git-mode.ps1` | `Test-CanClaimCursorProxyOwner`, `Test-ProxyReseedShouldKill`; Claim adopts `stale_non_connect`; Ensure 4 fallthroughs use chokepoint |
| `scripts/client/git-mode.sh` | `can_claim_cursor_proxy_owner`, `proxy_reseed_should_kill`; claim `stale_non_connect`; ensure + pre-kill belt |
| `scripts/client/windows/connect.ps1` | bg_init clears `needReseed` + logs `foreign_owner_cannot_bind` when CanClaim false |
| `scripts/client/tests/test-reseed-canbindl-gate.ps1` | Static + behavioral (kill_count=0 Gap, kill_count>=1 positive) |

## Contracts satisfied

- **D1:** Gap Ensure → `kill_count=0` (behavioral)
- **D2:** bg_init never keeps `needReseed=$true` under Gap (source gate + sim)
- **S2 token:** `foreign_owner_cannot_bind` on Win Ensure, connect.ps1 bg_init, Mac ensure
- **S1 MUST NOT:** Claim/CanClaim inside `Test-TunnelNeedsProxyReseed` (stays Claim-free)
- **Preferred chokepoint:** `Test-ProxyReseedShouldKill` / `proxy_reseed_should_kill`

## Tests

| Suite | Result |
|---|---|
| `test-reseed-canbindl-gate.ps1` | PASS (26 asserts) — TDD: red then green |
| `test-xray-http-leg-resilience.ps1` | PASS |
| `test-local-tunnel-ssh-pids.ps1` | PASS (32 asserts) |

## Concerns

- Not registered in `run-all.ps1` (Task 7 owns registration).
- No version bump / deploy in this task (plan ship gate later).
- Mac `missing_http` front-adopt parity vs Win Case 1 was pre-existing; not changed here.

---

## Review fix (2026-07-29)

**Status:** DONE  
**Commit:** `186ad0a` — `fix(connect): strip Task 1 HealBlackhole and version sneak-ins`  
**Parent feature commit:** `6a178c2` (CanBindL kept)

Addressed Critical/Important from `task-1-review.md`:

| Finding | Fix |
|---|---|
| CRITICAL HealBlackhole in `connect.ps1` | Removed boot + `no_tunnel_proxy_legs` `Invoke-CursorProxySidecarHealBlackhole` calls (match `c5fc940`) |
| IMPORTANT ConnectVersion/BuildId bump | Restored `20260729.2` / `b332a4c2-…` from `c5fc940` |
| IMPORTANT UTF-8 BOM | Stripped BOM from first line |
| Keep Task 1 | Retained `bg_init` `foreign_owner_cannot_bind` / CanClaim `needReseed` clear |

**Verify:** `test-reseed-canbindl-gate.ps1` PASS (26 asserts). `connect.ps1` still has `foreign_owner_cannot_bind`. Diff vs `c5fc940` for `connect.ps1` is only the bg_init gate.
