# Task 3+4 Review: Defer tunnel + drop Ensure#2 / firewall cache

**Reviewer:** task reviewer (subagent)  
**Date:** 2026-07-26  
**Artifacts reviewed:** `task-3-4-brief.md`, `task-3-4-report.md`, `task-3-4-diff.txt`, live source + test re-run

---

## Verdict (one line)

**SPEC PASS / QUALITY APPROVED** — boot path defers tunnel until post-pick; Ensure#2 removed; Ensure#1 hard-fail + `LaptopFirewallOk` preserved; firewall session cache added; tests enforce new contracts and pass.

---

## SPEC: **PASS**

| Requirement | Status | Evidence |
|---|---|---|
| **Task 3:** No `Initialize-SessionBgTunnel` between Ready and `:menuLoop` | ✅ | `Mark-BootstrapDone` at L1836 → `$script:SessionBgTunnel = $null` at L1838 → `:menuLoop` at L1844 with no tunnel init in between. Pre-menu call removed (diff L131). |
| **Task 3:** Post-pick tunnel path still present | ✅ | Inside `:menuLoop` after project pick: L1981–L1988 (`Step "Preparing tunnel"` + `Initialize-SessionBgTunnel`). Recovery/M-key sites retained at L2920, L3051. |
| **Task 3:** `$script:SessionBgTunnel = $null` before menu | ✅ | L1838 (unchanged intent). |
| **Task 4:** Ensure#2 removed (no `Ensure-LaptopSshReady` between Ready and menu) | ✅ | Entire soft-continue block removed (diff L115–L126). Boot slice L1836–L1844 has no `Ensure-LaptopSshReady`. |
| **Task 4:** Ensure#1 still hard-fails boot | ✅ | `Initialize-ServerSession` L861–L862 returns `Ok = $false; Error = 'laptop SSH key setup failed'`. Caller L1821–L1822 `Wait-ConnectExit` on `$boot.Error` / `-$boot.Ok`. |
| **Task 4:** `$script:LaptopFirewallOk = $true` on Ensure#1 success | ✅ | L864 immediately after Ensure#1 success (moved from Ensure#2 success branch). |
| **Task 4:** Firewall session cache skips repeat `Get-NetFirewallRule` | ✅ | `Test-LaptopSshReady` L635–L638: `if (-not $script:LaptopFirewallCheckedOk) { … Get-NetFirewallRule … else { $script:LaptopFirewallCheckedOk = $true } }`. |
| **Tests:** Pipeline + hard-regression updated to new contracts | ✅ | `test-connect-pipeline.ps1` structural boot regex + Ensure#1/cache asserts. `test-hard-multi-agent-regressions.ps1` replaces `FAIL LAPTOP_SSH_BOOT` with no-duplicate-Ensure + `LaptopFirewallOk`. |
| **Tests:** Not incorrectly weakened | ✅ | Tunnel assert changed from “pre-warms after Ready” to “still defines/uses” **plus** negative boot-path regex — stricter on ordering. `FAIL LAPTOP_SSH_BOOT` removal matches intentional Ensure#2 deletion (brief Step 1 Task 4). |

### Boot-path sequence (verified)

```
Ready (L1834) → Mark-BootstrapDone (L1836) → SessionBgTunnel=$null (L1838) → :menuLoop (L1844)
  → Choose-Project (L1858) → … → Initialize-SessionBgTunnel (L1986)
```

Mac parity intent satisfied: first tunnel spawn is post project pick, not pre-menu.

---

## QUALITY: **APPROVED**

### Strengths

- Minimal, focused diff on the shared hotspot (`connect.ps1` boot + `Test-LaptopSshReady`).
- TDD flow documented (RED 3+1 failures → GREEN); reviewer re-ran targeted tests — **all PASS**.
- Boot-section regex tightened to `Mark-BootstrapDone … :menuLoop while` avoids false positives from post-pick tunnel inside loop body (report FIX note is sound).
- Two-flag design is clear: `LaptopFirewallCheckedOk` (Test-LaptopSshReady cache) vs `LaptopFirewallOk` (post-pick firewall skip at L1967).
- Post-pick firewall re-check remains as fallback when `LaptopFirewallOk` unset; happy path skips 30–90s stall after Ensure#1 sets flag.

### Findings (non-blocking)

1. **Intentional log removal:** `FAIL LAPTOP_SSH_BOOT` no longer emitted — Ensure#2 was the only soft-continue path. Ensure#1 still hard-fails with `laptop SSH key setup failed`. Documented in report; test correctly updated, not weakened.

2. **Test redundancy:** `test-connect-pipeline.ps1` runs identical regex twice (`$bootToMenuStart` and `$bootToMenu`). Harmless; could dedupe in a cleanup pass.

3. **Optional brief items not done:** `docs/client-connect.md` Mac-parity sentence and `test-live-ssh-ready.ps1` re-run omitted. Acceptable for this wave; live smoke still recommended before claiming sub-5s cold start.

4. **`test-git-mode-deep.ps1` unchanged:** Brief listed “~234 if asserts pre-warm” — existing assert is for `git-mode.ps1` tunnel pre-warm, not `connect.ps1`. No action required.

5. **No `ConnectVersion` bump:** Report notes behavior-only change within same version string. Consistent with scope; publish/version bump can follow if desired.

---

## Test evidence (reviewer)

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\client\tests\test-connect-pipeline.ps1
→ All tests passed (incl. new boot-path + cache asserts)

powershell -NoProfile -ExecutionPolicy Bypass -File scripts\client\tests\test-hard-multi-agent-regressions.ps1
→ Hard regressions: 78 passed, 0 failed
```

---

## Files changed (as reviewed)

| File | Role |
|---|---|
| `scripts/client/windows/connect.ps1` | Remove Ensure#2 + pre-menu tunnel; Ensure#1 sets `LaptopFirewallOk`; `LaptopFirewallCheckedOk` cache in `Test-LaptopSshReady` |
| `scripts/client/tests/test-connect-pipeline.ps1` | Structural asserts: no tunnel/Ensure between Ready and menu; Ensure#1 + cache contracts |
| `scripts/client/tests/test-hard-multi-agent-regressions.ps1` | Replace `FAIL LAPTOP_SSH_BOOT` with no-duplicate-Ensure + Ensure#1 `LaptopFirewallOk` |

---

## Recommendation

Approve for merge/integration. Spec items verified against diff and live source. Optional follow-ups: manual cold-start timing, one-line Mac parity in `docs/client-connect.md`, dedupe duplicate regex variables in pipeline test.
