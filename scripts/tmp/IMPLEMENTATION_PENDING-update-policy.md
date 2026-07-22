# IMPLEMENTATION_PENDING: Optional/Force Client Update Policy

Scan date: 2026-07-21. Scope: `scripts/client/windows/connect-update.ps1`,
`scripts/client/mac/connect-update.sh`, `scripts/client/connect-ui.ps1`,
`scripts/server/commands/deploy-client-bundle.sh`, full repo grep for
policy/defer/force_min_version/watermark terms.

## Finding

No Optional/Force update-policy feature exists anywhere in the repository.
`connect-update.ps1` / `connect-update.sh` implement a single unconditional
update path: if the remote version is newer OR local files drift from the
server's `checksums.txt`, the client downloads, verifies, and swaps the live
bundle in-place, then relaunches (exit code 2) or errors (exit code 1). There
is no branch for "optional" (skippable/deferrable) vs "force" (mandatory)
update classes, no per-version minimum-required gate, and no user-facing
defer/snooze mechanism. All "watermark" occurrences in the codebase refer to
the **log-sync byte offset** (`.sync-offset`, `Read-ConnectLogSyncWatermark`),
which is an unrelated feature — there is no update-defer watermark.

Repo-wide search results (grep -c on live files):
- `client-update-policy.json` (or any `*update-policy*` filename): 0 matches
- `force_min_version` / `MinVersion` / `Defer-Update` / `Skip-Update`: 0 matches
- `optional update` / `force update` (policy sense): 0 matches
- `update_policy` / `UpdatePolicy`: 0 matches

## Exact missing symbols

Policy file:
- `scripts/server/client-update-policy.json` — does not exist.

`scripts/client/windows/connect-update.ps1`:
- `Get-UpdatePolicy` / `Read-UpdatePolicy` — not present.
- `Test-UpdateDeferActive` (watermark-within-window check) — not present.
- `Write-UpdateDeferWatermark` / `Set-UpdateDeferWatermark` — not present.
- `Test-ForceMinVersionExceeded` / `Get-ForceMinVersion` — not present.
- No `-Optional`/`-Force` mode branch anywhere in `main`/apply flow; the
  existing flow (`version_newer`/`content_drift` -> always apply) has no
  conditional skip for a deferred optional update.

`scripts/client/mac/connect-update.sh`:
- `_get_update_policy` / `_read_update_policy` — not present.
- `_test_defer_active` — not present.
- `_write_defer_watermark` — not present.
- `_force_min_version_override` — not present.
- `main()` mirrors Windows: unconditional apply, no defer branch.

Tests:
- `scripts/client/tests/test-update-policy.ps1` — does not exist. NOT created
  by this pass (see rationale below).

`scripts/server/commands/deploy-client-bundle.sh`:
- `win_files=(...)` / `mac_files=(...)` arrays have no entry for a policy
  JSON file — nothing to copy since the file itself does not exist. This is
  a real gap for goal item 5 ("deploy-client-bundle.sh should REFERENCE
  copying update-policy.json") — currently it does not, because there is
  nothing to reference.

## Why no test file was written

The task requires mocking/extracting *real* functions from the update code
to test 4 scenarios (missing-policy default, defer-within-48h skip,
defer-expired prompt, force_min_version override). Since none of
`Get-UpdatePolicy` / `Test-UpdateDeferActive` / `Write-UpdateDeferWatermark` /
`Test-ForceMinVersionExceeded` (or Mac equivalents) exist, a test file would
have nothing real to call — it would either fail on missing functions (not a
useful regression signal) or encode fabricated logic never exercised by
production code (false confidence). This report stands in for that file.

## Minimal shape to unblock implementation

1. `scripts/server/client-update-policy.json`:
   ```json
   { "mode": "optional", "force_min_version": "20260101.1", "defer_hours": 48 }
   ```
2. Windows (`connect-update.ps1`): fetch/parse the policy JSON alongside
   `connect-version.txt`; on missing/unreachable policy, default to
   `mode=optional`. Before applying a detected update, if `mode=optional`
   AND remote version does not exceed `force_min_version` AND
   `Test-UpdateDeferActive` (a `.update-defer` timestamp file younger than
   `defer_hours`) is true, exit 0 without prompting. On explicit user
   "later", call `Write-UpdateDeferWatermark`. `force_min_version` always
   bypasses defer.
3. Mac (`connect-update.sh`): symmetric bash functions, same JSON schema.
4. `deploy-client-bundle.sh`: add `client-update-policy.json` to both
   `win_files` and `mac_files` copy arrays so it flows through the existing
   stage/checksum/swap pipeline (this repo's convention already used for
   `connect-version.txt`).
5. `scripts/client/tests/test-update-policy.ps1`: dot-source the real
   functions from step 2 and assert the 4 scenarios listed in the task.

## Contract matrix (current reality, no mocking possible)

| Contract | Status |
|---|---|
| Missing policy file -> optional default | NOT IMPLEMENTED — no policy file concept exists; every detected diff is applied unconditionally (mandatory-only behavior today) |
| Defer watermark within 48h skips | NOT IMPLEMENTED — no defer watermark, no skip branch |
| Defer expired allows prompt path | NOT IMPLEMENTED — there is no interactive prompt path at all; update always auto-applies non-interactively (exit 2 relaunch) or fails (exit 1) |
| force_min_version overrides defer | NOT IMPLEMENTED — no min-version gate |

Net effect: today's client update is de facto always "Force" — there is no
"Optional" class to defer. This is a functional gap, not a bug in existing
code (existing code is internally consistent and covered by
`test-connect-update-hardening.ps1` / `test-connect-update-quick.ps1` for its
actual mandatory-apply contract).
