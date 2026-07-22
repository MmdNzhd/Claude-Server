# Cursor Figma + Context7 MCP Pack — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every Cursor Remote SSH user a curated MCP + skills pack so designers can work with Figma from Cursor, and agents get current library docs via Context7 — plus a small set of high-value companion MCP/skills.

**Architecture:** Cursor-first. Manage per-user `~/.cursor/mcp.json` on the Linux server (Remote SSH Editor uses remote MCP). Prefer **remote HTTP** MCP endpoints (Figma, Context7) over stdio for SSH reliability. Ship Figma + Context7 as must-have; Playwright as recommended companion; document GitHub / Chrome DevTools / Magic UI as optional. Add a safe merge sync for existing users (never full-overwrite `settings.json` / `mcp.json`). Mirror Claude Code template only as secondary (optional parity), not the primary path.

**Tech Stack:** Cursor MCP (`mcp.json`), Figma remote MCP (`https://mcp.figma.com/mcp`), Context7 remote MCP (`https://mcp.context7.com/mcp`), Playwright MCP (`npx @playwright/mcp`), bash deploy via `claude-server` / `add-user` / new `sync-cursor-mcp`, Figma Cursor plugin skills, Context7 skill/rule.

## Global Constraints

- Target client = **Cursor** (Remote SSH). Claude Code MCP is optional parity only.
- Project hooks must stay `{"version":1,"hooks":{}}`; do not put MCP guards in project hooks.
- No interactive sudo prompts; use `sudo-from-laptop --smart` for deploy.
- Never commit API keys / OAuth tokens; use per-user env files mode `0600`.
- Prefer HTTP MCP over stdio on Remote SSH; stdio Playwright is allowed but documented as flaky risk.
- Figma write-to-canvas needs **Full** seat (Dev = read-only outside drafts); Starter/View/Collab ≈ 6 calls/month — useless for real work.
- Do not share one Figma OAuth account across all users (ToS + token conflicts, same class of risk as Cursor golden auth).
- Keep active MCP count low (≈3–5) to avoid tool-discovery token bloat.
- Language in scripts: English only (project rule).
- Source of truth for repo edits: laptop via `laptop-exec -p claude-code-server`.

## Research snapshot (2026-07-20)

### Must ship

| Item | Why | Auth | Cursor install |
|------|-----|------|----------------|
| **Figma remote MCP** | Design → code + write-to-canvas for kids designing in Figma | Per-user OAuth | `/add-plugin figma` (preferred) or `url: https://mcp.figma.com/mcp` |
| **Figma skills** | `figma-use`, `figma-create-new-file`, `figma-generate-design`, `figma-generate-diagram`, … | Bundled with plugin | Included by Figma Cursor plugin |
| **Context7 MCP** | Up-to-date library docs; stops hallucinated APIs | API key preferred (`CONTEXT7_API_KEY`) | `url: https://mcp.context7.com/mcp` + headers |
| **Context7 skill/rule** | Auto-trigger docs lookup without typing "use context7" | Same key | `npx ctx7 setup --cursor` or hand-install skill under `~/.cursor/skills/` |

### Strongly recommend (include in pack)

| Item | Why | Notes |
|------|-----|-------|
| **Playwright MCP** | Verify UI after implementing Figma | `npx -y @playwright/mcp@latest`; stdio — may be flaky on some Remote SSH Agent windows |
| **Chrome DevTools MCP** | Console/network/performance when UI breaks | Already common in Cursor plugins; optional if Playwright covers QA |
| **frontend-design skill (ECC)** | Avoid generic AI UI; brand/composition rules | Already available via ECC plugin for Claude; mirror Cursor rule/skill for design kids |

### Backend / database (research 2026-07-20)

Industry consensus for data agents: **Supabase or Postgres MCP** for Postgres stacks; **specialist per engine** otherwise; always **read-only / staging first**.

#### MCP — pick by your DB engine

| Stack | Best MCP | Why | Auth / safety |
|-------|----------|-----|---------------|
| **SQL Server (this team already)** | Keep `@bilims/mcp-sqlserver` (Claude today) + mirror into Cursor; longer-term prefer **Microsoft SQL MCP (Data API Builder)** or **DBHub** | Team already uses `192.168.210.124` via Claude `sqlserver` MCP | Read-only login; never shared prod SA |
| Self-hosted **Postgres** | **Postgres MCP Pro** (CrystalDBA) | Index tuning (HypoPG), EXPLAIN, health checks, restricted mode | Restricted/read-only on prod |
| **Supabase** | Official `https://mcp.supabase.com/mcp` | Full BaaS: SQL, migrations, types, edge, advisors | OAuth + `?read_only=true` + project_ref |
| **Neon** serverless Postgres | Neon remote MCP | Branch-based safe migrations | OAuth hosted |
| **MongoDB / Atlas** | Official MongoDB MCP | 50+ ops; Atlas advisor; `--readOnly` | Start readOnly |
| Multi-engine / MySQL / SQLite / SQL Server gateway | **DBHub** (Bytebase) | One gateway, token-efficient | Read-only mode |
| Google Cloud multi-DB | **MCP Toolbox for Databases** | AlloyDB, BigQuery, Cloud SQL, … | Overkill if single SQL Server |
| Analytics warehouse | **ClickHouse MCP** | Read-heavy by design | SELECT-only tools |

**For Smart team default recommendation:**  
1. **v1 design pack** stays Figma + Context7 + Playwright (unchanged).  
2. **Backend track (v1.1):** expose existing **sqlserver** MCP to Cursor (`~/.cursor/mcp.json`) with per-user env (same pattern as Claude), **read-only** credentials.  
3. **If Postgres projects appear:** add Postgres MCP Pro or Supabase (not both by default).  
4. Do **not** auto-install Mongo/Neon/ClickHouse unless a project needs them.

#### Skills — backend counterparts to Sequential Thinking + frontend-design

| Skill | Role | Source |
|-------|------|--------|
| **Sequential Thinking** MCP | Structured multi-step reasoning (API design, migrations, incident plans) | Optional MCP — keep as recommend |
| **frontend-design** (ECC) | UI composition / brand | Already in pack discussion |
| **backend-patterns** (ECC) | API layout, DB schema patterns, caching — true counterpart to frontend-design | ECC (already in marketplace) |
| **database-migrations** (ECC) | Safe schema changes, zero-downtime, Prisma/Django/Drizzle/… | ECC |
| **api-design** (ECC) | REST/OpenAPI contracts | ECC |
| **postgres-patterns** / **mysql-patterns** / **prisma-patterns** | Engine/ORM-specific | ECC — enable per stack |
| **fastapi-patterns** / **django-patterns** / **dotnet-patterns** | Framework backends | ECC — enable per stack |
| Context7 (already core) | Live docs for EF Core, Dapper, FastAPI, Prisma, … | Complements skills |

**Suggested skill trio for backend kids:** `backend-patterns` + `database-migrations` + Context7 (with Sequential Thinking for hard designs).

#### Security rules (non-negotiable for DB MCP)

- Start **read-only** / replica / staging; write only on disposable DBs.
- Per-user credentials; never one shared SA in template.
- Prefer entity/RBAC gateways (Microsoft DAB SQL MCP) over raw SQL for production.
- Keep MCP count lean: design pack (3) + at most **one** DB MCP active per user.

### Optional / later (document, do not auto-install)

| Item | When to add |
|------|-------------|
| **GitHub MCP** (official remote) | Team lives in PRs/issues from Cursor |
| **Magic UI MCP** | Heavy React/Tailwind marketing UI |
| **Sequential Thinking MCP** | Complex multi-step planning only |
| **Sentry / Linear / Notion** | Ops / PM workflows — not design core |
| **Firecrawl / Brave Search** | External research — Cursor WebSearch often enough |
| **Figma desktop MCP** (`127.0.0.1:3845`) | Enterprise only; prefer remote |

### Famous “starter 3” (industry consensus 2026)

Most “best MCP 2026” lists converge on: **Context7 + GitHub + Playwright**. For this team’s stated goal (kids design in Figma via Cursor), replace GitHub with **Figma** as core #1, keep Context7 + Playwright.

### Seat / quota gotchas (must tell users)

| Product | Gotcha |
|---------|--------|
| Figma | View/Collab/Starter → ~6 tool calls/month. Need **Dev or Full** on Pro+. Write canvas → **Full**. |
| Context7 | Free ~1000 calls/mo; anonymous weaker. Prefer per-user API key. |
| MCP count | >5–6 servers → tool schema burns context; keep lean. |

### Remote SSH nuance (Cursor)

- **Editor Window** MCP: reads **remote** `~/.cursor/mcp.json` (Linux home).
- **Agents Window** (known limitation): may read **local Windows** `mcp.json` instead of remote.
- This project’s `connect.ps1` uses isolated profile `--user-data-dir …\ClaudeServerCursorProfile` — laptop-side MCP may need a **second** mirror for Agents Window parity.
- Prefer HTTP MCP so both sides can point at the same URL without remote stdio subprocess pain.

---

## File map (create / modify)

| Path | Responsibility |
|------|----------------|
| `scripts/server/cursor-mcp-template.json` | Golden template of MCP servers (no secrets) |
| `scripts/server/cursor-mcp-sync.sh` | Merge template into `/home/$USER/.cursor/mcp.json`; never delete unknown keys; never write secrets |
| `scripts/server/commands/sync-cursor-mcp.sh` | `claude-server sync-cursor-mcp [user\|all]` wrapper |
| `scripts/server/commands/add-user.sh` | Call cursor-mcp-sync after cursor-auth-sync; ensure `~/.cursor` exists |
| `scripts/server/commands/install.sh` | Deploy new scripts + `claude-server` subcommand |
| `scripts/server/claude-server` (dispatcher) | Wire `sync-cursor-mcp` |
| `scripts/server/skills/context7/` or install via ctx7 | Cursor skill for auto docs |
| `scripts/server/cursor-rules/figma-design.mdc` (optional) | Short rule: paste Figma link, use Figma MCP, then Context7 for framework APIs |
| `docs/cursor-mcp-pack.md` | User-facing setup: OAuth Figma, Context7 key, seats, `/add-plugin figma` |
| `CLAUDE.md` | Update MCP table: Cursor pack + Claude optional |
| Optional: `scripts/client/...` note | Mirror HTTP MCP into Windows ClaudeServerCursorProfile if Agents Window needed |
| Optional parity: `add-user.sh` Claude `mcpServers` HTTP entries | Only if we want Claude Code same tools |

**Out of scope for v1:** Magic UI, GitHub MCP auto-install, sharing one Figma login, desktop Figma MCP, overwriting existing user `mcp.json` wholesale.

---

## Recommended Cursor `mcp.json` shape (template)

```json
{
  "mcpServers": {
    "figma": {
      "url": "https://mcp.figma.com/mcp"
    },
    "context7": {
      "url": "https://mcp.context7.com/mcp",
      "headers": {
        "CONTEXT7_API_KEY": "${CONTEXT7_API_KEY}"
      }
    },
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    }
  }
}
```

Notes:
- If Cursor does not expand `${CONTEXT7_API_KEY}` in headers, sync script writes key from `/home/$USER/.config/cursor-mcp/context7.env` (mode 0600) into headers at sync time, or documents Settings → env injection.
- Figma auth is OAuth via Cursor UI Connect — no key in file.
- Playwright optional behind flag `CURSOR_MCP_PLAYWRIGHT=1` if we want leaner default (recommend **on** for design kids).

---

### Task 1: Add Cursor MCP template + sync script

**Files:**
- Create: `scripts/server/cursor-mcp-template.json`
- Create: `scripts/server/cursor-mcp-sync.sh`
- Create: `scripts/server/commands/sync-cursor-mcp.sh`
- Modify: `scripts/server/claude-server` (or install dispatcher) to expose subcommand
- Modify: `scripts/server/commands/install.sh` deploy section

- [ ] Write `cursor-mcp-template.json` with `figma` + `context7` (+ `playwright` if default-on).
- [ ] Implement `cursor-mcp-sync.sh`:
  - Args: `--user NAME` or `--all`
  - Ensure `/home/$USER/.cursor` exists (0700)
  - Merge template keys into `mcp.json` with Python/`jq` (preserve user custom servers)
  - If `/home/$USER/.config/cursor-mcp/context7.env` exists and contains `CONTEXT7_API_KEY=…`, inject into context7 headers
  - Never log the key; chmod 0600 on env + mcp.json
  - Idempotent; print OK/skip per user
- [ ] Add `claude-server sync-cursor-mcp` → calls sync script
- [ ] Deploy paths in `install.sh` (install binary to `/usr/local/bin/cursor-mcp-sync`, lib template under `/usr/local/lib/claude-server/`)
- [ ] Smoke on one user: `sudo-from-laptop --smart -- cursor-mcp-sync --user smart` then verify `~/.cursor/mcp.json` (mask secrets)
- [ ] Commit: `Add cursor-mcp-sync and Figma/Context7 MCP template`

---

### Task 2: Wire add-user + document seats

**Files:**
- Modify: `scripts/server/commands/add-user.sh`
- Create: `docs/cursor-mcp-pack.md`
- Modify: `CLAUDE.md` MCP section

- [ ] After `cursor-auth-sync` in add-user, call `cursor-mcp-sync --user "$USERNAME"`.
- [ ] Write user doc covering:
  1. Open Cursor Remote → Settings → Tools & MCP → Connect **figma** (OAuth)
  2. Preferred: chat `/add-plugin figma` (skills)
  3. Context7: create key at context7.com/dashboard → put in `~/.config/cursor-mcp/context7.env` → re-run sync
  4. Seat requirements table (Figma Full/Dev)
  5. Workflow: copy Figma frame link → Agent “implement this design” → Context7 for framework APIs → Playwright check localhost
  6. Remote SSH Agents Window caveat + optional Windows profile mirror
- [ ] Update `CLAUDE.md` MCP table with Cursor pack; keep codegraph/headroom/sqlserver for Claude.
- [ ] Commit: `Wire cursor MCP pack into add-user and docs`

---

### Task 3: Skills + rules for design workflow

**Files:**
- Create or vendor: Context7 Cursor skill under `scripts/server/skills/context7/SKILL.md` (or document `npx ctx7 setup --cursor` per user)
- Create: `scripts/server/cursor-rules/figma-design.mdc` (short)
- Modify: `laptop-exec-setup.sh` / install to copy rule+skill into each `~/.cursor/skills/` and `~/.cursor/rules/` (same pattern as laptop-exec skill)

- [ ] Context7 skill description must auto-trigger on library/framework/API questions.
- [ ] Figma design rule: when user pastes figma.com URL or asks to design/implement UI, use Figma MCP tools; do not invent layout from screenshots alone; after code, prefer Playwright check.
- [ ] Document that `/add-plugin figma` still installs official Figma skills (`figma-use`, etc.) — our rule complements, does not replace.
- [ ] Install skill/rule via `install.sh` + per-user setup (like laptop-exec-setup).
- [ ] Commit: `Add Context7 skill and Figma design Cursor rule`

---

### Task 4: Roll out to existing users + verify

**Files:**
- Modify: `scripts/server/commands/verify.sh` (assert mcp.json has figma+context7 keys)
- Optional: one-shot note in `docs/cursor-mcp-pack.md` for Windows Agents Window mirror

- [ ] `sudo-from-laptop --smart -- claude-server install`
- [ ] `sudo-from-laptop --smart -- claude-server sync-cursor-mcp` (all users)
- [ ] `claude-server verify` checks new keys
- [ ] Manual QA checklist (one designer account):
  - [ ] Figma Connect OAuth succeeds
  - [ ] Agent can `whoami` / fetch design from a frame link
  - [ ] Context7 resolves e.g. React / Tailwind docs
  - [ ] Playwright opens localhost (if enabled)
  - [ ] Confirm seat type via Figma whoami if available
- [ ] Commit: `Verify cursor MCP pack and roll out sync`

---

### Task 5 (optional parity): Claude Code HTTP MCP

Only if product owner wants Claude Code to match Cursor.

- [ ] Add HTTP `figma` + `context7` to `add-user.sh` Claude `mcpServers` template (type http/url).
- [ ] Enable plugins: `figma@claude-plugins-official`, Context7 marketplace — or document one-shot `claude plugin install`.
- [ ] **Do not** full-overwrite existing users’ `settings.json`; write `merge-claude-mcp` similar to cursor sync.
- [ ] Commit separately if done.

---

## Acceptance criteria

1. New user via `add-user` gets `~/.cursor/mcp.json` with figma + context7 (+ playwright if default).
2. `claude-server sync-cursor-mcp` updates all existing homes without wiping custom MCP entries.
3. Docs explain Figma OAuth, seats, Context7 key, and design→code workflow.
4. Skills/rules installed so agents auto-use Context7 and Figma appropriately.
5. No secrets in git; env files 0600.
6. CLAUDE.md lists the Cursor pack.

## Explicit non-goals (v1)

- Auto-provisioning Figma seats / org SSO
- Magic UI / Sequential Thinking / GitHub MCP as defaults
- Forcing desktop Figma MCP
- Shared team Figma bot account

## Rollback

- Remove keys from template; re-run sync with `--prune-pack` (implement only if needed) or manually delete figma/context7/playwright entries.
- `claude-server install` previous revision from git.

---

## Suggested decision defaults (locked for implementer unless user overrides)

| Decision | Default |
|----------|---------|
| Client | Cursor only (Claude optional Task 5) |
| Figma transport | Remote HTTP |
| Context7 auth | Per-user API key file |
| Playwright | Included by default |
| GitHub MCP | Document only, not auto |
| Chrome DevTools | Document; skip auto if Playwright on |
| ECC frontend-design | Add Cursor rule pointer / ensure ECC skill visible |
| Windows Agents Window | Document caveat; optional follow-up to mirror HTTP MCP into ClaudeServerCursorProfile |

---

## Implementation order

1 → 2 → 3 → 4 → (5 optional)

After plan approval, implement with subagent-driven-development; commit per task.
