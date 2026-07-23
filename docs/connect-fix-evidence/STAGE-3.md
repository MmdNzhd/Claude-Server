# STAGE-3 Evidence Pack

## ID
- Stage: 3 (sibling-safe orphan reclaim + hybrid per-UI port / primary PushConf)
- CONNECT_VERSION: `20260722.40`
- Timestamp: 2026-07-22T17:50Z approx
- deploy_ran=no

## VERIFY
- Live: `ORPHAN_TUNNEL: kill pid=30708 port=20027 reason=unprotected_live` session `6c8884b5220c` @ 18:25:39; followed by `ACQUIRE_FAST claim_sticky port=20027 slot=7` (sibling/orphan war under sticky reclaim).
- Code (pre-fix): `Remove-LocalOrphanTunnel` assumed peers use different ports; killed any unprotected live `ssh -R` (`reason=unprotected_live`); no `skip_sibling`.
- still_live=yes historically; post-patch needs Connect relaunch to prove absence of sibling kills.

## RESEARCH
1. https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-process — `ParentProcessId` / `CommandLine` for sibling Connect UI detection via CIM
2. https://man.openbsd.org/ssh.1 — `-R` remote forward: killing a peer's forward drops their tunnel
3. https://learn.microsoft.com/en-us/powershell/module/cimcmdlets/get-ciminstance?view=powershell-7.6 — enumerate `ssh.exe` with filter for `-R <port>:localhost:22`

What this changes:
- `Get-SiblingConnectTunnelPids` walks ssh → Connect UI ancestors; orphan cleanup logs `ORPHAN_TUNNEL: skip_sibling`
- Sticky/busy reclaim skips `sibling_live` (logs `sticky_shared`) instead of kill-steal
- Hybrid: conf `PORT` does not outrank `CLAUDE_CONNECT_UI_SLOT` when slot set
- `Test-IsPrimaryTunnelPublisher` (slot 0 / unset) — non-primary `PUSH_CONF skip_non_primary`

What we will NOT do:
- Deploy/publish; no Sepidz unfreeze; no Stage 4 recovery presence edits in this pack

## RED_TEST
```
test-orphan-tunnel-skip-sibling.ps1 → Failed: 7 (missing Get-SiblingConnectTunnelPids / skip_sibling / primary gate)
```

## IMPLEMENT
- `scripts/client/git-mode.ps1`: `Test-ProcessCommandIsConnectUi`, `Get-SiblingConnectTunnelPids`, `Test-IsPrimaryTunnelPublisher`; orphan `skip_sibling`; Acquire sibling_live / sticky_shared; hybrid candidate sort; PushConf skip_non_primary
- `scripts/client/tests/test-orphan-tunnel-skip-sibling.ps1` + `run-all.ps1` registration
- `test-hard-multi-agent-regressions.ps1` asserts for skip_sibling / sticky_shared / primary
- drive_by=none

## GREEN_TEST
```
test-orphan-tunnel-skip-sibling.ps1 → Passed: 10 Failed: 0
test-hard-multi-agent-regressions.ps1 → Hard regressions: 69 passed, 0 failed
test-acquire-tunnel-port-no-port-alias.ps1 → Passed: 10 Failed: 0
test-foreign-own-block-indeterminate.ps1 → Passed: 7 Failed: 0
PARSE_OK git-mode.ps1
```

## LIVE_GATE
- `signature_absent=pending_reconnect` reason=`need new Connect from Desktop\Claude-Connect; expect ORPHAN_TUNNEL: skip_sibling or ACQUIRE_SKIP: sibling_live / sticky_shared instead of kill unprotected_live on sibling -R`
- After relaunch with 2+ UIs: no orphan kill of peer Connect tunnel PIDs; slot>0 should log `PUSH_CONF skip_non_primary`

## GATE
`STAGE_3_DONE` 2026-07-22T17:50Z `deploy_ran=no` N+1 unlocked (Stage 4)
