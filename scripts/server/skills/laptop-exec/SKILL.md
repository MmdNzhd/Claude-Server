---
name: laptop-exec
description: >-
  Use for ~/mounts/ work and laptop routing. On Windows when windows-mcp /
  user-windows-mcp is ready: DEFAULT to MCP FileSystem/PowerShell/UI first;
  laptop-exec is fallback (and always for git + content rg). Also use when
  Cursor Read/Grep/Glob/Write/Edit deny, MCP down, tunnel DOWN, Mac laptop,
  session slots full, rg flag rejected, active_mount mismatch, or Task prompts
  for mounts work. Never remove laptop-exec — required for Mac/git/rg/fallback.
---

# Laptop Exec (Windows-MCP first; LE fallback)

`~/mounts/` may be stale SSHFS. **Laptop disk is truth** — reach it via
**windows-mcp first** (when ready), else **`laptop-exec`**.
**Mac / MCP down → laptop-exec only.** Never uninstall `laptop-exec`.

## Priority (read this first)

```
1. Windows + MCP ready  →  windows-mcp for FileSystem / PowerShell / UI
2. Else                 →  laptop-exec (-p PROJECT every call)
3. Always               →  laptop-exec for git + content rg (even when MCP ready)
```

Do **not** open with `laptop-exec read/run/write` when MCP is ready for that step.

## Parallel MCP (mandatory)

When MCP is ready and ops are **independent**:

- Fan out **~8 parallel** `windows-mcp` `FileSystem` / `PowerShell` calls **in the same turn**.
- **Never** drip independent MCP requests one-by-one across turns.
- Sequence only when step N needs output from step N-1.
- MCP has no SSH mux limit; the ≤4 / hard-cap-8 limit applies to **`laptop-exec` only**.

## HARD STOP

1. Read/Grep/Glob/Write/Edit/StrReplace on `/mounts/` → deny is **expected**.
2. **Never retry** the denied tool. Run the `NEXT:` command in the same turn.
3. First allowed I/O for that need:
   - **Windows + MCP ready:** windows-mcp (`FileSystem` / `PowerShell` / UI)
   - **Otherwise:** Shell + `laptop-exec` with **`-p PROJECT` every call**

```bash
laptop-exec status    # must be UP for LE path; else user connect.bat/sh — stop
laptop-exec read  -p PROJECT REL
laptop-exec rg    -p PROJECT 'pattern' [pathspec...]
laptop-exec write -p PROJECT REL <<'EOF'
...
EOF
laptop-exec git   -p PROJECT -- status
laptop-exec run   -p PROJECT -- command...
```

`PROJECT` = folder under `~/mounts/PROJECT/`. Always `-p` (active_mount often wrong).

## Hybrid routing (Windows)

`windows-mcp` / `user-windows-mcp` **ready** = default path for FS/shell/UI.
`laptop-exec` stays forever for **git**, **content rg**, **Mac**, and **MCP-down fallback**.

### When MCP counts as ready

1. `laptop-exec status` → `tunnel: UP` and `laptop_os: windows` (or Windows paths).
2. MCP server connected (tools like `FileSystem`, `PowerShell`, `Screenshot` listed).
3. Prefer MCP process in **interactive session** (SessionId > 0). If Screenshot/UI
   fails with session/desktop errors → fall back to laptop-exec for non-UI work;
   tell user to run `windows-mcp install` (or `~\.windows-mcp\start-server.cmd`).

If any check fails → **laptop-exec only**. Never invent raw SSH.

### Routing table

| Need | First choice | Fallback / always |
|------|--------------|-------------------|
| File read/write/list/info | **windows-mcp `FileSystem`** | `laptop-exec read/write` |
| Shell / build / tests | **windows-mcp `PowerShell`** | `laptop-exec run` |
| Screenshot / Click / Type / Snapshot / UI | **windows-mcp only** | (no LE equivalent) |
| Clipboard / Process / Notification / Registry | **windows-mcp** | `laptop-exec run` where sensible |
| `git` | — | **`laptop-exec git` only** |
| Content search (`rg`) | — | **`laptop-exec rg` only** (MCP search ≠ content grep) |
| Mac laptop | — | **`laptop-exec` only** |
| MCP down / auth / forward broken | — | **`laptop-exec` only** |

### Paths

- `laptop-exec`: **repo-relative** + `-p PROJECT` (never `/home/.../mounts/...`).
- windows-mcp `FileSystem`: **absolute Windows path** under the project root
  (from connect/`LAPTOP_PATH` + REL, e.g. `D:\Smart\Dakhl\docs\foo.md`).
  Relative MCP paths resolve from Desktop — avoid for repo work.

### Ops (server ↔ laptop)

- Forward: `windows-mcp-forward` → `http://127.0.0.1:PORT/mcp` (PORT is per-UID,
  default `28000+(UID-1000)` — see `~/.config/windows-mcp/env`
  `WINDOWS_MCP_FORWARD_PORT`). Bearer from that env / laptop
  `~/.windows-mcp/config.toml` auth_key.
- Cursor: `~/.cursor/mcp.json` entry `windows-mcp`. Reload Window after auth change.
- Detail: `reference-windows-mcp.md` next to this skill.

## rg contract

Not ripgrep. `-i`/`-l`/`-n`/`--glob`/`-g` are **rejected** (old hangs pinned all 8 slots for hours).

```bash
# wrong:  laptop-exec rg -p ID -i foo --glob '*.ts'
# right:  laptop-exec rg -p ID 'foo|Foo' src/
# right:  laptop-exec rg -p ID 'pattern' '*.ts'
```

Exit `1` = no matches. Timeout **90s**. Dash-leading patterns: `rg -- -foo path`. Narrow pathspecs.

Default timeouts (override `LAPTOP_EXEC_*_TIMEOUT=0` to disable): rg 90s, run 600s, git 300s, scp 120s.

`write` = **full file replace** (not patch). Read → edit in `/tmp` → write.

## Multi-agent (non-negotiable)

Task spawn is allowed. **Children do not inherit this skill.** If the Task `prompt` omits the block below, the child will Read/Grep mounts, burn denies, and/or pin mux slots.

**Paste verbatim into every Task `prompt` (replace PROJECT):**

```
Windows-MCP first (when ready); laptop-exec fallback.
On Windows+MCP ready: use windows-mcp FileSystem/PowerShell/UI by default.
ALWAYS laptop-exec for git + content rg; Mac; or when MCP is down.
laptop-exec status first when using LE. Use -p PROJECT on every laptop-exec call.
Paths: MCP = absolute Windows under project root; LE = repo-relative (never /home/.../mounts/...).
Never Read/Grep/Glob/Write/Edit/Shell-heavy on /mounts/.
Never laptop-exec rg -i/-l/-n/--glob.
On deny: run NEXT: immediately — do not retry the denied tool.
MCP: ~8 parallel FileSystem/PowerShell in ONE turn (never one-by-one for independent ops). laptop-exec: prefer ≤4 parallel (hard cap 8 SSH slots).
Never remove laptop-exec.
```

Prefer ≤4 parallel Tasks that touch the laptop via SSH. One hung `run` blocks everyone. No raw `ssh`/`scp`.

## Rationalizations (all false)

| Excuse | Reality |
|--------|---------|
| "SSH-first means always laptop-exec first" | False — on Windows+MCP, MCP is first for FS/shell/UI |
| "I'll laptop-exec read even though MCP is ready" | Forbidden for that step; use MCP FileSystem |
| "One MCP call per turn is safer" | False — independent MCP calls must be parallel in one turn |
| "Child will see session hooks" | Often weak; paste the block anyway |
| "Just one quick Read on mounts" | Deny + wasted turn; use MCP or `laptop-exec read` |
| "rg -i is fine" | Rejected or historically hung for hours |
| "active_mount is already right" | Often wrong — always `-p` |
| "8 parallel LE explores are faster" | 8 slots → stall; use MCP parallelism for FS instead |
| "I'll retry the denied tool" | Forbidden; run `NEXT:` |
| "windows-mcp replaces laptop-exec" | False — Mac/git/rg need LE |
| "MCP FileSystem search = rg" | False — use `laptop-exec rg` for content search |

## Red flags → stop

Defaulting to LE while MCP ready · Serializing independent MCP calls · Retry after deny · `rg -i/--glob/-l` · Task without paste block · omit `-p` · `cd mounts && git` · long unbounded `run` · ask for SSHFS/sudo password → `sudo-from-laptop` · delete/disable laptop-exec because MCP exists

Detail: `laptop-exec --help`. Do not paste CLAUDE.md SSH encyclopedia into prompts.
