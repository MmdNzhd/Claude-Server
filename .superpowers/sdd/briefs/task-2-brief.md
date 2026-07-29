## Global Constraints

- English-only in repo (comments, tests, logs, docs).
- Do **not** break:
 - foreign-peer `refuse_kill` / hostkey mismatch refuse
 - `missing_http` front-adopt gate (`state -eq 'missing'` only - Win Case 1)
 - first-budget `no_proc_tcp_open` keep-alive (must not `Release-StaleTunnelPort` on first exhaust)
 - known-down must not short-circuit backend probe
 - port formula `20000+(UID-1000)*10+slot`
 - Clear skip when Cursor windows open and 18998 up
 - `scripts_only_reuse` EXE rename-lie guard
- Fixed proxy ports: backends `19080`/`19180`; sticky fronts `18999`/`18998`.
- Project hooks remain `{"version":1,"hooks":{}}`.
- MULTI_INSTANCE slots != proxy ownership (one owner per laptop for fixed backends).
- After client changes: bump connect version + deploy Smart client bundle (`publish\deploy-scripts-only.ps1` preferred; do **not** invent versioned EXE from unrebuilt SFX).
- Prefer <=4 parallel `laptop-exec` if on Remote SSH; git via `laptop-exec git` only when on mount.

---

## STRICT (binding)

## STRICT CONTRACT (non-negotiable)

### S0 - Definition of Done (whole plan)

The plan is **DONE** only when **all** of the following are true. Partial ship is forbidden.

| ID | Requirement | Evidence |
|---|---|---|
| D1 | Under Gap, Ensure **never** calls `Stop-TunnelProcessWithExitLog` / `kill` for proxy reseed | Behavioral test: kill counter stays 0 |
| D2 | Under Gap, `connect.ps1` bg_init **never** sets `needReseed=$true` | Behavioral or source+sim assert |
| D3 | `Wait-ForTunnelUp` returns `$true` only if spawn pid in local `-R` PIDs | Behavioral stub of `Test-TunnelUp=$true` + empty local PIDs -> `$false` |
| D4 | After `port still busy` with no local `-R`, Ensure does **not** `Start-Process ssh` on that port | Behavioral: spawn counter 0, or rebind to different port |
| D5 | Owner with backends down + xray expected releases within **<=65s** wall (60s timer + 5s slack) | Behavioral timer sim with frozen clock / injected `Get-Date` |
| D6 | First `no_proc` budget exhaust still keep-alives (no `Release-Stale`) | Existing keepalive suite still PASS unchanged on first exhaust |
| D7 | After **>=120s** continuous no_proc keep-alive + (NOT auth OR NOT banner) -> drop | Behavioral age inject |
| D8 | Win and Mac emit **identical** reason tokens (exact substrings below) | Grep both trees |
| D9 | `run-deploy-gate.ps1` PASS with **zero** skipped new suites | Gate log |
| D10 | Live Gap replay checklist (Task 8) all boxes checked | Daylog quotes in report |

**Ship abort (any one fails -> do not bump/deploy):**

- Any of D1-D9 fails
- New test is static-only (no behavioral counter / stub path) for Tasks 1-5
- Win ships a reason Mac lacks (or vice versa) for the tokens in S2
- `test-xray-http-leg-resilience.ps1` or `test-tunnel-no-proc-keepalive.ps1` regresses
- Deploy uses `-SkipTests`

### S1 - MUST / MUST NOT (runtime)

| | Rule |
|---|---|
| **MUST** | Gate proxy-motivated kill with `Test-CanClaimCursorProxyOwner` / `can_claim_cursor_proxy_owner` at **every** Ensure reseed fallthrough **and** bg_init |
| **MUST** | On Gap skip: keep existing `$BgTunnel` / `$bg_pid`, call `Complete-CursorProxyAfterTunnel`, return success (`$true` / `0`) |
| **MUST** | Wait fail with `reason=local_r_not_owned` when banner up but pid not in local `-R` set |
| **MUST** | Refuse spawn or rebind when still-busy within 15s and no local `-R` |
| **MUST** | `Release-CursorProxyOwner` with `reason=service_dead` when claimed + NOT backends + xray-expected >=60s |
| **MUST NOT** | Kill `-R` solely because `ReseedRaw` is true while `NOT CanBindL` |
| **MUST NOT** | Treat `Test-TunnelUp` / banner alone as Wait success |
| **MUST NOT** | Spawn on a port that just logged `STALE_FORWARD: port still busy` while still TCP-open and no local `-R` |
| **MUST NOT** | Remove or weaken first-budget `soft_fail_exhausted_keep_alive` (no `Release-Stale` in that arm) |
| **MUST NOT** | Release owner on intentional `xray_closed` server_direct |
| **MUST NOT** | Suppress `missing_http` reseed when HTTP backend is down (front-alone adopt) |
| **MUST NOT** | Put Claim/CanClaim inside `Test-TunnelNeedsProxyReseed` (predicate stays pure; gate at caller) |
| **MUST NOT** | "Fix" Gap by forcing Claim steal from a live Connect-shaped owner |

### S2 - Exact reason tokens (byte-identical Win / Mac)

These substrings **must** appear in both `git-mode.ps1` and `git-mode.sh` (and bg_init skip in `connect.ps1` where noted). Typos / renamed reasons = **review reject**.

| Token | Platforms |
|---|---|
| `foreign_owner_cannot_bind` | Win Ensure, Win `connect.ps1` bg_init, Mac ensure |
| `local_r_not_owned` | Win Wait, Mac wait |
| `stale_port_busy` | Win Ensure, Mac ensure |
| `reason=service_dead` | Win+Mac owner release |
| `stale_non_connect` | Win+Mac Claim adopt |
| `soft_fail_exhausted_zombie_drop` | Win+Mac Sync |

### S3 - Locked thresholds (do not "tune" without updating tests)

| Name | Value | Rationale | Test must lock |
|---|---|---|---|
| `SERVICE_DEAD_SEC` | **60** | Long enough for sidecar flap; short vs 80min zombie | assert `TotalSeconds -ge 60` / `$SERVICE_DEAD_SEC` |
| `NO_PROC_ZOMBIE_SEC` | **120** | > dual-UI reattach window; << multi-hour STATUS_OK | assert `120` literal or named const |
| `STILL_BUSY_WINDOW_SEC` | **15** | Covers clear->spawn race in same Ensure | assert `15` |
| Still-busy clear waits | Win 4x250ms; Mac 8x250ms after `i=0` | Keep existing budgets; Mac must init `i` | Mac source `local i=0` |

Changing a threshold without updating the matching test asserts = **fail**.

### S4 - Test quality bar (reject soft tests)

Pattern to follow: `scripts/client/tests/test-tunnel-proxy-skip-hard.ps1` (static **and** behavioral).

For Tasks **1-5** each new/extended suite **MUST** include:

1. **Static contracts** - function names, reason tokens, call-order inside Ensure/Wait/Sync bodies
2. **Behavioral simulation** - `. $gmPath` (or extracted helper), stub dependencies, **counter** for kill/spawn/Release
3. **Negative assert** - the forbidden action's counter stays 0
4. **Positive control** - when CanBindL / ownership / still-busy clear, the heal path still runs (kill or Wait ok allowed)
5. **Mac parity static** - same reason tokens in `git-mode.sh`
6. **Throw on ASSERT fail** (or `$Fail -gt 0` -> `exit 1`) - no soft WARN-only tests

**Review reject if:**

- Only `Assert ($src -match 'foreign_owner...')` without kill-counter behavioral case
- Behavioral test stubs so broadly that `Ensure-SessionTunnel` is never exercised for Gap
- Task marked complete while Mac tokens missing
- New suite not registered in `run-all.ps1`

### S5 - Forbidden source patterns after implementation

CI/review must `Select-String` / ripgrep and **fail** if found:

| Forbidden (post-fix Ensure/bg_init paths) | Why |
|---|---|
| Ensure reseed fallthrough that reaches `killing stale bg` with no prior `Test-CanClaimCursorProxyOwner` / `can_claim` in the same function body order | Gap reopen |
| `Wait-ForTunnelUp` returning success on `Test-TunnelUp` without `Get-LocalTunnelSshPids` / pgrep ownership check | False Wait |
| Mac `clear_server_stale_tunnel_forward` using `$i` without `i=0` / `local i=0` before loop | Unbound loop |
| First `soft_fail_exhausted_keep_alive` arm containing `Release-StaleTunnelPort` before age gate | Dual-UI regression |

### S6 - Incident replay acceptance (must quote daylog)

After deploy, a fresh daylog segment for a **controlled Gap replay** must satisfy:

| Assert | Pass condition |
|---|---|
| A | Second Connect logs `foreign_owner_cannot_bind` (Ensure and/or bg_init) |
| B | Between that skip and next spawn on same session: **zero** `killing stale bg` for proxy reseed |
| C | No `TUNNEL_WAIT ok=1` immediately after `port still busy` on same port without `local_r_not_owned` or `refuse_spawn`/`rebind` |
| D | Zombie owner Connect: within 65s of backends-down+xray, log contains `released reason=service_dead` **or** owner file pid changes via adopt |
| E | Healthy single-window path still logs `proxy_leg=-L` when xray up (no over-skip) |

If live replay is impossible (no second UI), **harness replay** in Task 8 Step 2b (scripted stubs writing synthetic daylog markers via unit path) is required instead - "couldn't test live" is **not** acceptance.

---

## Task

### Task 2: Wait-ForTunnelUp requires this pid owns local `-R`

**DoD:** D3, S2 `local_r_not_owned` Win+Mac, S4 behavioral: `Test-TunnelUp=$true` + empty local PIDs => Wait returns `$false` with token; positive: local PIDs contain spawn pid => `$true`.

**Files:**
- Modify: `scripts/client/git-mode.ps1` (`Wait-ForTunnelUp` ~2686-2719)
- Modify: `scripts/client/git-mode.sh` (`wait_for_tunnel_up` ~1010+)
- Create: `scripts/client/tests/test-wait-local-r-ownership.ps1`

**Interfaces:**
- Consumes: `Get-LocalTunnelSshPids` / Mac pgrep for `-R ${PORT}:...`
- Produces: Wait success only if spawn pid in local `-R` set; log `reason=local_r_not_owned`
- Gate A is reverse ownership only (not `-L` listen)

**HARD:** Empty local PID list is failure, not success. Banner-only success is a ship abort (S5).

- [ ] **Step 1: Failing test (static + behavioral)**

```powershell
# Static: tokens + Get-LocalTunnelSshPids inside Wait body before return $true
# Behavioral:
# . git-mode.ps1
# function Test-TunnelUp { $true }
# function Get-LocalTunnelSshPids { @() }
# $fake = [pscustomobject]@{ Id = 4242; HasExited = $false }
# # Port must be set; Quiet to avoid UI
# Assert (-not (Wait-ForTunnelUp -TunnelProc $fake -Quiet))
# Assert ($log -match 'local_r_not_owned')
# Positive:
# function Get-LocalTunnelSshPids { @(4242) }
# Assert (Wait-ForTunnelUp -TunnelProc $fake -Quiet)
```

Reduce Wait loop cost in test by stubbing `Start-Sleep` if needed - **do not** delete Gate A to make tests faster.

- [ ] **Step 2: Run - FAIL**
- [ ] **Step 3: Implement Win** (Gate A as previously specified; empty locals => fail)
- [ ] **Step 4: Mac parity - same token**
- [ ] **Step 5: PASS both behavioral cases + commit**

---

## Notes
Task 6+1 done. Commit ONLY Wait + test-wait-local-r-ownership.ps1 (+ Mac wait). No HealBlackhole, no version bump. Before commit: git diff --stat and strip unrelated hunks vs HEAD.
