# STAGE-5 Evidence Pack

## ID
- Stage: 5 (MountOk re-assert + ACTIVE_MOUNT guard)
- CONNECT_VERSION: `20260722.40`
- Timestamp: 2026-07-22T18:20Z approx
- deploy_ran=no

## VERIFY
- Code: `Complete-PostTunnelRecovery -MountOk $true` logged `RECOVERY_END mount_ok=True` without live `Test-ProjectMountHealthy` / mountpoint probe → diagnostic `SSHFS_NOT_MOUNTED` can disagree.
- PushConf always applied `PREFER` ACTIVE_MOUNT even when another project mount was still live (multi-UI race).
- Live historical: `RECOVERY_END … mount_ok=True` in archived logs; ACTIVE_MOUNT prefer races noted in Stage 0 timeline.
- still_live=yes structurally until relaunch.

## RESEARCH
1. https://manpages.debian.org/stable/util-linux/mountpoint.1.en.html — `mountpoint -q` for live SSHFS dir
2. https://linux.die.net/man/1/sshfs — unmount races when peer tears tunnel
3. https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions?view=powershell-7.6 — reassert before logging terminal status

What this changes:
- `Complete-PostTunnelRecovery` logs `RECOVERY_MOUNTOK_REASSERT` and flips MountOk false if not live
- `Push-ServerConnectConf` PowerShell + remote bash `ACTIVE_MOUNT_GUARD keep=… prefer=… reason=other_still_mounted`
- Skip-clear recovery re-prefers ACTIVE_MOUNT only when mount live

What we will NOT do:
- Stage 6 bat/UX edits; no deploy; no Sepidz unfreeze

## RED_TEST
```
test-mount-ok-reassert-before-recovery-end.ps1 → Failed: 3
test-active-mount-guard.ps1 → Failed: 3
```

## IMPLEMENT
- `scripts/client/windows/connect.ps1`: MountOk reassert; skip-clear ActiveMount prefer-if-live
- `scripts/client/git-mode.ps1`: ACTIVE_MOUNT_GUARD (client + remote body)
- Tests registered in run-all.ps1
- drive_by=none

## GREEN_TEST
```
test-mount-ok-reassert-before-recovery-end.ps1 → Passed: 4 Failed: 0
test-active-mount-guard.ps1 → Passed: 4 Failed: 0
test-push-conf-uses-script-port.ps1 → Passed: 5 Failed: 0
test-auto-recovery-skip-clear-mount-matrix.ps1 → Passed: 12 Failed: 0
PARSE_OK connect.ps1 + git-mode.ps1
```

## LIVE_GATE
- `signature_absent=pending_reconnect` reason=`need recovery/session-open; expect RECOVERY_MOUNTOK_REASSERT live=True|False matching RECOVERY_END mount_ok; multi-UI expect ACTIVE_MOUNT_GUARD when other project still mounted`

## GATE
`STAGE_5_DONE` 2026-07-22T18:20Z `deploy_ran=no` N+1 unlocked (Stage 6)
