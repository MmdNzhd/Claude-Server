# STAGE-6b Evidence Pack

## ID
- Stage: 6b (optional update policy forever + Smart hard-refuse + Sepidz freeze docs + Smart folder package)
- CONNECT_VERSION: `20260722.40` (unchanged; no bump)
- Timestamp: 2026-07-22T18:45Z approx
- deploy_ran=no

## VERIFY
- Live fingerprint (pre-fix force update still present until reconnect / policy flip on laptop):
  - session=`b3ef3f44f713` `@18:25:09.775` `UPDATE: UPDATE_FORCE applying local=20260722.36 remote=20260722.38 min=20260722.24`
  - same session `@18:25:13.001` `UPDATE: applied_ok need_relaunch exit=2`
  - same session `@18:25:09.185` `UPDATE_POLICY ... mode=force` then `@18:25:09.775` `UPDATE_POLICY source=remote_bundle` (policy was **force** with `force_min_version=20260722.24` at live time).
- Server share freeze (untouched this stage):
  - `/usr/local/share/claude-client` **ABSENT**
  - `/usr/local/share/claude-client.FROZEN` present (`SEPIDZ/SMART client auto-update FROZEN... do_not_restore_without_explicit_user_unfreeze`)
  - disabled dir `claude-client.disabled-20260722-164945`
- Repo policy now `mode=optional`, `latest=20260722.40`, `force_min_version=null` (Quiet cannot force).
- still_live=yes for old force signature until client relaunch with optional policy + no remote force bundle.

## RESEARCH
1. https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables?view=powershell-7.6 - Quiet/non-interactive defaults must not surprise-apply updates
2. https://learn.microsoft.com/en-us/windows/security/operating-system-security/virus-and-threat-protection/ - folder-primary install reduces SmartScreen/EXE-only trust friction vs stripped EXE trees
3. https://man.openbsd.org/ssh.1 - site IP / reverse-tunnel identity; refuse Sepidz `.70` contamination on Smart clients

What this changes:
- Smart `client-update-policy.json` -> `mode=optional`, `latest=20260722.40`, `force_min_version=null`
- Quiet never auto-applies optional; prompt default N; Smart hard-refuse Sepidz path/IP
- Docs freeze Sepidz forever; publish EXE-only strip gated

What we will NOT do:
- Deploy/publish; restore server `claude-client`; ForceUnfreeze Sepidz
## RED_TEST
```
test-client-update-policy-optional.ps1 -> Passed: 9 Failed: 13
(pre-patch; policy still force / catch default Y / no hard-refuse / strip ungated)
```

## IMPLEMENT
- `scripts/server/client-update-policy.json`: mode optional, latest 20260722.40, force_min_version null
- `scripts/client/windows/connect-update.ps1`: Assert-SmartNotSepidzContaminated; forceApply gate; prompt catch/empty -> N
- `scripts/client/windows/connect.ps1`: Test-PathLooksSepidz + Die REFUSE on Smart contamination
- `publish/publish.ps1`: keep full Smart windows\ tree unless CLAUDE_PUBLISH_STRIP_WINDOWS_EXE_ONLY=1
- `docs/client-connect.md`: Sepidz publish freeze + Smart folder layout + optional-forever policy
- `publish/README-sepidz.txt`: bat-only / no EXE / no auto-update / SEPIDZ_PUBLISH_FROZEN / no ForceUnfreeze without ask
- `scripts/client/tests/test-client-update-policy-optional.ps1` + register in `run-all.ps1`
- drive_by=none (temp stage helpers removed)

## GREEN_TEST
```
test-client-update-policy-optional.ps1 -> Passed: 24 Failed: 0
CONNECT_VERSION still 20260722.40
deploy_ran=no; server share still ABSENT + FROZEN marker present; SEPIDZ_PUBLISH_FROZEN present
```

## LIVE_GATE
- `signature_absent=pending_reconnect` reason=`need client relaunch with optional policy (and no remote force bundle); expect no UPDATE_FORCE/applied_ok from Quiet optional checks; Smart path must Die/FAIL on sepidz folder names or .70 IP`

## GATE
`STAGE_6b_DONE` 2026-07-22T18:45Z `deploy_ran=no` N+1 unlocked (Stage 6c)