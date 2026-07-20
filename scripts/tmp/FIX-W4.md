# FIX-W4 — Auth (CRITICAL)

Project: `claude-code-server` via laptop-exec only. **No deploy.**

## Must-fix status

| # | Requirement | Status | Change |
|---|-------------|--------|--------|
| 1 | Temp dir cleanup via `Remove-CursorAuthTempDir` / `Get-CursorAuthTempRoot` (no bare `Remove-Item $tmp -Recurse` on 8.3 TEMP / AA616) | **FIXED** | Skip-path machineid heal now creates under `Get-CursorAuthTempRoot` and cleans with `Remove-CursorAuthTempDir`. Golden scp already used the helpers; no remaining `-Recurse` outside the helper. |
| 2 | Win auth skip checks golden-synced-at / exported-at rotation | **FIXED** | `Test-CursorAuthNeedsRefresh` adds `golden_stale` when `golden-synced-at.txt` ≠ server `exported-at`. Connect skip (`cursorRunning && authComplete`) no longer skips forever after token rotation. `Sync-CursorGoldenAuth` already required matching stamp. |
| 3 | Mac O-key dead when sticky opened — allow O | **FIXED** | Mac O handler matches Windows: if not on correct folder, reopen even when `_editor_opened=1`. |
| 4 | Don't AUTH_RELAUNCH kill when auth was skipped | **FIXED** | `skipped)` branch no longer exports `CURSOR_AUTH_RELAUNCH=1` (`ok` / `tokens_only` still do). |
| 5 | machineid file drift forces refresh | **FIXED** | `Test-CursorAuthNeedsRefresh` adds `machineid_file_mismatch` when profile `machineid` ≠ golden `machine-id.txt` (parity with Mac `cursor_auth_needs_refresh`). |
| 6 | Keep email/stripe metadata on early merge path | **FIXED** | `Build-CursorAuthValuesFromGoldenDir` early path (`$vals.Count -gt 0` from state-keys) now copies `cachedEmail` / `cachedSignUpType` / `stripeMembershipType` / `stripeSubscriptionStatus` from `auth.json`. |

## Files touched

- `scripts/client/cursor-auth-laptop.ps1`
- `scripts/client/mac/connect.sh`
- `scripts/client/tests/test-cursor-auth-merge.ps1`

## Tests

```
powershell -NoProfile -File scripts/client/tests/test-cursor-auth-merge.ps1
```

Exit code: **0** (all assertions passed).

## Leftover risks (out of must-fix / other agents)

- Bug #42 (`auth-relaunch-unused-when-already-on-folder`): when editor already open, Mac may not call `launch_remote_editor`, so `CURSOR_AUTH_RELAUNCH` soft-stop still may not run after a successful merge.
- Bug #44 / #66 (VS Code isolated profile / Mac agent-home aggressiveness) not in this pass.
- File-level `Remove-Item $tmp -Force` in `Merge-CursorStorageJsonFromGolden` (merge-src beside storage.json) is intentional; not a TEMP dir recurse.

