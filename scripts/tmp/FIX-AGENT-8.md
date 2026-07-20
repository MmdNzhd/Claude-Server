# Fix Agent 8 — Designer / UX

Date: 2026-07-20  
Scope: designer + connect-design + connect-ui (+ early Wait-ConnectExit guards in main connect.ps1)  
Constraints: laptop-exec only; no deploy; no commit. Main tunnel logic left to Agents 3/5.

## Bugs fixed

| # | Slug | Fix |
|---|------|-----|
| 8 | `designer-pushconf-empty-no-clear` | Win: `Push-ServerConnectConf -ClearActiveMount` (not `-ActiveMount ''`). Mac: `push_server_connect_conf --clear` whenever clearing. |
| 26 | `designer-design-key-or-vk` | Designer Win + connect-design: ASCII letter + `useVk` only for null/control KeyChar (match main `.31`). |
| 52 | `designer-no-single-instance-mutex` | Designer Win + connect-design source `connect-ui.ps1` and call `Enter-ConnectSingleInstance` (same `Global\ClaudeConnect-{user}` as main). |
| 53 | `wait-connect-exit-before-ui` | `Wait-ConnectExit` respects `ConnectUiReady` (no prompt pre-UI); guards `Write-ConnectLog`/sync/close/mutex. Main connect trap/ssh/Die: `Get-Command Wait-ConnectExit` fallback to `Read-Host` before UI load. |
| 59 | `post-disconnect-layout-parity` | Designer Mac: post-disconnect C/X menu with ASCII-only keys; ignore non-ASCII (Persian). |
| 70 | `persian-quit-designer-win` | No default quit on any key; Persian ض ignored; Q only via ASCII `q` or VK when KeyChar null/control. |
| 71 | `persian-quit-connect-design` | `Resolve-DesignKeyLetter` + same useVk policy on session/retry/kick loops. |

## Files touched

- `scripts/client/users/designer/connect.ps1`
- `scripts/client/users/designer/connect.sh`
- `scripts/client/windows/connect-design.ps1`
- `scripts/client/connect-ui.ps1` (`Wait-ConnectExit` harden)
- `scripts/client/windows/connect.ps1` (early exit guards only — not tunnel logic)

## Key policy (canonical)

```
$code = [int] KeyChar
$ascii = ($code -ge 32 -and $code -le 126)
$letter = ascii ? ToLower : ''
$useVk = ($code -eq 0 -or ($code -gt 0 -and $code -lt 32))
# match letter OR (useVk AND ConsoleKey)
# Persian printable (ض on Q): useVk=false → ignored
```

## Verify

- PS parser: designer/connect.ps1, connect-design.ps1, connect-ui.ps1 → OK
- `bash -n` designer/connect.sh → OK
- No `ActiveMount ''` clears left in designer
- No `KeyChar … -or ConsoleKey` quit patterns in designer/design

## Not done

- Deploy / publish / commit (per instructions)
- Main connect Persian quit already in `.31` (left alone except early Wait-ConnectExit)
