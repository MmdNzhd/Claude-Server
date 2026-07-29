# Task 3+4 Report — connect.ps1 boot perf (tunnel defer + Ensure#2 removal)

**STATUS:** GREEN — all targeted tests pass. No commit (per instructions).

## Summary

Combined Tasks 3 and 4 on the `connect.ps1` hotspot:

1. **Task 3 (P0):** Removed pre-menu `Initialize-SessionBgTunnel` call. Reverse tunnel now starts only after project pick (Mac parity). Post-pick path (~1996), recovery, and M-key sites unchanged. `$script:SessionBgTunnel = $null` kept before `:menuLoop`.

2. **Task 4 (P1):** Removed Ensure#2 block (`Ensure-LaptopSshReady` between Ready and menu). Ensure#1 in `Initialize-ServerSession` remains hard-fail and now sets `$script:LaptopFirewallOk = $true` on success. `Test-LaptopSshReady` skips repeat `Get-NetFirewallRule` when `$script:LaptopFirewallCheckedOk` is set.

## Test commands and exits

| Command | Exit |
|---------|------|
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\client\tests\test-connect-pipeline.ps1` | **0** (RED: 3 failures before implement; GREEN after) |
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\client\tests\test-hard-multi-agent-regressions.ps1` | **0** (RED: 1 failure; GREEN after) |
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\client\tests\test-git-mode-deep.ps1` | **0** (unchanged; no connect pre-warm assert) |

## Files changed

| File | Change |
|------|--------|
| `scripts/client/windows/connect.ps1` | Remove Ensure#2 + pre-menu tunnel; Ensure#1 sets `LaptopFirewallOk`; firewall session cache in `Test-LaptopSshReady` |
| `scripts/client/tests/test-connect-pipeline.ps1` | New structural asserts: no tunnel/Ensure between Ready and `:menuLoop while`; function-scoped Ensure#1 + cache asserts |
| `scripts/client/tests/test-hard-multi-agent-regressions.ps1` | Replace `FAIL LAPTOP_SSH_BOOT` assert with no duplicate Ensure + Ensure#1 `LaptopFirewallOk` |

**Not changed:** `connect-update.ps1`, `connect-preflight.ps1`, `connect.bat`, `test-git-mode-deep.ps1`, `test-live-ssh-ready.ps1`, `docs/client-connect.md`.

## TDD flow

1. **RED:** Added failing pipeline + hard-regression asserts; pipeline failed 3, hard-regression failed 1.
2. **GREEN:** Minimal `connect.ps1` edits.
3. **Fix test false-positive:** Boot-section regex tightened to `Mark-BootstrapDone … :menuLoop while` (avoids matching post-pick tunnel inside loop body / `end :menuLoop` comment).

## Concerns / follow-ups

- **Removed log:** `FAIL LAPTOP_SSH_BOOT` no longer emitted (Ensure#2 was soft-continue). Ensure#1 still hard-fails boot with `laptop SSH key setup failed`.
- **Live smoke:** `test-live-ssh-ready.ps1` not re-run (live SSH/server dependency; source-only change to cache flag).
- **Cold-start timing:** Manual connect timing still recommended to confirm sub-5s Ready→menu on real laptop.
- **Publish:** No `ConnectVersion` bump in this wave (behavior-only boot path change within same version string).
