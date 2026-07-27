---
name: laptop-exec
description: >-
  Routes file I/O between SSHFS mounts, windows-mcp, and laptop-exec with
  priority chains and failover. Use when reading/writing under ~/mounts/,
  calling user-windows-mcp FileSystem/PowerShell, running laptop-exec, git on
  the laptop, Select-String, Glob on Remote SSH, or recovering from mount
  EPERM/STALE or MCP ECONNREFUSED. Prefer mount for Read/Grep, MCP for
  Write/Glob; if the preferred path fails, use the next in the same turn.
---

# Laptop Exec — priority + failover

Three paths to the laptop disk. **Prefer the fastest healthy path; if it fails,
use the next immediately — never stuck.**

| Shortcut | Meaning |
|----------|---------|
| **mount** | Cursor Read/Grep/Write/Glob on `/home/$USER/mounts/PROJECT/` |
| **MCP** | `user-windows-mcp` / `windows-mcp` FileSystem + PowerShell (abs Windows paths) |
| **LE** | `laptop-exec -p PROJECT …` over the reverse tunnel |

Ops / install / ports → [reference-windows-mcp.md](reference-windows-mcp.md)

## When to use

- Any read/write/search under `~/mounts/<project>/`
- Choosing between Cursor tools vs `user-windows-mcp` FileSystem
- `laptop-exec` read/write/rg/git/run
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

## Failover / circuit breaker

| Symptom | Next path |
|---------|-----------|
| Mount EPERM / STALE / EIO / not mounted | MCP (abs path) → LE |
| MCP not listed / one hard fail (`ECONNREFUSED`, fetch failed) | Mark MCP **down for session**; mount + LE; **do not** retry that MCP call |
| Mount + MCP both bad; tunnel UP | LE `-p PROJECT` |
| Tunnel DOWN | Stop LE; tell user `connect.bat` / `connect.sh` |

Pattern matches industry fallback chains: ordered degrade, trip on hard fail, keep serving.

## Examples

**Read README (healthy mount):**

```text
✅ Read  /home/$USER/mounts/refactoreoldclub/README.md
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

**Find `*.csproj`:**

```text
✅ FileSystem mode=search|list  (or Cursor Glob)
```

**Content search for `Foo`:**

```text
✅ Cursor Grep on mount  (FileSystem search ≠ content)
✅ fallback Select-String → laptop-exec rg -p ID 'Foo|foo'
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
laptop-exec read  -p PROJECT REL
laptop-exec rg    -p PROJECT 'pattern' [pathspec...]   # no -i/-l/-n/--glob
laptop-exec write -p PROJECT REL <<'EOF'
...
EOF
laptop-exec git   -p PROJECT -- status
laptop-exec run   -p PROJECT -- command...
```

`rg` is **not** ripgrep: `-i`/`-l`/`-n`/`--glob` rejected.

## HARD STOP

1. Mount Read/Grep/Write/Glob are **ALLOWED** by hooks — use them for Read/Grep when healthy.
2. Denied tool → never retry; follow `NEXT:` (usually next chain hop).
3. MCP FileSystem `mode=search` ≠ content Grep.
4. `user-filesystem` ≠ `windows-mcp`. FileSystem uses `mode=` not `action=`.
5. Task children need an explicit paste (below).

## Multi-agent paste

```
PRIORITY+FAILOVER: 1st path then 2nd/3rd same turn if down. READ/GREP=mount→MCP→LE. WRITE=MCP→mount→LE. Glob=MCP→mount. git=LE -p PROJECT. One MCP hard fail=>MCP down; continue mount+LE. Abs Windows for MCP. No rg -i/-l/-n/--glob. user-filesystem≠windows-mcp. mode= not action=. Parallel: mount Read ~16-32; MCP ~8-12; LE ≤4.
```

## Anti-patterns

| Don’t | Do |
|-------|-----|
| MCP FileSystem read first while mount is fine | mount Cursor Read |
| Give up after one mount EPERM | failover MCP → LE |
| Retry MCP after ECONNREFUSED | MCP down; mount + LE |
| FileSystem search for content | Cursor Grep / Select-String |
| `laptop-exec rg -i` / `--glob` | alternation in pattern; pathspecs |
| Omit `-p` | always `-p PROJECT` |
| Desktop-relative MCP paths | absolute under project root |

Windows-MCP install, ports, auth → [reference-windows-mcp.md](reference-windows-mcp.md)
