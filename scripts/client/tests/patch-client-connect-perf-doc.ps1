# One-shot: add PERF logging section to docs/client-connect.md (run from repo root on laptop)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$p = Join-Path $root 'docs\client-connect.md'
if (-not (Test-Path $p)) { throw "Not found: $p" }
$text = Get-Content $p -Raw
if ($text -match 'Performance marks \(v20260714\.4\+\)') {
    Write-Host 'docs already patched'
    exit 0
}
$old = @'
## Logging (Windows)

`connect.log` is written next to `connect.bat`. Rotates at 1.5 MB to `connect.log.1`.

Useful lines:

```
[INFO]  PROJECT: id=...
[INFO]  ACTIVE_MOUNT: ...
[DEBUG] FOLDER_CHECK: on_folder=... agent_home=...
[INFO]  LAUNCH_CMD: ... --folder-uri vscode-remote://...
[INFO]  STATUS: [... | Cursor]
```
'@
$new = @'
## Logging (Windows)

`connect.log` is written next to `connect.bat`. Rotates at 1.5 MB to `connect.log.1`.

### Performance marks (v20260714.4+)

Cheap `PERF[...]` lines are emitted by default across mount, auth, launch, and diagnostic. Disable with:

```
set CLAUDE_CONNECT_PERF_LOG=0
```

Verbose launch diagnostics (WMI snapshots) only when debugging slowness:

```
set CLAUDE_CONNECT_VERBOSE_LAUNCH=1
```

Summarize a session log on Windows:

```bat
powershell -NoProfile -File scripts\client\tests\parse-connect-perf.ps1 -LogPath connect.log
```

**Expected gates after Tier A fixes:** cold `Opening Cursor` under 8000 ms, skip path under 1500 ms, `SNAPSHOT` count 0 unless verbose mode.

Useful lines:

```
[INFO]  STEP end: Opening Cursor ok ms=...
[DEBUG] PERF[launch_total] ms=... cim_total=...
[DEBUG] PERF[session_open_summary] ms=0 mount_ms=... auth_ms=... open_ms=... diag_ms=...
[INFO]  LAUNCH_SKIP: already on correct folder - keeping Cursor open
[INFO]  PROJECT: id=...
[INFO]  ACTIVE_MOUNT: ...
[DEBUG] FOLDER_CHECK: on_folder=... agent_home=...
[INFO]  STATUS: [... | Cursor]
```
'@
if (-not $text.Contains($old.Trim())) { throw 'Logging section block not found - manual merge needed' }
$text = $text.Replace($old, $new)
$text = $text.Replace(
    'Key tests: `test-connect-pipeline.ps1`, `test-git-mode-deep.ps1`, `test-editor-launch.ps1`, `audit-local-connect.ps1`.',
    'Key tests: `test-connect-pipeline.ps1`, `test-editor-launch-strategies.ps1`, `test-parse-connect-perf.ps1`, `test-git-mode-deep.ps1`, `audit-local-connect.ps1`.'
)
Set-Content -Path $p -Value $text -Encoding UTF8 -NoNewline
Write-Host "Patched: $p"
