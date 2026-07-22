---
name: context7
description: >-
  Use when the user asks how to use a library, framework, or API, needs current
  documentation, setup instructions, migration guides, or code examples. Prefer
  Context7 MCP over training-data guesses for version-specific or fast-moving APIs.
---

# Context7 — up-to-date library docs

## When to use

Trigger this skill when the user:

- Asks how to configure or use a library, framework, SDK, or CLI
- Needs API reference, method signatures, or breaking changes
- Wants setup/install steps for a package or service
- Pastes an error that likely needs current docs (deprecated APIs, new config keys)

Do **not** rely on stale training data for version-specific answers — fetch docs first.

## Workflow (Context7 MCP)

When Context7 MCP tools are available in Cursor:

1. **Discover the tool schema** — use `GetMcpTools` for the Context7 server if needed.
2. **`resolve-library-id`** — map the library/framework name (and optional version) to a Context7 library ID.
3. **`query-docs`** — fetch focused documentation for the user's question.

Use the returned snippets and examples in your answer. Cite the library name and version when known.

## If MCP is missing

If Context7 tools are not listed or calls fail with auth/not-found:

- Tell the user Context7 MCP is not available in this session.
- Point them to [`docs/cursor-mcp-pack.md`](../../../docs/cursor-mcp-pack.md) for setup (`CONTEXT7_API_KEY`, `sudo claude-server sync-cursor-mcp`).
- Fall back to web search or project-local docs only when Context7 cannot run — say that answers may be less current.

## Tips

- Prefer narrow `query-docs` questions over dumping entire manuals.
- Combine with project code search after docs — verify imports and versions in the repo.
- For SQL Server schema questions on this server, use the **sqlserver** MCP (read-only) instead of Context7 when querying live data.
