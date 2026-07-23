# STAGE-6 Evidence Pack

## ID
- Stage: 6 (windows-mcp no orphan cmd + auto_relaunch skip Settings + bat preflight ≤3 PS)
- CONNECT_VERSION: `20260722.40` (unchanged; no bump)
- Timestamp: 2026-07-22T17:30Z approx
- deploy_ran=no

## VERIFY
- Live fingerprint (pre-fix still present until reconnect):
  - `session=84a0d47796e2` `@16:32:42` `SESSION: auto_relaunch agent_home_streak=3 - reopening project folder` then `LAUNCH_BEGIN … agent_home=True` / `LAUNCH_PLAN: use_new_window=True reason=agent_home` (server day log `~/.claude/logs/connect-20260722.log`).
  - Earlier same day: `session=08eeab20d50f` `@15:54:47` same `auto_relaunch agent_home_streak=3` signature.
- windows-mcp cmd orphan (code + on-disk launcher):
  - Pre-fix `Start-WindowsMcpIfNeeded` / `Restart-WindowsMcpServer` used `Start-Process -FilePath …\start-server.cmd -WindowStyle Hidden`, leaving a long-lived `cmd.exe /c` parent.
  - Laptop `~\.windows-mcp\start-server.cmd` itself wraps another Hidden PowerShell `Start-Process` of `python -m windows_mcp serve …` — double wrapper risk when connect starts the `.cmd` directly.
- bat happy path pre-fix: multiple discrete `powershell` starts (run-id, BOOTSTRAP log, bootstrap, heal, update) before `connect-boot.ps1`.
- still_live=yes structurally until client relaunch with patched scripts.

## RESEARCH
1. https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.createnowindow — `CreateNoWindow` + `UseShellExecute=$false` avoids console host for direct child processes.
2. https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/cmd — `cmd /c` stays alive as parent when it launches long-running children without immediate exit in some launcher patterns; prefer direct `windows-mcp.exe` / `python -m windows_mcp serve`.
3. https://forum.cursor.com/t/cursor-keeps-opening-to-agents-view-instead-of-project/153009 — Cursor Agents/home false positives; Settings-focused windows also lack stable `folder-uri` titles and must not trigger auto_relaunch.

What this changes:
- Direct `Start-WindowsMcpProcessDirect` (exe or `python -m windows_mcp serve`) with `CreateNoWindow`; orphan `cmd.exe` reaper after listen OK
- `auto_relaunch_skip reason=cursor_settings` when any Cursor main title matches `(?i)settings`; hardened `Test-RemoteEditorInAgentHome`
- `connect-preflight.ps1` + bat early jump → ≤3 bat `powershell` starts ending at `connect-boot`

What we will NOT do:
- Version bump; deploy/publish; Sepidz unfreeze; edit Stage 3–5 packs

## RED_TEST
```
test-windows-mcp-no-orphan-cmd.ps1 → Passed: 1 Failed: 17
(pre-patch; connect-preflight.ps1 already present for bat test scaffolding)
```

## IMPLEMENT
- `scripts/client/windows/windows-mcp-laptop.ps1`: `Start-WindowsMcpProcessDirect`, `Stop-WindowsMcpOrphanCmdWrappers`; start/restart use helper (no `.cmd` Start-Process)
- `scripts/client/windows/connect.ps1`: Settings gate before auto_relaunch; keep one-shot `AutoRelaunchAttempted` otherwise
- `scripts/client/editor-launch.ps1`: `Test-RemoteEditorInAgentHome` — Agent/home title OR (no folder-uri AND title not Settings)
- `scripts/client/windows/connect-preflight.ps1`: NEW (run-id + day log + bootstrap/heal/update; exit 0/2/3)
- `scripts/client/windows/connect.bat`: early jump to preflight → `AFTER_CLIENT_UPDATE` / heal / update relaunch
- Tests registered in `scripts/client/tests/run-all.ps1`
- drive_by=none

## GREEN_TEST
```
test-windows-mcp-no-orphan-cmd.ps1 → Passed: 18 Failed: 0
test-connect-bat-max-ps-starts.ps1 → Passed: 12 Failed: 0
PARSE_OK windows-mcp-laptop.ps1 + connect-preflight.ps1 + connect.ps1 + editor-launch.ps1 + both tests + run-all.ps1
CONNECT_VERSION still 20260722.40
```

## LIVE_GATE
- `signature_absent=pending_reconnect` reason=`need client relaunch with patched scripts; expect no auto_relaunch while Settings focused (log auto_relaunch_skip reason=cursor_settings); expect started_via_windows_mcp_exe|started_via_python_direct and orphan_cmd_reaped if stale cmd wrappers; bat happy path via connect-preflight then connect-boot`

## GATE
`STAGE_6_DONE` 2026-07-22T17:30Z `deploy_ran=no` N+1 unlocked (Stage 6b)
