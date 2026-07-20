# V5 connect-update.ps1 - DONE

File: `scripts/client/windows/connect-update.ps1`

## Changes

### 1. CLAUDE_CONNECT_RUN_ID bootstrap
- Added `Ensure-ConnectRunId` helper.
- Called once at script start (`$null = Ensure-ConnectRunId`).
- If `$env:CLAUDE_CONNECT_RUN_ID` is empty/whitespace, generates 12-hex via `[guid]::NewGuid().ToString('N').Substring(0, 12)` and sets env.
- Otherwise trims existing value.

### 2. Write-UpdateFileLog session id
- All file log lines use `$sid = $env:CLAUDE_CONNECT_RUN_ID.Trim()` (no `-` fallback).
- Log format unchanged: `[timestamp] [LEVEL] [sid] UPDATE: message`

### 3. -Quiet suppresses user output
- `$script:Quiet = [bool]$Quiet` set at startup.
- `Write-UpdateMsg` is the sole user-facing output path; gates on `$script:Quiet`.
- Audited: only one `Write-Host` in file (inside `Write-UpdateMsg`).
- All 11 `Write-UpdateMsg` call sites remain; none bypass Quiet.

### 4. File-log all decisions (Quiet-independent)
- `Write-UpdateFileLog` never checks Quiet.
- Added logs:
  - `bat_launch ... quiet=<bool>`
  - `checksum_verify_failed exit=1`
  - `staging_missing rel=<path>` per missing staged file
  - `ship_skip no_conf_or_log` when ship preconditions fail
- Existing decision logs retained (ssh/scp missing, unreachable, up_to_date, download/checksum/swap failures, ship stages).

### 5. ASCII
- Replaced mojibake em-dash in Invoke-SshTimed comment with `--`.

## Not changed
- No deploy.
- `connect.bat` unchanged (still sets run id before update when launched normally).
- Other client scripts untouched.

## Verify
```powershell
# Quiet: no console output, file log still written
$env:CLAUDE_CONNECT_RUN_ID = ''
& .\connect-update.ps1 -ScriptDir $PWD -Quiet
Get-Content "$env:USERPROFILE\.config\claude-connect\logs\connect-$(Get-Date -Format yyyyMMdd).log" -Tail 5
```
