# Task 6 Review (re-review after fix): Harden Get-LocalTunnelSshPids regex

**Reviewer:** task reviewer (spec compliance + code quality)  
**Artifacts:** `task-6-brief.md`, `task-6-report.md`, `task-6-diff.txt`  
**Range:** `2bcc983` .. `HEAD` (`c3a5a86` + fix `c5fc940`)  
**Verification:** cumulative diff + live `test-local-tunnel-ssh-pids.ps1` (exit 0, **32/32** asserts)

---

## Verdict (one line)

**SPEC PASS · QUALITY Approved** — Prior Critical (out-of-scope HealBlackhole) and Important (Mac table coverage) are fixed; matcher DoD met on Win+Mac.

---

## Prior FAIL disposition

| Prior finding | Status | Evidence |
|---|---|---|
| CRITICAL: out-of-scope `Complete-CursorProxy*` HealBlackhole / force-clear | **Fixed** | `c5fc940` reverts Completes to BASE `2bcc983` (logic-identical; comment encoding only). Range diff has **zero** `HealBlackhole` / `heal_cursor_proxy_sidecar_blackhole` hunks. HEAD `git-mode.ps1` / `.sh` Completes restore Clear + `Test-MayClear` / `test_may_clear` gates. |
| IMPORTANT: Mac matcher name-only static | **Fixed** | Suite extracts `test_local_tunnel_ssh_command` via bash harness and runs the same 4 pass + 7 fail rows; reviewer re-ran → **32 asserts PASS** (20 Win + 11 Mac + 1 no-FAIL). |

---

## SPEC: **PASS**

| Requirement | Verdict | Evidence |
|---|---|---|
| Accept `-R PORT:localhost:22` | **Met** | Win + Mac pass row `space localhost` |
| Accept `-R PORT:127.0.0.1:22` | **Met** | Win + Mac pass row + behavioral pid=101 |
| Accept `-R=PORT:localhost:22` | **Met** | Win + Mac pass row + behavioral pid=102 |
| Reject wrong port | **Met** | Fail row + behavioral pid=103 |
| Reject without `-R` | **Met** | Fail rows `-L`, bare, ssh-keygen |
| Win+Mac shared matcher used by PID enum | **Met** | `Test-LocalTunnelSshCommandLine` → `Get-LocalTunnelSshPids`; `test_local_tunnel_ssh_command` → `get_local_tunnel_ssh_pids` at orphan/stop/hygiene/has_local_reverse |
| Table-driven pass+fail | **Met** | Same rows drive Win `Test-*` and Mac bash harness |
| Task scope (matcher only) | **Met** | Range touches only `git-mode.ps1`, `git-mode.sh`, `test-local-tunnel-ssh-pids.ps1`; Completes match BASE |
| Global Clear-skip / locked invariants | **OK** | Completes back to may-clear gated Clear; no port-formula / refuse_kill / missing_http / no_proc edits in matcher hunks |

---

## QUALITY: **Approved**

### Strengths

- Clean Win helper split + Mac `grep -E` parity (incl. `-R=…127.0.0.1:22`, double-space).
- ssh-keygen exclusion after RED→GREEN.
- Mac replaces brittle `pgrep -f "…localhost:22"` with filtered pid enum.
- Behavioral CIM stub with negative counters; Mac harness fails hard if bash unavailable.

### Critical

None.

### Important

None for Task 6 DoD.

### Minor

1. **Mislabeled fail row** — `'wrong host'` uses `:2222` (wrong dest port), overlaps `'wrong dest port'`.
2. **`run-all.ps1` registration deferred** — Acceptable if Task 7 owns it.
3. **`Get-LocalTunnelSshReversePortFromCommandLine` lacks ssh-keygen exclude** — Safe under CIM `ssh.exe` filter; keep in sync if reused.
4. **Pass table omits explicit `-R=PORT:127.0.0.1:22` row** — Matcher accepts it on both sides; optional row for documentation.

---

## Files reviewed

| File | Role |
|---|---|
| `scripts/client/git-mode.ps1` | Matcher helpers + consumers; Completes = BASE |
| `scripts/client/git-mode.sh` | Mac matcher + pid enum wiring; Completes = BASE |
| `scripts/client/tests/test-local-tunnel-ssh-pids.ps1` | Win table + CIM stub + Mac bash harness |

---

## Test evidence (reviewer)

```
powershell -NoProfile -File scripts\client\tests\test-local-tunnel-ssh-pids.ps1
→ All local-tunnel-ssh-pids tests passed (32 asserts).
EXIT=0
```

---

## Recommendation

Task 6 is ready to proceed. No blocking follow-ups for this brief.
