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

## From STRICT CONTRACT (binding)

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

### Task 1: ReseedEffective - do not kill `-R` when Claim will fail

**DoD (task fails review without these):** D1, D2, S1 MUST NOT kill under Gap, S2 token `foreign_owner_cannot_bind` on Win+Mac+connect.ps1, S4 behavioral kill_count=0 **and** positive control kill_count>=1 when CanBindL.

**Files:**
- Modify: `scripts/client/git-mode.ps1` (~1637 Claim area; ~3095-3182 Ensure fallthrough; all reseed->kill sites)
- Modify: `scripts/client/git-mode.sh` (~1691-1740 ensure)
- Modify: `scripts/client/windows/connect.ps1` (~2408-2418)
- Create: `scripts/client/tests/test-reseed-canbindl-gate.ps1`

**Interfaces:**
- Consumes: `Get-CursorProxyOwnerInfo`, `Test-ProcessAlive`, `Test-ProcessCommandIsConnectUi`
- Produces: `Test-CanClaimCursorProxyOwner` / `can_claim_cursor_proxy_owner` (read-only, no file write)
- Produces: `Test-ProxyReseedShouldKill` (preferred single chokepoint) OR equivalent at every site
- Produces: Ensure + bg_init use `ReseedEffective = ReseedRaw AND CanClaim`

**Call sites that must gate (Win) - miss any = reject:**
1. Ensure after `tunnel_up` + ReseedRaw true (~3095-3101)
2. Ensure after `recent_success_tcp_open` reseed (~3115-3120)
3. Ensure after `recent_success` reseed (~3140-3145)
4. Ensure after `adopt_local_forward` reseed (~3166-3172)
5. Path to unconditional kill block (~3178-3182) unreachable under Gap
6. `connect.ps1` bg_init (~2408-2418)

**Mac:** before `kill "$bg_pid"` when reseed true (~1735). Prefer one helper so sites cannot drift.

- [ ] **Step 1: Write the failing test (static + behavioral)**

Create `scripts/client/tests/test-reseed-canbindl-gate.ps1` modeled on `test-tunnel-proxy-skip-hard.ps1`:

```powershell
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_paths.ps1"
$Fail = 0; $Pass = 0
function Assert([bool]$c, [string]$m) {
 if ($c) { $script:Pass++; Write-Host " PASS $m" -ForegroundColor Green }
 else { $script:Fail++; Write-Host " FAIL $m" -ForegroundColor Red }
}

$gmPath = Get-ClientFile 'git-mode.ps1'
$winPath = Get-ClientFile 'windows\connect.ps1'
$shPath = Get-ClientFile 'git-mode.sh'
$gm = Get-Content -LiteralPath $gmPath -Raw
$win = Get-Content -LiteralPath $winPath -Raw
$sh = Get-Content -LiteralPath $shPath -Raw

# --- Static (necessary, not sufficient) ---
Assert ($gm -match 'function Test-CanClaimCursorProxyOwner') 'Win Test-CanClaimCursorProxyOwner'
Assert ($gm -match 'foreign_owner_cannot_bind') 'Win foreign_owner_cannot_bind'
Assert ($win -match 'foreign_owner_cannot_bind') 'connect.ps1 bg_init token'
Assert ($sh -match 'can_claim_cursor_proxy_owner') 'Mac can_claim'
Assert ($sh -match 'foreign_owner_cannot_bind') 'Mac foreign_owner_cannot_bind'

$ens = [regex]::Match($gm, 'function Ensure-SessionTunnel[\s\S]*?\r?\nfunction ').Value
Assert ($ens -match 'Test-CanClaimCursorProxyOwner|Test-ProxyReseedShouldKill') 'Ensure gates CanClaim'
$canRel = [Math]::Max($ens.IndexOf('Test-CanClaimCursorProxyOwner'), $ens.IndexOf('Test-ProxyReseedShouldKill'))
$killRel = $ens.IndexOf('killing stale bg')
Assert ($canRel -ge 0 -and $killRel -gt $canRel) 'gate before killing stale bg in Ensure'

$reseedFn = [regex]::Match($gm, 'function Test-TunnelNeedsProxyReseed[\s\S]*?\r?\nfunction ').Value
Assert ($reseedFn -notmatch 'Claim-CursorProxyOwner|Test-CanClaimCursorProxyOwner') `
 'ReseedRaw stays Claim-free'

# Count Ensure fallthrough sites: every Test-TunnelNeedsProxyReseed / Test-ProxyReseedShouldKill
# in Ensure must be the gated helper OR immediately followed by CanClaim check in source.
# Prefer: Assert ($ens -match 'function' ) - implementer must show >=4 gated sites OR single helper used >=4 times.
Assert (([regex]::Matches($ens, 'Test-ProxyReseedShouldKill|Test-CanClaimCursorProxyOwner')).Count -ge 2) `
 'Ensure references gate more than once (or helper + call sites)'

# --- Behavioral Gap: ReseedRaw true, CanClaim false => kill_count=0 ---
# Strategy: stub Test-TunnelNeedsProxyReseed=$true, Test-CanClaimCursorProxyOwner=$false,
# Stop-TunnelProcessWithExitLog increments kill_count, drive the reuse->reseed path of Ensure
# with a fake live BgTunnel + Test-TunnelUp=$true. Exact stubs may wrap Test-ProxyReseedShouldKill
# if Ensure uses that chokepoint - assert kill_count=0 and log contains foreign_owner_cannot_bind.
#
# REQUIRED: this block must execute real Ensure-SessionTunnel (or Test-ProxyReseedShouldKill
# + the Ensure branch that would kill). Pure "simulate if" without calling product code = REJECT.

# --- Behavioral positive control: CanClaim true => kill allowed (count>=1) when ReseedRaw ---
# Prove we did not disable all reseeds.

Write-Host ""
if ($Fail -eq 0) { Write-Host "All $Pass reseed-canbindl contracts passed."; exit 0 }
Write-Host "$Fail failed, $Pass passed."; exit 1
```

**Implementer MUST flesh the behavioral blocks into real `. $gmPath` stubs before marking Step 1 done.** Skeleton comments are not a passing test.

- [ ] **Step 2: Run test - expect FAIL**

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\client\tests\test-reseed-canbindl-gate.ps1
```

Expected: FAIL on missing helpers / tokens / behavioral kill_count path.

- [ ] **Step 3: Implement Win helper**

Near `Claim-CursorProxyOwner` in `git-mode.ps1`:

```powershell
function Test-CanClaimCursorProxyOwner {
 # Read-only mirror of Claim success without writing owner.json.
 $info = Get-CursorProxyOwnerInfo
 if (-not $info) { return $true }
 $pidOwn = 0
 try { $pidOwn = [int]$info.pid } catch { return $true }
 if ($pidOwn -le 0) { return $true }
 if ($pidOwn -eq $PID) { return $true }
 if (-not (Test-ProcessAlive -ProcessId $pidOwn)) { return $true }
 try {
 $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$pidOwn" -ErrorAction Stop
 $cmd = [string]$cim.CommandLine
 if (Get-Command Test-ProcessCommandIsConnectUi -ErrorAction SilentlyContinue) {
 if (-not (Test-ProcessCommandIsConnectUi -CommandLine $cmd)) {
 return $true # PID reuse by non-Connect -> Claim would adopt
 }
 }
 } catch {
 # Unreadable cmdline: treat as foreign-live (safe: skip kill)
 return $false
 }
 return $false
}
```

Also tighten `Claim-CursorProxyOwner` live_owner branch: if alive but **not** Connect-shaped -> treat as stale adopt (same as dead).

- [ ] **Step 4: Gate all Ensure reseed fallthroughs + kill block**

Helper pattern (inline or small function):

```powershell
function Test-ProxyReseedShouldKill {
 param([int]$TunnelPid, [string]$Alias, [string]$SshCfgPath = '')
 if (-not (Test-TunnelNeedsProxyReseed -TunnelPid $TunnelPid -Alias $Alias -SshCfgPath $SshCfgPath)) {
 return $false
 }
 if (-not (Test-CanClaimCursorProxyOwner)) {
 Write-GitModeLog "ENSURE_TUNNEL reseed_skip reason=foreign_owner_cannot_bind pid=$TunnelPid port=$Port" 'WARN'
 return $false
 }
 return $true
}
```

Replace each:

```powershell
if (-not (Test-TunnelNeedsProxyReseed ...)) { Complete...; return $true }
# Fall through kill
```

with:

```powershell
if (-not (Test-ProxyReseedShouldKill -TunnelPid ... -Alias $Alias -SshCfgPath $SshCfgPath)) {
 Complete-CursorProxyAfterTunnel
 return $true
}
# Fall through kill only when ReseedEffective
```

**Critical:** When ReseedRaw was true but CanClaim false, still `Complete-CursorProxyAfterTunnel` and **return $true** with `$TunnelReused.Value = $true` (keep existing bg). Do **not** reach `killing stale bg`.

- [ ] **Step 5: Gate `connect.ps1` bg_init**

```powershell
$needReseed = [bool](Test-TunnelNeedsProxyReseed -TunnelPid $bgTunnel.Id -Alias $Alias -SshCfgPath $sshCfg)
if ($needReseed -and (Get-Command Test-CanClaimCursorProxyOwner -ErrorAction SilentlyContinue)) {
 if (-not (Test-CanClaimCursorProxyOwner)) {
 $needReseed = $false
 Write-ConnectLog "ENSURE_TUNNEL bg_init_reseed_skip reason=foreign_owner_cannot_bind pid=$($bgTunnel.Id) port=$Port" 'WARN'
 }
}
```

- [ ] **Step 6: Mac parity**

```bash
can_claim_cursor_proxy_owner() {
 local path pid_own
 path="$(cursor_proxy_owner_path)"
 [ -f "$path" ] || return 0
 pid_own="$(... read pid ...)"
 [ -n "$pid_own" ] || return 0
 [ "$pid_own" = "$$" ] && return 0
 if ! kill -0 "$pid_own" 2>/dev/null; then return 0; fi
 # optional: Connect-shaped check via ps; if non-Connect return 0
 return 1
}
```

Before kill when reseed:

```bash
if ! can_claim_cursor_proxy_owner; then
 connect_log "ENSURE_TUNNEL reseed_skip reason=foreign_owner_cannot_bind pid=$bg_pid" 'WARN'
 complete_cursor_proxy_after_tunnel || true
 TUNNEL_REUSED=1
 return 0
fi
```

- [ ] **Step 7: Re-run test - expect PASS**

- [ ] **Step 8: Commit** (only if user asked to commit)

```bash
git add scripts/client/git-mode.ps1 scripts/client/git-mode.sh \
 scripts/client/windows/connect.ps1 scripts/client/tests/test-reseed-canbindl-gate.ps1
git commit -m "$(cat <<'EOF'
fix(connect): skip proxy reseed kill when foreign owner cannot bind -L

EOF
)"
```

---

## Prior task interfaces (Task 6 done)
- Test-LocalTunnelSshCommandLine / test_local_tunnel_ssh_command exist
- Do NOT redo Task 6. Do NOT register run-all (Task 7).
- Behavioral tests mandatory (kill_count=0 under Gap + positive control).
