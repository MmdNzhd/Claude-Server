# Agent L — HARD update matrix (wave2)

Date: 2026-07-20 11:35:00 (UTC+3:30 session)
Project: `-p claude-code-server` (laptop-exec only; **no** live deploy/publish)

## Overall: **HARD FAIL**

| Test | Exit | Result | Seconds | Notes |
|------|------|--------|---------|-------|
| `test-connect-update-quick.ps1` | 0* | **FAIL** (functional) | 6.8 | Script exits 0, but connect-update returned **rc=1** (“rolled back”); `connect-version.txt` missing after rollback wipe |
| `test-connect-update-e2e.ps1` | 1 | **FAIL** | 4.1 | Expected rc=2 + ver `20260713.26`; got apply rollback, empty ver; remote offered `v20260714.2` |
| `test-connect-update-desktop.ps1` | 124 | **FAIL** | 60 | **TIMEOUT** on `ssh … claude-server` remote bundle probe (hung) |
| `test-publish.ps1` | 1 | **FAIL** | 0.7 | 15 failures (stale Desktop publish ZIPs / IP / file-count drift) |
| `test-client-auto-update.sh` | 1 | **FAIL** | 3.1 | 2–4 fails: version compare needs `python3` (missing on Win Git bash path); “should detect newer remote”; intermittent mac IdentityAgent/timeout greps |
| `test-update-exit-contract.ps1` | 0 | **PASS** | ~1 | 20 pass / 0 fail — ERROR paths exit nonzero |
| `verify-checksum` | 0 | **PASS** | — | `Test-BundleChecksums` + `_verify_checksums`; tested via auto-update grep |
| `verify-rollback-partial` | 0 | **PASS** | — | `Restore-FromBak` / `Swap-LiveDir` / `apply_rollback` present |
| `verify-bat-relaunch-bound` | 0 | **PASS** | — | `CLAUDE_CONNECT_UPDATE_DEPTH` with `GEQ 3` in `connect.bat` |

\*quick harness does not `exit 1` on update failure — counted **FAIL** for HARD matrix because update did not apply.

## Per-test tails

### test-connect-update-quick (exit=0 script / update rc=1) — FAIL

```
calling connect-update...
  Update source: smart@192.168.210.240
  Client update available: v20260701.1 -> v20260714.2
    downloading client bundle...
  [!] Update apply failed - rolled back to previous package
done rc=1 ver=
Get-Content : Cannot find path '...\claude-update-quick\connect-version.txt'
```

### test-connect-update-e2e (exit=1) — FAIL

```
=== E2E live update test ===
  Update source: smart@192.168.210.240
  Client update available: v20260701.1 -> v20260714.2
    downloading client bundle...
  [!] Update apply failed - rolled back to previous package
exit=1 newver=
E2E LIVE UPDATE: FAIL
```

### test-connect-update-desktop (exit=124) — FAIL

```
TIMEOUT after 60s
(last observed before hang: PASS Desktop version sync (20260714.2); then ssh claude-server bundle probe)
```

### test-publish (exit=1) — FAIL

```
FAIL  main publish folder has no claude-automount.sh
FAIL  main has exactly 18 client files (got 22)
FAIL  sepidz … contains forbidden 'claude-server-sepidz' (×3)
FAIL  connect.ps1 / connect.sh differs only by SERVER_IP
FAIL  binary identical: mac\connect-version.txt, mac\git-mode.sh, windows\connect-ui.ps1, windows\connect-version.txt, windows\git-mode.ps1
FAIL  connect.ps1 size delta = IP length diff (-1 bytes)
15 test(s) failed.
```

### test-client-auto-update (exit=1) — FAIL

```
FAIL .26 > .25          (python3 not found under Git bash)
FAIL should detect newer remote
(also saw: FAIL mac IdentityAgent / mac ssh/scp timeout on one run)
23–21 passed depending on run; Python was not found (Microsoft Store stub)
```

### test-update-exit-contract (exit=0) — PASS

```
contract: 20 pass, 0 fail
(ps1+sh: ssh/scp/manifest/download/incomplete/apply_rollback/checksum ERROR paths exit nonzero)
```

### verify-checksum — PASS

```
code=True tested=True
(Test-BundleChecksums / Get-FileHash SHA256; _verify_checksums; test-client-auto-update.sh greps Test-BundleChecksums|checksums.txt)
```

### verify-rollback-partial — PASS

```
ps=True sh=True
(Windows Restore-FromBak + Swap-LiveDir + apply_rollback; Mac apply_rollback after failed swap)
```

### verify-bat-relaunch-bound — PASS

```
depthGuard=True
(connect.bat: CLAUDE_CONNECT_UPDATE_DEPTH; increment on exit 2; stop at GEQ 3)
```

## Artifacts

- Contract: `scripts/tmp/test-update-exit-contract.ps1`
- Runner: `scripts/tmp/run-agent-l-hard.ps1`
- Logs: `scripts/tmp/agent-l-hard-logs/`

## Verdict: **HARD FAIL**

Failures: quick (functional), e2e, desktop (timeout), publish, client-auto-update.  
Passes: ERROR exit contract, checksum presence+test hook, rollback, bat relaunch bound.
