# Windows-MCP + laptop-exec (ops)

Companion to `SKILL.md`. Keep `laptop-exec` forever (Mac + git + content `rg`).

**Priority:** on Windows when MCP is ready, use windows-mcp for FS/shell/UI
**first**; `laptop-exec` is fallback (and always for Mac + git + content `rg`).

## Official product model

- Local Cursor on Windows: often `stdio` via `uvx windows-mcp serve`.
- Our Remote-SSH agents (Linux): `streamable-http` on laptop
  `127.0.0.1:18765` (not `8000` — Hyper-V/WSL often reserves `7916-8015`),
  forwarded to a **per-user** server port `127.0.0.1:28000+(UID-1000)` (never a
  shared literal like the old `18000` — that port is bound server-wide in one
  netns, so a fixed value only ever works for the first user who claims it),
  Cursor MCP URL + Bearer.

Docs: https://github.com/CursorTouch/Windows-MCP  
Install on laptop (interactive user session):

```text
windows-mcp install --transport streamable-http --host 127.0.0.1 --port 18765
```

Creates task `windows-mcp-server` + `~\.windows-mcp\start-server.cmd` (AtLogOn).
Auth in `~/.windows-mcp/config.toml` (`auth_key`; optional `auth.key` mirror).

## Session rule

UI tools (Screenshot, Click, Type, Snapshot) need an **interactive** Windows
session (same session as explorer). Process started only via SSH Session 0 may
serve HTTP/FS but fail screen grab / some PowerShell. Prefer official `install`
or user-started `start-server.cmd` on the desktop.

## Server helpers

| Item | Path |
|------|------|
| Auth env | `~/.config/windows-mcp/env` (mode 600) |
| Forward CLI | `~/.local/bin/windows-mcp-forward` |
| Cursor MCP | `~/.cursor/mcp.json` → `http://127.0.0.1:PORT/mcp` (PORT = `WINDOWS_MCP_FORWARD_PORT` in the env file, per-UID, default `28000+(UID-1000)`) |

After connect: ensure forward is up if MCP tools fail to connect. Watchdog
restarts a dead forward every ~30s while the tunnel is UP; connect mid-session
maintain re-syncs every ~3 minutes.

## Skill vs MCP vs CLI (why hybrid)

- **Skill** = routing SOP (this file + SKILL.md).
- **MCP** = windows-mcp tools (FS/UI/shell with schema).
- **CLI** = `laptop-exec` (mux-safe SSH to laptop disk; required on Mac).

Do not collapse to MCP-only.
