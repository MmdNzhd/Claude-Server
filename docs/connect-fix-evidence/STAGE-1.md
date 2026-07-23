# STAGE-1 Evidence Pack

## ID
- Stage: 1 (canonical tunnel port / `$port`≠`$Port` shadow)
- CONNECT_VERSION: `20260722.40` (unchanged this stage)
- Timestamp: 2026-07-22T17:05Z approx
- deploy_ran=no

## VERIFY
- Baseline smoking gun (Stage 0): session `6c8884b5220c` @ 18:25 — `claim_sticky port=20027` with prior candidate loop risk of bare `$Port` stale; `ORPHAN_TUNNEL kill port=20027` / exit log port mismatch class.
- Code anchors pre-fix: `Acquire-TunnelPort` used `$port = [int]$c.Port`; `Test-TunnelPortIsForeignPeer` did `$Port = $TargetPort`; `Push-ServerConnectConf` dedupe/`portEsc` used bare `$Port`.
- still_live=yes in historical day log (pre-patch clients). Post-patch live Connect not yet run in this execute window.

## RESEARCH
1. https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_variables?view=powershell-7.6 — variable names not case-sensitive
2. https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_case-sensitivity?view=powershell-7.6 — `$port` ≡ `$Port` on all platforms
3. https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scopes?view=powershell-7.6 — `$script:` vs bare scope

What this changes:
- Loop candidate is `$candPort` only inside `Acquire-TunnelPort`
- Session port via `Get-SessionTunnelPort` / `$script:Port`; sync `$Port = $script:Port` after claim
- Foreign/stale probes use `-TargetPort` on TcpOpen/Banner — no session `$Port` mutation

What we will NOT do:
- Rely on casing to distinguish `$port`/`$Port`; no Stage-3 hybrid rewrite in this stage

## RED_TEST
Commands (pre-fix): three new tests failed (9+4+5 asserts).
```
powershell -File scripts/client/tests/test-acquire-tunnel-port-no-port-alias.ps1  # FAIL Get-SessionTunnelPort / candPort
powershell -File scripts/client/tests/test-push-conf-uses-script-port.ps1
powershell -File scripts/client/tests/test-foreign-peer-no-global-port-mutation.ps1
```

## IMPLEMENT
- `scripts/client/git-mode.ps1`: `Get-SessionTunnelPort`; `Test-TunnelPortTcpOpen`/`Get-TunnelBanner` `-TargetPort`; foreign+stale no `$Port` mutate; Acquire `$candPort` + `$Port=$script:Port` sync; PushConf `$sessionPort` + `PORT_SHADOW_DETECT`
- Tests: `test-acquire-tunnel-port-no-port-alias.ps1`, `test-push-conf-uses-script-port.ps1`, `test-foreign-peer-no-global-port-mutation.ps1`; registered in `run-all.ps1`
- Intent: stop PushConf/orphan logging from publishing stale candidate port
- drive_by=none (Stage 1b CRLF universal sanitizer not in this change set beyond existing PushConf strip)

## GREEN_TEST
```
test-acquire-tunnel-port-no-port-alias.ps1 → Passed: 10 Failed: 0
test-push-conf-uses-script-port.ps1 → Passed: 5 Failed: 0
test-foreign-peer-no-global-port-mutation.ps1 → Passed: 5 Failed: 0
test-pushconf-quoting.ps1 → All passed
test-git-mode-deep.ps1 → All deep git-mode tests passed
```

## LIVE_GATE
- Current mux: `laptop-exec status` tunnel_port=20027 UP; server conf should align with session sticky when Connect next pushes.
- New Connect after this pack required to prove absence of shadow pair (`claim_sticky port=X` + PushConf/exit `port=Y≠X`).
- `signature_absent=pending_reconnect` with reason=`repo patch landed; live client still .38 until user relaunches Connect from Desktop\Claude-Connect`
- Code LIVE_GATE substitute: static invariants I1–I4 green in tests above.

## GATE
`STAGE_1_DONE` 2026-07-22T17:05Z `deploy_ran=no` N+1 unlocked (Stage 1b)
