---
name: laptop-exec
description: >-
  Use when any file, search, edit, build, test, or git work targets ~/mounts/,
  after Cursor Read/Grep/Glob/Write/Edit deny, SSH-first BLOCKED, NEXT:
  laptop-exec, session slots full, rg flag not supported, tunnel DOWN,
  active_mount mismatch, spawning Task/subagent on mounts, multi-agent mux
  contention, or (Windows only) routing between laptop-exec and windows-mcp.
  Use before the first mounts tool call â€” not after deny. Never remove or
  skip laptop-exec on Mac or when windows-mcp is down.
---

# Laptop Exec (SSH-first)

`~/mounts/` may be stale SSHFS. **Laptop disk via `laptop-exec` is truth for code/git.**
On **Windows**, optional **windows-mcp** (Cursor MCP) can accelerate FS/UI â€” it **complements**
`laptop-exec`, never replaces it. **Mac / no MCP â†’ laptop-exec only.**

## HARD STOP

1. Read/Grep/Glob/Write/Edit/StrReplace on `/mounts/` â†’ deny is **expected**.
2. **Never retry** the denied tool. Run the `NEXT:` command in the same turn.
3. First I/O = Shell + `laptop-exec` with **`-p PROJECT` every call** (unless a
   windows-mcp tool is used for that step per the hybrid table below).

```bash
laptop-exec status    # must be UP; else user connect.bat/sh â€” stop
laptop-exec read  -p PROJECT REL
laptop-exec rg    -p PROJECT 'pattern' [pathspec...]
laptop-exec write -p PROJECT REL <<'EOF'
...
EOF
laptop-exec git   -p PROJECT -- status
laptop-exec run   -p PROJECT -- command...
```

`PROJECT` = folder under `~/mounts/PROJECT/`. Always `-p` (active_mount often wrong).

## Hybrid: windows-mcp (Windows only â€” keep laptop-exec)

Do **not** uninstall, disable, or stop using `laptop-exec`. Mac users and git/`rg`
depend on it. windows-mcp is an **optional accelerator** when Cursor MCP
`windows-mcp` / `user-windows-mcp` is **ready**.

### When available

1. `laptop-exec status` â†’ `tunnel: UP` and `laptop_os: windows` (or Windows paths).
2. MCP server `windows-mcp` connected (tools like `FileSystem`, `Screenshot` listed).
3. Prefer MCP process in **interactive session** (SessionId > 0). If Screenshot/UI
   fails with session/desktop errors â†’ fall back to laptop-exec; tell user to run
   `windows-mcp install` (or start `~\.windows-mcp\start-server.cmd`) on the laptop.

If any check fails â†’ **laptop-exec only**. Never invent raw SSH.

### Routing (prefer left when MCP ready)

| Need | Prefer | Fallback / always |
|------|--------|-------------------|
| `git` (status, diff, commit, â€¦) | â€” | **`laptop-exec git` only** |
| Content search (`rg`) | â€” | **`laptop-exec rg` only** (MCP search â‰  content grep) |
| Small/medium file read/write/list/info | windows-mcp `FileSystem` | `laptop-exec read/write` |
| Shell / build / tests | windows-mcp `PowerShell` (interactive) or `laptop-exec run` | `laptop-exec run` if MCP shell fails |
| Screenshot / Click / Type / Snapshot / UI | windows-mcp only | (no LE equivalent) |
| Clipboard / Process / Notification / Registry | windows-mcp | `laptop-exec run` where sensible |
| Mac laptop | â€” | **`laptop-exec` only** |
| MCP down / auth / forward broken | â€” | **`laptop-exec` only** |

### Paths

- `laptop-exec`: **repo-relative** + `-p PROJECT` (never `/home/.../mounts/...`).
- windows-mcp `FileSystem`: **absolute Windows path** under the project root
  (from connect/`LAPTOP_PATH` + REL, e.g. `D:\Smart\Claude-Code-Server\src\foo.ts`).
  Relative MCP paths resolve from Desktop â€” avoid for repo work.

### Ops (server â†” laptop)

- Forward: `windows-mcp-forward` â†’ `http://127.0.0.1:18000/mcp` (Bearer from
  `~/.config/windows-mcp/env` / laptop `~/.windows-mcp/config.toml` auth_key (optional auth.key mirror).
- Cursor: `~/.cursor/mcp.json` entry `windows-mcp`. Reload Window after auth change.
- Detail: `reference-windows-mcp.md` next to this skill (optional).

## rg contract

Not ripgrep. `-i`/`-l`/`-n`/`--glob`/`-g` are **rejected** (old hangs pinned all 8 slots for hours).

```bash
# wrong:  laptop-exec rg -p ID -i foo --glob '*.ts'
# right:  laptop-exec rg -p ID 'foo|Foo' src/
# right:  laptop-exec rg -p ID 'pattern' '*.ts'
```

Exit `1` = no matches. Timeout **90s**. Dash-leading patterns: `rg -- -foo path`. Narrow pathspecs.

Default timeouts (override `LAPTOP_EXEC_*_TIMEOUT=0` to disable): rg 90s, run 600s, git 300s, scp 120s.

`write` = **full file replace** (not patch). Read â†’ edit in `/tmp` â†’ write.

## Multi-agent (non-negotiable)

Task spawn is allowed. **Children do not inherit this skill.** If the Task `prompt` omits the block below, the child will Read/Grep mounts, burn denies, and/or pin mux slots.

**Paste verbatim into every Task `prompt` (replace PROJECT):**

```
SSH-first mandatory. laptop-exec status first.
Use -p PROJECT on every laptop-exec read/rg/git/run/write.
Paths repo-relative; never /home/.../mounts/...
Never Read/Grep/Glob/Write/Edit/Shell-heavy on /mounts/.
Never laptop-exec rg -i/-l/-n/--glob.
On deny: run NEXT: immediately â€” do not retry the denied tool.
Max 8 shared SSH slots; prefer â‰¤4 parallel laptop-exec; queue OK.
Windows hybrid: if windows-mcp MCP is ready, prefer it for FileSystem/UI/Screenshot/PowerShell;
ALWAYS keep laptop-exec for git, content rg, Mac, and when MCP is down. Never remove laptop-exec.
```

Prefer â‰¤4 parallel Tasks that touch the laptop. One hung `run` blocks everyone. No raw `ssh`/`scp`.

## Rationalizations (all false)

| Excuse | Reality |
|--------|---------|
| "Child will see session hooks" | Often weak; paste the block anyway |
| "Just one quick Read on mounts" | Deny + wasted turn; use `laptop-exec read` |
| "rg -i is fine" | Rejected or historically hung for hours |
| "active_mount is already right" | Often `review` while workspace differs â€” always `-p` |
| "8 parallel explores are faster" | 8 slots â†’ `session slots full` â†’ everyone stalls |
| "I'll retry the denied tool" | Forbidden; run `NEXT:` |
| "windows-mcp replaces laptop-exec" | False â€” Mac/git/rg need LE; hybrid only |
| "MCP FileSystem search = rg" | False â€” use `laptop-exec rg` for content search |

## Red flags â†’ stop

Retry after deny Â· `rg -i/--glob/-l` Â· Task without paste block Â· omit `-p` Â· `cd mounts && git` Â· long unbounded `run` Â· ask for SSHFS/sudo password â†’ `sudo-from-laptop` Â· delete/disable laptop-exec because MCP exists

Detail: `laptop-exec --help`. Do not paste CLAUDE.md SSH encyclopedia into prompts.
