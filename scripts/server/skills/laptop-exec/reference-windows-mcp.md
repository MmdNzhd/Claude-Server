# Windows-MCP ops (progressive disclosure)

Loaded from [SKILL.md](SKILL.md) when needed. Routing/failover lives in SKILL.md.

## Contents

- Product model / install
- Interactive session (UI)
- FAIL-FAST + failover notes
- Server helper paths
- Fully qualified MCP tool names

## Product model

- Local Cursor on Windows: often `stdio` via `uvx windows-mcp serve`.
- Remote-SSH agents (Linux): laptop `streamable-http` on `127.0.0.1:18765`
  (avoid `8000` — Hyper-V/WSL often reserves `7916-8015`), forwarded to
  per-user `127.0.0.1:28000+(UID-1000)`, Cursor MCP URL + Bearer.

Docs: https://github.com/CursorTouch/Windows-MCP

```text
windows-mcp install --transport streamable-http --host 127.0.0.1 --port 18765
```

Creates task `windows-mcp-server` + `~\.windows-mcp\start-server.cmd` (AtLogOn).
Auth: `~/.windows-mcp/config.toml` (`auth_key`).

## Interactive session (UI)

Screenshot/Click/Type/Snapshot need the same interactive Windows session as
explorer. Prefer official install or user-started `start-server.cmd`.

## FAIL-FAST + failover

1. Tools not listed → MCP down; use mount + `laptop-exec`.
2. One `ECONNREFUSED` / fetch failed / not connected → MCP down for session;
   continue mount + LE; never retry that same call (circuit open).
3. Mount EPERM/STALE/EIO → MCP then LE — keep working.
4. `user-filesystem` ≠ windows-mcp.
5. FileSystem: `mode=` (`read`/`write`/`list`/`search`/…), never `action=`.
6. Relative FileSystem paths → Desktop; always absolute under project root.
7. Tell user once if needed: `connect.bat`, start-server, Reload Window.

## Fully qualified MCP names

Prefer qualified names in prompts/docs:

- `user-windows-mcp` FileSystem (`mode=read|write|list|search`)
- `user-windows-mcp` PowerShell (`Select-String` for content Grep failover)

## Server helpers

| Item | Path |
|------|------|
| Auth env | `~/.config/windows-mcp/env` (mode 600) |
| Forward CLI | `~/.local/bin/windows-mcp-forward` |
| Cursor MCP | `~/.cursor/mcp.json` → per-UID `WINDOWS_MCP_FORWARD_PORT` |

Watchdog restarts a dead forward ~30s while tunnel UP; connect maintain ~3 min.
