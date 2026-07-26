# Cursor MCP Pack

**Config path:** `~/.cursor/mcp.json` (per Linux user on the server).

Server-side Cursor agents get a shared **MCP pack** synced into each user's `~/.cursor/mcp.json`. Tools are **available but not mandatory** — Cursor invokes them when relevant to the task.

---

## Installed servers

| Server | Purpose |
|---|---|
| **Figma** | Inspect design files, frames, components, tokens |
| **Context7** | Up-to-date library/framework/API documentation |
| **Playwright** | Browser automation for UI verification |
| **Sequential Thinking** | Structured multi-step reasoning for complex tasks |
| **Memory** | Persistent knowledge-graph memory across chats (`~/.cursor/mcp-memory.jsonl`) |
| **sqlserver** | Read-only SQL Server queries (shared dev DB) |

## Memory

Cursor MCP id: `user-memory`. Agents are steered by always-on rule `mcp-memory.mdc`
to `search_nodes` / `create_entities` / `add_observations` for durable project facts.
Storage: `MEMORY_FILE_PATH` → `~/.cursor/mcp-memory.jsonl` (per user). Never store secrets.

Claude Code (terminal) keeps codegraph/headroom/sqlserver from add-user; `cursor-mcp-sync` also merges HTTP `figma`/`context7` (with Figma Bearer) and injects SQL env from `/etc/claude-code/sqlserver.env` — see [`CLAUDE.md`](../CLAUDE.md).

---

## General behavior

- MCP tools appear in the agent tool list after sync; the model **chooses** when to call them.
- Missing or auth-failed servers: the agent should say MCP is unavailable and point here — not silently guess.
- After any config change: **Reload Window** in Cursor (`Developer: Reload Window`) or start a new chat.

---

## Figma

1. **Fleet Cursor skills (preferred)** — `claude-server install` / `add-user` deploy official write-to-canvas skills plus a Smart router into each user's `~/.cursor/skills/`:
   - `figma-use` (mandatory before every `use_figma`)
   - `figma-generate-design` (multi-section screens from the design system)
   - `figma-create-new-file`
   - `figma-designer` (Smart router + prompt templates)
   Vendor pin: [`scripts/server/skills/FIGMA-SKILLS-VENDOR.md`](../scripts/server/skills/FIGMA-SKILLS-VENDOR.md). After install: **Reload Window**.
2. **Optional:** In Cursor chat, `/add-plugin figma` can add extra plugin skills; not required when the fleet trees above are present.
3. **Server golden OAuth (preferred for this fleet)** — `cursor-mcp-sync` injects a shared OAuth access token (`figu_…`, not PAT `figd_…`) from root-only `/etc/claude-code/figma-mcp.env` into each user's Cursor `~/.cursor/mcp.json` and Claude `~/.claude/settings.json` as `Authorization: Bearer …`. Re-sync: `sudo claude-server sync-cursor-mcp` (or `cursor-mcp-sync --all`). After sync: **Reload Window**.
4. **Optional per-user override** — `~/.config/cursor-mcp/figma-mcp.env` with `FIGMA_MCP_ACCESS_TOKEN=…` (mode `0600`).
5. **Manual OAuth Connect** still works in Cursor MCP settings if you prefer a personal login (on Remote SSH, `cursor://` callbacks must hit the Connect profile — see connect notes).
6. **Seat requirement** — the Figma account behind the token needs **Full** or **Dev** seat for MCP/API access (View-only may fail). **Write to canvas needs Full seat + edit permission** on the file. Shared golden login has the same ToS/concurrency caveats as Cursor golden auth.
7. **Blast radius** — the same OAuth access token is copied into every user's `~/.cursor/mcp.json` and `~/.claude/settings.json` (mode `0600`). Compromise of any home directory can expose the golden bearer; revoke/rotate by replacing `/etc/claude-code/figma-mcp.env` and re-running `sync-cursor-mcp --all`. Refresh token stays root-only in the golden env.
8. Token lifetime is finite (`expires_in` ~90 days); renew by re-exporting OAuth tokens into `/etc/claude-code/figma-mcp.env` and re-syncing.

Agent rule: [`scripts/server/cursor-rules/figma-design.mdc`](../scripts/server/cursor-rules/figma-design.mdc)  
Smart skill: [`scripts/server/skills/figma-designer/SKILL.md`](../scripts/server/skills/figma-designer/SKILL.md)

### Designer quick prompts (Club: also load `figma-designer/references/club-design-kit.md`)

Paste a Figma file or selection link, then ask in plain language. Examples:

**Build a page from requirements**

```
Using this Figma file: <PASTE_FILE_URL>
Build a new settings screen with auto layout using our existing components.
Requirements:
- …
```

**Edit a selection**

```
Using this selection: <PASTE_NODE_URL>
Change the primary button label to "Save" and keep existing components/variables.
```

**New file then design**

```
Create a new Figma Design file named "Onboarding draft", then using that file build an empty-state screen from our design system.
```

Agent should load `figma-designer` → `figma-use` / `figma-generate-design` as appropriate. Large screens work best section-by-section.

---

## Context7

Up-to-date docs for libraries and APIs (agent skill: [`scripts/server/skills/context7/SKILL.md`](../scripts/server/skills/context7/SKILL.md)).

**No API key required.** The pack points at `https://mcp.context7.com/mcp` and works out of the box (anonymous / free tier).

Optional: if you later want higher rate limits, you may set `CONTEXT7_API_KEY` in `~/.config/cursor-mcp/context7.env` (mode `0600`) and re-run `sudo claude-server sync-cursor-mcp $USER` — this is **not** required for normal use.


## SQL Server (`sqlserver`)

Connection secrets live outside git:

```bash
# ~/.config/cursor-mcp/sqlserver.env (mode 600)
SQLSERVER_HOST=192.168.210.124
SQLSERVER_USER=YourReadOnlyUser
SQLSERVER_PASSWORD=change_me
```

Then sync:

```bash
sudo claude-server sync-cursor-mcp YOUR_LINUX_USERNAME
```

**Read-only recommended** — use read-only SQL login for agents; avoid DDL/DML via MCP in normal workflows.

---

## Playwright & Sequential Thinking

- **Playwright** — UI smoke tests after Figma-driven or frontend changes (see figma-design rule).
- **Sequential Thinking** — optional structured planning for large backend or migration tasks (see backend-agent rule).

No extra env files required when bundled in the server MCP pack.

---

## Remote SSH / Agents Window caveat

When using **Remote SSH** with a **local** Cursor window (Agents on laptop profile):

- MCP config is synced to the **server** user's `~/.cursor/mcp.json` by `sync-cursor-mcp`.
- Some agent modes read MCP from the **local** `--user-data-dir` profile (e.g. `ClaudeServerCursorProfile` on Windows).
- If tools are missing in Agents chat but work on the server UI, copy or merge **`mcp.json`** (and env references) into the local profile's Cursor config, then Reload Window.
- See [`CLAUDE.md`](../CLAUDE.md) — Cursor golden auth and isolated profile sections.

---

## Sync command reference

```bash
sudo claude-server sync-cursor-mcp USER   # one user
sudo claude-server sync-cursor-mcp          # all users (if supported by install)
```

After deploy changes to the golden MCP pack, re-run sync and reload Cursor.


## Figma via server xray (stdio)

Figma MCP is **not** reached from the laptop `http.proxy`. Cursor launches `/usr/local/bin/mcp-via-xray` on the **Linux server** (stdio), which dials `https://mcp.figma.com/mcp` through server xray HTTP `127.0.0.1:10809`. Bearer token is injected by `cursor-mcp-sync` as `MCP_AUTH_HEADER` from `/etc/claude-code/figma-mcp.env`.

After changing the pack: `sudo claude-server sync-cursor-mcp` then **Reload Window**.

## Remote Machine proxy (server last-resort direct)

Remote Cursor inherits the laptop `http.proxy` (often `127.0.0.1:18998`), which does not exist on the server. `cursor-remote-proxy-sync` writes Machine settings under `~/.cursor-server/data/Machine/settings.json`:

| Condition | Mode | Machine settings |
|---|---|---|
| `ss` shows `127.0.0.1:10809` (xray up) | `xray_10809` | `http(s).proxy=http://127.0.0.1:10809`, `http.proxySupport=override` |
| 10809 down | `server_direct` | `http.proxySupport=off` (server NIC; no proxy) |

`server_direct` means **no proxy on the remote host**. It does not change xray routing: when xray is up, austria-xhttp remains the primary egress for Cursor IP unification. There is no austria→direct balancer (would risk office-IP leak).

Re-run:

```bash
sudo cursor-remote-proxy-sync --all
# or via install / MCP sync:
sudo claude-server install
sudo claude-server sync-cursor-mcp
```

Wired into: `install.sh`, `add-user.sh`, `claude-automount.sh` (per-login self), `cursor-mcp-sync` / `sync-cursor-mcp`.

