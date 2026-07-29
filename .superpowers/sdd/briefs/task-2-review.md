# Task 2 Review: Wait Gate A (`local_r_not_owned`)

**Reviewer:** read-only (spec + quality)  
**Range:** `186ad0a` .. `91bda73`  
**Artifacts:** `task-2-brief.md`, `task-2-report.md`, `reviews/task-2-diff.txt`

---

## SPEC: PASS

| Requirement | Verdict | Evidence |
|---|---|---|
| D3 banner up + empty local PIDs => Wait false | **Met** | Win: `return $true` only when `$localPids -contains $spawnPid`; empty/`spawnPid -le 0` stays fail-closed. Behavioral: empty stub => `$false` + `local_r_not_owned` |
| S2 `local_r_not_owned` Win + Mac | **Met** | Win `Wait-ForTunnelUp`; Mac `wait_for_tunnel_up` **and** `poll_tunnel_with_progress` (Ensure calls poll) |
| Empty locals => fail (HARD / S5) | **Met** | No banner-only success path; Gate A before every `return $true` / `return 0` |
| Behavioral +/- (S4) | **Met** | Negative empty + foreign; positive owned => `TUNNEL_WAIT ok=1`; `Start-Sleep` stubbed without removing Gate A; `$Fail -gt 0` => `exit 1` |
| Wait / Mac wait gated | **Met** | Both Mac wait helpers gated; Win Wait gated |
| No HealBlackhole / version sneak-in | **Met** | Diff STAT: only `git-mode.ps1`, `git-mode.sh`, `test-wait-local-r-ownership.ps1` (+196/−26). No connect.ps1/sh, version.txt, sidecar |

---

## QUALITY: Changes requested

### Critical

None.

### Important

1. **Mac pure-timeout final log dropped** — Win still emits `TUNNEL_WAIT fail=1 reason=timeout` when Gate A never tripped; Mac `wait_for_tunnel_up` / `poll_tunnel_with_progress` only log final fail when `local_r_not_owned=1`, so banner-never-up timeouts lose the WARN fail line (TRACE attempts only). Restore Win-parity `else` timeout log before `release_stale_tunnel_port`.

### Minor (non-blocking)

1. **`run-all.ps1` not registered** — Acceptable; plan Task 7 owns wire-up (`wait-local-r-ownership`).
2. **Mac static assert is OR** — suite can pass if only wait *or* poll has the token; both currently have it; tighten to AND (or assert both bodies) later.
3. **Unused `$pollSrc`** in test static block; Mac Gate A double-calls `get_local_tunnel_ssh_pids` (join + loop).

---

## Verdict

**SPEC PASS · QUALITY Changes requested**

Gate A DoD (D3 / S2 / empty fail-closed / behavioral +/- / scoped commit) is met. Fix Mac timeout final-fail log for Win parity before treating quality as Approved.
