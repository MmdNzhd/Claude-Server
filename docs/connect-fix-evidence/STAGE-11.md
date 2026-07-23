# STAGE-11 Evidence Pack

## ID
- Stage: 11 (Version + full Stage 1–11 related suite)
- CONNECT_VERSION: **`20260722.40`** (kept; no bump)
- Timestamp: 2026-07-22T20:20Z approx
- deploy_ran=no
- Stage D: **LOCKED / not run**

## VERIFY
- CONNECT_VERSION already `20260722.40` in connect.ps1 / connect.sh / connect-version.txt / policy latest.
- New Stage 6c–10 tests registered in `scripts/client/tests/run-all.ps1`.
- Server Stage 6e/7/8 tests present under `scripts/server/tests/`.
- Ancient p0 pin still expected `20260721.52` / mac `20260720.26` → updated to `.40`.

## RESEARCH
1. https://semver.org/ — keep existing dated stamp unless breaking client wire change requires bump.
2. https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scripts — register suites in a single runner for CI/local gates.
3. Prior packs Stages 0–10 under `docs/connect-fix-evidence/` — N+1 unlock chain.

What this changes:
- `test-p0-connect-fixes.ps1` expected version → `20260722.40`.
- Temp `_*.ps1` / `_*.py` stage helpers removed.
- No version bump; policy latest already `.40`.

What we will NOT do:
- `publish` / `claude-server install` / `-ForceUnfreeze` / restore `/usr/local/share/claude-client`.
- Imply that laptop clients or server binaries were deployed.

## RED_TEST
```
Pre-Stage-11: p0 pin 20260721.52 would fail against current .40 sources.
```

## IMPLEMENT
- `scripts/client/tests/test-p0-connect-fixes.ps1` (pin to .40)
- Cleanup root/client temp patch helpers from Stages 8–9
- Evidence: this pack
- drive_by=none

## GREEN_TEST
```
Client batch (Stage 6b–11 related): CLIENT_STAGE_FAILS=0
  smartscreen-docs-contract → 20
  exe-launch-slot-gate → 12
  cursor-profile-db-tool → 18
  chat-freeze-skip-paths → 13
  log-sync-forbid-shrink → 8
  log-sync-contracts → 15
  p0-connect-fixes → 12
  hard-multi-agent-regressions → 74
  client-update-policy-optional → 24
Server:
  test-cursor-auth-personal-denylist.sh → 12
  test-laptop-exec-timeout-audit.sh → 7
  test-cursor-auth-golden-perms.sh → 9
CONNECT_VERSION=20260722.40
deploy_ran=no
```

## LIVE_GATE
- `repo_only_complete` reason=`all Stage 6c–11 code+tests+packs in repo; deploy/publish LOCKED`
- Stage D not run



## EXEC_ORDER_NOTE
Post-6b order (Stage 10 is a 6d prerequisite): 6c -> 6f -> 6e -> 10 -> 6d -> 7 -> 8 -> 9 -> 11.
## GATE
`STAGE_11_DONE` `STAGES_0_11_DONE` 2026-07-22T20:20Z `deploy=LOCKED` `deploy_ran=no`
