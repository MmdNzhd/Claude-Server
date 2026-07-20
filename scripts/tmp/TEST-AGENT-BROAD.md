# TEST-AGENT-BROAD

- Agent: I (Broad suite)
- Project: `-p claude-code-server`
- Deploy: none
- When: 2026-07-20 07:46:20 UTC
- Overall: **HARD FAIL**

## Summary table

| Script | Exit | Verdict | Notes |
|--------|------|---------|-------|
| `scripts/client/tests/run-all.ps1` | LIVE-SKIP | LIVE-SKIP | Skipped: suite includes test-launch-perf-live.ps1 |
| `scripts/client/tests/test-pipeline-deep.ps1` | 0 | PASS | All deep tests passed |
| `scripts/client/tests/test-connect-ui.ps1` | 0 | PASS | OK |
| `scripts/client/tests/test-connect-update-quick.ps1` | 0 | PASS | Update path ran; test exit 0 (rc=2 from updater = updated) |
| `scripts/client/tests/test-connect-update-e2e.ps1` | 1 | FAIL | Network OK; E2E LIVE UPDATE: FAIL (exit=2 newver=20260714.2) |
| `scripts/client/tests/test-connect-update-desktop.ps1` | LIVE-SKIP | LIVE-SKIP | Local smoke PASS then hung on live ssh claude-server |
| `scripts/client/tests/audit-ps5-deep.ps1` | 1 | FAIL | 3 FAIL: smart quotes in connect.ps1, connect-ui.ps1, git-mode.ps1 |
| `scripts/client/tests/test-select-project.ps1` | 0 | PASS | All select-project tests passed |
| `scripts/client/tests/test-connect-diagnostic.ps1` | 0 | PASS | All tests passed |

## Overall: HARD FAIL

Non-live failures drive HARD FAIL. LIVE-SKIP does not.

## Per-script last 30 lines

### `scripts/client/tests/run-all.ps1` — exit=LIVE-SKIP (LIVE-SKIP)

```
SKIPPED: run-all.ps1 includes test-launch-perf-live.ps1 (live SSH)
EXIT:LIVE-SKIP
```

### `scripts/client/tests/test-pipeline-deep.ps1` — exit=0 (PASS)

```
=== PowerShell pipeline deep test (MS docs aligned) ===

  PASS  Join-Path -Path -ChildPath explicit matches Path.Combine
  PASS  Path.Combine ignores stray pipeline objects (static method)
  PASS  Unary comma return emits one object (about_Return)
  PASS  Function can emit multiple success-stream objects
  PASS  @(func)[-1] picks last emitted object
  PASS  $null = ($m = ...) suppresses assignment leak in function
  PASS  connect.ps1 version 20260719.31
  PASS  editor-launch uses Path.Combine not Join-Path
  PASS  safe Choose-Project capture
  PASS  safe Resolve-EditorChoice capture

All deep tests passed.
EXIT:0
```

### `scripts/client/tests/test-connect-ui.ps1` — exit=0 (PASS)

```
OK test-connect-ui.ps1
EXIT:0
```

### `scripts/client/tests/test-connect-update-quick.ps1` — exit=0 (PASS)

```
calling connect-update...
  Update source: smart@192.168.210.240
  Client update available: v20260701.1 -> v20260714.2
    downloading client bundle...
  Updated to v20260714.2
done rc=2 ver=20260714.2
EXIT:0
```

### `scripts/client/tests/test-connect-update-e2e.ps1` — exit=1 (FAIL)

```
=== E2E live update test ===
  Update source: smart@192.168.210.240
  Client update available: v20260701.1 -> v20260714.2
    downloading client bundle...
  Updated to v20260714.2
exit=2 newver=20260714.2
E2E LIVE UPDATE: FAIL
EXIT:1
```

### `scripts/client/tests/test-connect-update-desktop.ps1` — exit=LIVE-SKIP (LIVE-SKIP)

```
=== Windows auto-update smoke ===
PASS .26 > .25
PASS .9 not > .10
PASS connect-update.ps1 on Desktop
PASS connect.bat hook
PASS Desktop version sync (20260714.2)
HUNG on live ssh claude-server (server bundle probe)
EXIT:LIVE-SKIP
```

### `scripts/client/tests/audit-ps5-deep.ps1` — exit=1 (FAIL)

```
  PASS  users\designer\connect.ps1 parses cleanly
  PASS  users\designer\connect.ps1 no smart quotes
  PASS  users\designer\connect.ps1 no en/em dashes in executable lines
  PASS  users\designer\connect.ps1 no invalid -replace backslash regex
  PASS  users\designer\connect.ps1 no bare Select-String [regex]::Escape
  PASS  users\designer\connect.ps1 no pipe-in-Set-ConnectTitle double-quote

--- repo git-mode dot-source ---
  PASS  repo git-mode loads Sanitize-SshAliasConfig
  PASS  repo git-mode loads Acquire-TunnelPort

--- dot-source smoke (functions load) ---
  PASS  Desktop editor-launch loads
  PASS  Desktop git-mode loads
  PASS  Desktop connect-ui loads
  PASS  Desktop cursor-auth loads

--- connect.bat bundle guards ---
  PASS  connect.bat requires connect-ui.ps1
  PASS  connect.bat requires editor-launch.ps1
  PASS  connect.bat requires git-mode.ps1
  PASS  connect.bat requires cursor-auth-laptop.ps1
  PASS  connect.bat requires connect-version.txt
  PASS  connect.bat requires Path.Combine
  PASS  connect.bat requires @(Choose-Project
  PASS  connect.bat requires Acquire-TunnelPort
  PASS  connect.bat checks ConnectVersion from connect-version.txt

3 check(s) failed.
EXIT:1
```

### `scripts/client/tests/test-select-project.ps1` — exit=0 (PASS)

```
=== Post-select pipeline test (non-interactive) ===

  PASS  @(Choose-Project)[-1] returns project id
  PASS  Path.Combine editor.conf path valid
  PASS  LeakySelect emits at least one object
  PASS  Path.Combine safe with pipeline context
  PASS  windows\connect.ps1 uses safe Choose-Project capture
  PASS  windows\connect.ps1 omits script path in header (v12)
  PASS  editor-launch uses Path.Combine not Join-Path

All select-project tests passed.
EXIT:0
```

### `scripts/client/tests/test-connect-diagnostic.ps1` — exit=0 (PASS)

```
=== Connect diagnostic ===

  PASS  Get-ConnectProblemVerdict defined
  PASS  Write-ConnectDiagnosticReport defined
  PASS  detects TUNNEL_DOWN
  PASS  TUNNEL_DOWN suggests R
  PASS  detects MOUNT_PATH_MISSING
  PASS  detects CURSOR_AGENT_HOME from launch history
  PASS  detects CURSOR_ON_FOLDER_OK
  PASS  F7 light SESSION_OPEN diagnostic gate
  PASS  F7 skips expensive process snapshot

All tests passed.
EXIT:0
```
