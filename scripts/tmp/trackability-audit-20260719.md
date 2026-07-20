# Connect trackability audit — 2026-07-19

## Deployed / source
- Sepidz server was `20260719.24` (P0 recovery present)
- Source now `20260719.25` with trackability + Farzad-bug fixes
- Smart frozen at `20260717.22` (must stay)

## Bugs found in Farzad `connect-20260719.log` (farzadb / f.bahadorifar)

| Bug | Root cause | Fix in .25 |
|-----|------------|------------|
| ACTIVE_MOUNT stuck `backend` while client prefers `frontend` | `Push-ServerConnectConf` used `AM=""` inside Windows OpenSSH remote → quotes eaten → `elif` syntax error (exit 2); conf never written | base64\|bash remote + `PUSH_CONF ok/fail` INFO with `PUSH_CONF_RESULT` |
| Accidental quit on `ض` (`key=Q keychar=ض`) | `$action='q'` default + any unrecognized key fell through to disconnect; also `ConsoleKey::Q` with Persian KeyChar | default `action=''`; ignore non-ASCII; disconnect **only** if `action -eq 'q'`; log `SESSION_KEY ignore` |
| CLEAR_MOUNT looked like crash | User quit path; reason not logged | `reason=user_quit` / `auto_recovery` on CLEAR_MOUNT |

## Logging trackability

| Event | Level | Syncs to server `~/.claude/logs` |
|-------|-------|----------------------------------|
| SESSION / UPDATE / LAUNCH / VERDICT | INFO | yes (batch) |
| PUSH_CONF begin/ok/fail | INFO/ERROR | yes (.25) |
| SESSION_KEY ignore / disconnect reason | INFO | yes (.25) |
| RECOVERY_SKIP / FINALLY_KEEP | WARN | yes (immediate) |
| GITMODE DEBUG/TRACE | DEBUG/TRACE | local file; syncs when INFO/WARN flushes or session close |

## Still open (not blockers)
- Pre-existing test FAIL: `git menu option` assert
- Project menu WARN spam on Persian input (a/e/d/c/g/q) — separate from session key
- Farzad needs relaunch after .25 deploy to exercise new code
