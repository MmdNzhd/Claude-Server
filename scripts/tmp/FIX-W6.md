# FIX-W6 — Designer / UX (NO DEPLOY)

Date: 2026-07-20  
Scope: bugs **8, 26, 52, 53, 70, 71** (`designer-pushconf-empty-no-clear`, `designer-design-key-or-vk`, `designer-no-single-instance-mutex`, `wait-connect-exit-before-ui`, `persian-quit-designer-win`, `persian-quit-connect-design`)  
Constraints: laptop-exec only (`-p claude-code-server`); **no deploy**; **no commit**.

## Fixed slugs

| # | Slug | Status |
|---|------|--------|
| 8 | `designer-pushconf-empty-no-clear` | Fixed — `Push-ServerConnectConf -ClearActiveMount` (4 call sites) |
| 26 | `designer-design-key-or-vk` | Fixed — `useVk` only for null/control KeyChar (designer + connect-design) |
| 52 | `designer-no-single-instance-mutex` | Fixed — both forks dot-source `connect-ui.ps1` + `Enter-ConnectSingleInstance` |
| 53 | `wait-connect-exit-before-ui` | Fixed — `ConnectUiReady` gates `Read-Host` in `Wait-ConnectExit`; main early trap/ssh use Get-Command fallback |
| 70 | `persian-quit-designer-win` | Fixed — no default `$action='q'`; Persian printable ignored; Q only via ASCII letter or gated VK / Enter |
| 71 | `persian-quit-connect-design` | Fixed — same `useVk` pattern on retry / session / kick menus |

## Files touched

| File | Change |
|------|--------|
| `scripts/client/connect-ui.ps1` | `$script:ConnectUiReady`; set `$true` at end of `Initialize-ConnectLog`; `Wait-ConnectExit` prompts only when ready |
| `scripts/client/users/designer/connect.ps1` | ClearActiveMount; connect-ui + mutex; Persian-safe session + post-menu keys; `Exit-ConnectSingleInstance` |
| `scripts/client/windows/connect-design.ps1` | connect-ui + mutex; Persian-safe R/Q loops; no seed quit; `Exit-ConnectSingleInstance` |
| `scripts/client/windows/connect.ps1` | **Minimal shared:** trap + missing-ssh no longer call `Wait-ConnectExit` before UI is loaded (Get-Command / Read-Host fallback) |

## Verify

Parse-check (laptop):

```powershell
powershell -NoProfile -File scripts\tmp\_w6-parse2.ps1
```

Result: **PARSE_OK** for designer, connect-design, connect-ui, connect.ps1; static HITs = 0.

## Leftover risks

1. Designer/connect-design share the same `Global\ClaudeConnect-{user}` mutex as main connect — intentional (prevents dual tunnels). Running designer while main connect is open will refuse with single-instance message.
2. Designer Mac `connect.sh` not in this pass (Windows PS forks only).
3. `Initialize-ConnectLog -Version 'designer'|'connect-design'` writes into the shared connect day-log sink — fine for audit; not a separate product log stream.
4. No interactive Persian-layout runtime test in this agent pass (static parity with main `connect.ps1` useVk gating).
