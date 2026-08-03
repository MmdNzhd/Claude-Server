# test-amir-multi-connect-matrix.md
# Fleet matrix checklist (amir + amirhossein class) — Multi-Connect mount lifecycle
# Map: M# → auto suite (L1–L7 / T1–T4 / H0*). Sign off for pilot before claiming 10-project bar.

| # | Scenario | Expect | Auto | Pass? | Notes |
|---|----------|--------|------|-------|-------|
| M1 | KEEP + Cursor on folder | marker written; Soft `KEEP_EDITOR` / protect skip | L1 | [ ] | |
| M2 | Close Cursor → Connect | STALE_KEEP; tunnel+marker+mount cleaned | L1 | [ ] | |
| M3 | Two live Connect UIs Soft | siblings untouched (Win Soft; no Stop-Process UI) | L2 | [ ] | |
| M4 | Same project reconnect | pin + adopt (`RECLAIM_PIN` / adopt_local_forward) | L3 | [ ] | |
| M5 | Free slot + other orphan | orphan reclaimable; free claim succeeds | L4 / L5 | [ ] | |
| M6 | Skew live OK (both TCP + ls) | `MOUNT_PORT_SKEW_DEFERRED` (no remount) | T1 / L7 | [ ] | |
| M7 | Skew live dead / hung ls | `MOUNT_PORT_SKEW` remount (return 1) | T1 / L7 | [ ] | |
| M8 | cleanup-user without `--force` | refuse when Connect/session live | T4 | [ ] | |
| M9 | cleanup-user `--force` | clean TUNNEL keep LAPTOP_USER | T4 | [ ] | |
| M10 | Mac Soft dual Connect | sibling survives Soft | H0d / mac hard-batch | [ ] | |
| M11 | amirhossein-class conf≠sshfs | dead remount or DEFERRED if alive | T1 / L7 | [ ] | |
| M12 | Version twins `20260803.4` | Win / Mac / bat aligned | version tests | [ ] | |
| M13 | N=2 then N=5 Connect/KEEP | no peer_live stranding; Soft safe; new session gets slot | L5 + pilot | [ ] | anti-amir wall-at-2 |
| M14 | Litter: many sibling PS + profile windows | Soft alone leaves siblings; Deep-clean confirm clears server-profile Cursor + sibling Connect; personal `%APPDATA%\Cursor` untouched | B9 / B10 | [ ] | |

## How to run auto coverage

```powershell
# Static hard-batch (deploy gate)
powershell -NoProfile -File scripts\client\tests\run-deploy-gate.ps1

# HARDER L1–L7
powershell -NoProfile -File scripts\client\tests\test-harder-live-keep-reclaim.ps1
powershell -NoProfile -File scripts\client\tests\test-harder-live-keep-soft-race.ps1
powershell -NoProfile -File scripts\client\tests\test-harder-live-pin-before-reclaim.ps1
powershell -NoProfile -File scripts\client\tests\test-harder-live-acquire-keep-split.ps1
powershell -NoProfile -File scripts\client\tests\test-harder-live-slot-storm-keep.ps1
powershell -NoProfile -File scripts\client\tests\test-harder-adversarial-keep-mount.ps1
powershell -NoProfile -File scripts\client\tests\test-harder-live-mount-skew-gate.ps1

# Or via battery / run-all HARDER section
powershell -NoProfile -File scripts\client\tests\run-harder-battery.ps1
```

## Sign-off

- [ ] L1–L5 green in `run-all` HARDER + `run-harder-battery`
- [ ] L6–L7 PASS (or honest SKIP only if source file missing)
- [ ] M1–M14 checked for pilot user (amir-class multi-project)
