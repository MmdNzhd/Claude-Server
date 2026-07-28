---
name: laptop-exec
description: >-
  Priority+failover I/O for ~/mounts: healthy mount ⇒ Cursor Read/Grep
  (never laptop-exec read/rg first); Write ⇒ windows-mcp then mount then LE;
  git ⇒ laptop-exec only. Use when choosing mount vs MCP vs laptop-exec,
  recovering from EPERM/STALE/ECONNREFUSED, or fixing bad LE CLI (no
  --glob/-A/--offset). Prefer 1st path; if it fails, use next same turn.
---

# Laptop Exec — priority + failover

**HARD RULE:** If the SSHFS mount is healthy, **never** call `laptop-exec read`
or `laptop-exec rg` first. Use Cursor **Read** / **Grep** on `/mounts/`.
LE read/rg is **failover only** (~20–28× slower). LE is required for **git**.

Three paths to the laptop disk. Prefer the fastest healthy path; if it fails,
use the next immediately — never stuck.

| Shortcut | Meaning |
|----------|---------|
| **mount** | Cursor Read/Grep/Write/Glob on `/home/$USER/mounts/PROJECT/` |
| **MCP** | `user-windows-mcp` / `windows-mcp` FileSystem + PowerShell (abs Windows paths) |
| **LE** | `laptop-exec -p PROJECT …` over the reverse tunnel |

Ops / install / ports → [reference-windows-mcp.md](reference-windows-mcp.md)

## When to use

- Choosing between Cursor tools vs `user-windows-mcp` FileSystem vs LE failover
- `laptop-exec` **git** / **run** (builds) / read-rg **only after** mount+MCP fail
- Mount glitches (EPERM, STALE, EIO) or MCP down (not listed, ECONNREFUSED)

## Priority chains (measured 2026-07-26)

| Action | 1st | 2nd (same turn if 1st fails) | 3rd | Parallel |
|--------|-----|------------------------------|-----|----------|
| **Read** | mount Cursor **Read** | MCP FileSystem `mode=read` | `laptop-exec read` | mount ~16–32; MCP ~8–12; LE ≤4 |
| **Grep (content)** | mount Cursor **Grep** | MCP PowerShell `Select-String` | `laptop-exec rg` | mount ~16–32; SS ~4–8; LE ≤4 |
| **Glob / by name** | MCP FileSystem `search`/`list` | mount Glob / `ls` | `laptop-exec run` | MCP ~8–12; mount ~16 |
| **Write / Edit** | MCP FileSystem `mode=write` | mount Write/StrReplace | `laptop-exec write` | MCP ~8–10; mount ~10; LE ≤4 |
| **git** | `laptop-exec git` only | — | — | LE ≤4 |
| **Shell build/test** | MCP PowerShell | `laptop-exec run` | mount Shell | MCP free; LE ≤4 |
| **UI** | MCP only | — | — | — |

**Healthy default:** Read/Grep → mount. Write/Glob → MCP.  
**Not:** “MCP tools are listed → always FileSystem read.”  
**Not:** “Shell → laptop-exec read/rg while mount works.”

## Failover / circuit breaker

| Symptom | Next path |
|---------|-----------|
| Mount EPERM / STALE / EIO / not mounted | MCP (abs path) → LE |
| MCP not listed / one hard fail (`ECONNREFUSED`, fetch failed) | Mark MCP **down for session**; mount + LE; **do not** retry that MCP call |
| Mount + MCP both bad; tunnel UP | LE `-p PROJECT` |
| Tunnel DOWN | Stop LE; tell user `connect.bat` / `connect.sh` |

## Examples

**Read README (healthy mount):**

```text
✅ Read  /home/$USER/mounts/refactoreoldclub/README.md
❌ laptop-exec read -p refactoreoldclub README.md   # only if mount failed
❌ first CallDynamicTool user-windows-mcp FileSystem mode=read
```

**Read README (mount just returned EPERM):**

```text
✅ same turn → FileSystem mode=read with absolute D:\...\README.md
✅ or laptop-exec read -p refactoreoldclub README.md
```

**Write a file (MCP up):**

```text
✅ user-windows-mcp FileSystem mode=write  path=<abs Windows>
✅ if MCP down → Cursor Write on /mounts/... then LE write
```

**Content search for `Foo`:**

```text
✅ Cursor Grep on mount  (FileSystem search ≠ content)
✅ fallback Select-String → laptop-exec rg -p ID 'Foo|foo' src/
❌ laptop-exec rg --glob '*.cs' Foo
❌ laptop-exec rg -A 3 Foo
```

## Checklist (every I/O)

1. Pick **1st** from the table for this action.
2. On error / unavailable → **2nd** in the **same turn**.
3. Still failing + tunnel UP → **3rd** (LE).
4. git? Always LE. Always `-p PROJECT`.

## Paths

| Path | Form |
|------|------|
| mount | `/home/$USER/mounts/PROJECT/REL` |
| MCP | Absolute Windows: `LAPTOP_REMOTE_PATH` / mounts.d `rpath` + REL (not Desktop-relative) |
| LE | `-p PROJECT` + repo-relative REL (never `/home/.../mounts/...`) |

```bash
laptop-exec status
laptop-exec read  -p PROJECT REL          # ONE file; no --offset/--limit
laptop-exec rg    -p PROJECT 'pattern' [pathspec...]   # no ripgrep flags
laptop-exec write -p PROJECT REL <<'EOF'
...
EOF
laptop-exec git   -p PROJECT -- status
laptop-exec run   -p PROJECT -- command...
```

`rg` is **not** ripgrep: reject `-i/-l/-n/-A/-B/-C/-m/-g/--glob/--type/--max-count`
(and invents like `--pathspec`). Use pathspecs + regex `|[]()+?`.

`read` is **not** Cursor Read: one relative file only — no `--offset/--limit`,
no multi-file, no positional line numbers.

## HARD STOP

1. Mount Read/Grep/Write/Glob are **ALLOWED** by hooks — use them for Read/Grep when healthy.
2. Healthy mount ⇒ **do not** `laptop-exec read` / `laptop-exec rg`.
3. Denied tool → never retry; follow `NEXT:` (usually next chain hop).
4. MCP FileSystem `mode=search` ≠ content Grep.
5. `user-filesystem` ≠ `windows-mcp`. FileSystem uses `mode=` not `action=`.
6. Task children need an explicit paste (below).

## Multi-agent paste

```
PRIORITY+FAILOVER: 1st path then 2nd/3rd same turn if down. Healthy mount: NEVER laptop-exec read/rg — Cursor Read/Grep on /mounts. READ/GREP=mount→MCP→LE. WRITE=MCP→mount→LE. Glob=MCP→mount. git=LE -p PROJECT. One MCP hard fail=>MCP down; continue mount+LE. Abs Windows for MCP. No rg -i/-l/-n/-A/-B/-C/-m/-g/--glob/--type/--max-count. LE read=one file (no --offset/--limit). user-filesystem≠windows-mcp. mode= not action=. Parallel: mount Read ~16-32; MCP ~8-12; LE ≤4.
```

## Anti-patterns

| Don’t | Do |
|-------|-----|
| `laptop-exec read/rg` while mount is fine | Cursor Read/Grep on `/mounts/` |
| MCP FileSystem read first while mount is fine | mount Cursor Read |
| Give up after one mount EPERM | failover MCP → LE |
| Retry MCP after ECONNREFUSED | MCP down; mount + LE |
| FileSystem search for content | Cursor Grep / Select-String |
| `laptop-exec rg -i` / `--glob` / `-A` / `--type` | pathspecs; regex alternation; or Cursor Grep |
| `laptop-exec read` with `--offset` / multi-file / `file 1 120` | Cursor Read on mount |
| Omit `-p` | always `-p PROJECT` |
| Desktop-relative MCP paths | absolute under project root |

Windows-MCP install, ports, auth → [reference-windows-mcp.md](reference-windows-mcp.md)
