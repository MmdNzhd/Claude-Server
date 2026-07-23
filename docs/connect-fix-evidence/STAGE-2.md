# STAGE-2 Evidence Pack

## ID
- Stage: 2 (own-block FOREIGN_INDETERMINATE + FOREIGN TTL)
- CONNECT_VERSION: `20260722.40`
- Timestamp: 2026-07-22T17:35Z approx
- deploy_ran=no

## VERIFY
- Live: `ACQUIRE_SKIP: foreign_peer cached port=20028` session `6c8884b5220c` @ 18:25 (own-block permanent cache shrinks 10-port range).
- Code: `Test-TunnelPortIsForeignPeer` treated `tcpOpen||Windows banner` as foreign; `Test-CachedForeignTunnelPort` permanent pin.
- still_live=yes historically; post-patch needs Connect relaunch + cache expiry/forget.

## RESEARCH
1. https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_server_configuration — reverse forwards / MaxSessions context for multi-tunnel
2. https://man.openbsd.org/ssh.1 — `-R` remote forward semantics (peer vs own)
3. https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_hash_tables?view=powershell-7.6 — in-memory TTL maps for cache metadata

What this changes:
- Own UID block + tcp open + auth not owned → `FOREIGN_INDETERMINATE` / not foreign
- Own-block foreign cache TTL 300s with `FOREIGN_PORT forget`
- Hostkey mismatch remains `-Permanent` pin

What we will NOT do:
- Blindly clear all FOREIGN_TUNNEL_PORTS on disk without TTL rules; no Stage-3 hybrid in this pack

## RED_TEST
```
test-foreign-own-block-indeterminate.ps1 → Failed: 7 (missing helpers / INDETERMINATE)
```

## IMPLEMENT
- `git-mode.ps1`: `Test-TunnelPortInOwnUidBlock`, `Remove-ForeignTunnelPort`, `ForeignTunnelPortTtlSec=300`, Add-Foreign `-Permanent`, cached TTL forget, foreign peer indeterminate branch
- Test registered in `run-all.ps1`
- drive_by=none

## GREEN_TEST
```
test-foreign-own-block-indeterminate.ps1 → Passed: 7
test-foreign-peer-no-global-port-mutation.ps1 → Passed: 5
test-git-mode-deep.ps1 → All passed
```

## LIVE_GATE
- `signature_absent=pending_reconnect` reason=`need new Connect; own-block cache entry 20028 expires/forgets on TTL or indeterminate path`
- After relaunch: should see `FOREIGN_INDETERMINATE` or `FOREIGN_PORT forget` instead of permanent skip-only on 20028 when it is our block.

## GATE
`STAGE_2_DONE` 2026-07-22T17:35Z `deploy_ran=no` N+1 unlocked (Stage 3)
