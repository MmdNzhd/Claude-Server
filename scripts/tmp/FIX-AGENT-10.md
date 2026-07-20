# FIX-AGENT-10 — Silent failures / tests / docs

Date: 2026-07-20  
Scope: bugs **35, 39, 41, 62, 63, 64, 69**  
Constraints: laptop-exec only; **no deploy**; **no commit**.

## Fixed slugs

| # | Slug | Status |
|---|------|--------|
| 35 | `docs-temp-log-lie` | Fixed — docs match durable local day logs + server sync |
| 39 | `sshx-swallow-callers` | Fixed — `Invoke-SshXChecked` + critical callers WARN on nonzero exit |
| 41 | `missing-pushconf-quoting-e2e` | Fixed — `test-pushconf-quoting.ps1` (base64 + RESULT + elif / nasty prefer) |
| 62 | `weak-assert-true` | Fixed — real asserts in editor-launch + publish tests |
| 63 | `win-pushconf-ok-without-result` | Fixed — exit 0 without `PUSH_CONF_RESULT` does **not** set dedupe |
| 64 | `update-tests-miss-fail-exit` | Fixed — `test-connect-update-fail-exit.ps1` + ERROR→`exit 1` in update scripts |
| 69 | `claude-md-no-unconditional-runas-lie` | Fixed — invariant documents always-elevate / UAC |

## Files touched

### Docs
- `CLAUDE.md` — connect log policy; always-elevate invariant
- `docs/client-connect.md` — durable day-log paths (Win/Mac), no wipe-on-exit; session-end marker wording

### Production (own + minimal shared)
- `scripts/client/git-mode.ps1` — `Invoke-SshXChecked`; PushConf `hasResult` gate; critical mount/push Out-Null → checked
- `scripts/client/git-mode.sh` — PushConf: drop `|| true` swallow; require RESULT before dedupe *(minimal; Agent 4 owns Mac tunnel — noted)*
- `scripts/client/cursor-auth-laptop.ps1` — `cursor-auth-sync --force` checks exit / WARN
- `scripts/client/users/designer/connect.ps1` — mount add/edit/recover/down checked
- `scripts/client/windows/connect.ps1` — mkdir/chmod checked
- `scripts/client/windows/connect-update.ps1` — ERROR paths `exit 1` *(minimal; Agent 6 owns update)*
- `scripts/client/mac/connect-update.sh` — download/incomplete/manifest → `exit 1`
- `scripts/client/connect-ui.sh` — comment: durable day log (not temp wipe)

### Tests
- `scripts/client/tests/test-pushconf-quoting.ps1` **(new)**
- `scripts/client/tests/test-connect-update-fail-exit.ps1` **(new)**
- `scripts/client/tests/test-editor-launch.ps1` — Assert cursor Source
- `scripts/client/tests/test-publish.ps1` — Assert `$hitCount -eq 0`
- `scripts/client/tests/test-connect-pipeline.ps1` — base64 / RESULT / hasResult / Invoke-SshXChecked
- `scripts/client/tests/run-all.ps1` — register new suites

### Report
- `scripts/tmp/FIX-AGENT-10.md` (this file)

## Leftover risks

1. **Best-effort SshX still Out-Null** where remote ends with `|| true` / `true` (stale-forward kill, recover-if-needed, self-heal, laptop-exec-setup). Those cannot surface exit≠0; only callers without remote `true` were hardened.
2. **Mac update** `ssh`/`scp` missing still `exit 0` without ERROR (soft skip) — intentional; tests lock ERROR-labeled paths only.
3. **Agent 6** may further harden update (checksum, copy rollback — bugs 9/10/29/30). This agent only made ERROR→nonzero + tests.
4. **Agent 4** Mac ensure/tunnel parity bugs unchanged; PushConf RESULT gate here is a minimal shared edit.
5. **Designer** mount add failure now `StepFail` but session may still continue into tunnel loop — operator-visible WARN/FAIL only.
6. Remaining `Assert $true` elsewhere: none under `scripts/client/tests` after this pass.

## Verify (laptop)

```bat
scripts\client\tests\run-all.bat
```

Or individually:

```powershell
powershell -NoProfile -File scripts\client\tests\test-pushconf-quoting.ps1
powershell -NoProfile -File scripts\client\tests\test-connect-update-fail-exit.ps1
powershell -NoProfile -File scripts\client\tests\test-connect-pipeline.ps1
```

## Verify results (this agent)

| Suite | Result |
|-------|--------|
| `test-pushconf-quoting.ps1` | PASS |
| `test-connect-update-fail-exit.ps1` | PASS |
| `test-editor-launch.ps1` | PASS |
| `test-connect-pipeline.ps1` | PASS |

No deploy / no commit.
