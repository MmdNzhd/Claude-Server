# STAGE-6f Evidence Pack

## ID
- Stage: 6f (EXE MessageBox false single-instance)
- CONNECT_VERSION: `20260722.40` (unchanged; no bump)
- Timestamp: 2026-07-22T18:20Z approx
- deploy_ran=no

## VERIFY
- Pre-fix `publish/_setup-launch-body.ps1` `Test-ConnectUiOpen`:
  - Scanned `Win32_Process` CommandLine for `connect-boot.ps1` / `connect.ps1` and returned `$true` if any match → false single-instance when any UI open.
  - Mutex loop returned `$true` on first held slot (not only when all 10 held).
  - MessageBox: `Claude Connect is already open.` (not the connect-boot 10-slot wording).
- `connect-boot.ps1` correctly acquires one of `Global\ClaudeConnect#0..#9` and prints `10 Claude Connect windows already open` only when pool full.
- ExeLaunch debounce mutex `Global\ClaudeConnectExeLaunch` must remain.
- still_live=n/a until next publish EXE (repo body only; NO publish EXE this stage).

## RESEARCH
1. https://learn.microsoft.com/en-us/dotnet/standard/threading/mutexes — named Mutex / abandoned mutex; cross-process slot ownership.
2. https://learn.microsoft.com/en-us/dotnet/api/system.threading.mutex — `Global\` namespace visibility for multi-instance slot pools.
3. https://learn.microsoft.com/en-us/windows/win32/sync/object-names — kernel object names / Global vs Local namespaces.

What this changes:
- `Test-ConnectUiOpen` probes slots 0–9; returns true only when `$free -eq 0`.
- MessageBox text: `10 Claude Connect windows already open - close one, then retry.`
- Keep `ClaudeConnectExeLaunch` debounce.

What we will NOT do:
- Publish / rebuild Claude-Connect.exe; deploy; change connect-boot pool size.

## RED_TEST
```
test-exe-launch-slot-gate.ps1 → Passed: 6 Failed: 6
(pre-patch; Win32_Process gate + old MessageBox; no free-count gate)
```

## IMPLEMENT
- `publish/_setup-launch-body.ps1`: rewrite `Test-ConnectUiOpen`; MessageBox 10-slot text; keep ExeLaunch
- `scripts/client/tests/test-exe-launch-slot-gate.ps1` + register in `run-all.ps1`
- `test-hard-multi-agent-regressions.ps1`: +5 EXE slot-gate asserts
- drive_by=none; temp `_stage6f-patch.ps1` removed; NO publish EXE

## GREEN_TEST
```
test-exe-launch-slot-gate.ps1 → Passed: 12 Failed: 0
test-hard-multi-agent-regressions.ps1 → Passed: 74 Failed: 0
CONNECT_VERSION still 20260722.40
deploy_ran=no; publish EXE not built
```

## LIVE_GATE
- `signature_absent=pending_publish` reason=`repo body fixed; live EXE MessageBox false-block clears only after next publish/rebuild of Claude-Connect.exe (explicitly not done this stage)`

## GATE
`STAGE_6f_DONE` 2026-07-22T18:20Z `deploy_ran=no` N+1 unlocked (Stage 6e)
