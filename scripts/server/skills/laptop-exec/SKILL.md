---
name: laptop-exec
description: >-
  Hybrid laptop routing (measured 2026-07-26). READ/GREP: mount first (~16-32
  parallel), then windows-mcp, then laptop-exec. WRITE/EDIT: MCP FileSystem
  first (~8-10), then mount (~10), then LE. Glob: MCP search/list. git: LE only.
  Max parallel per path; LE ≤4 (cap 8). Mac/MCP-down/tunnel: mount+LE. Never
  remove laptop-exec — required for Mac/git/rg-fallback.
---

# Laptop Exec (hybrid routing)

`~/mounts/` may be STALE for **git** truth; mount Cursor tools are **ALLOWED**.
Measured SoT (idle + load + multi-round on Windows hybrid): mount scales best
for Read/Grep; MCP is fastest for Write and best for Glob/UI; LE is SoT for git
and slow fallback.

**Mac / MCP down → mount for FS + laptop-exec** (git always LE). Never uninstall.

## Priority by action (source of truth — measured 2026-07-26)

| Action | 1st | 2nd | 3rd | Parallel (same turn) |
|--------|-----|-----|-----|----------------------|
| **Read** | Cursor Read on `/mounts/` | windows-mcp `FileSystem` (abs Windows) | `laptop-exec read` | mount **~16–32**; MCP **~8–12**; LE **≤4** |
| **Grep (content)** | Cursor Grep on `/mounts/` | MCP PowerShell `Select-String` | `laptop-exec rg` | mount **~16–32**; Select-String **~4–8**; LE **≤4** |
| **Glob / filename** | windows-mcp `FileSystem` search/list | Cursor Glob / mount `ls` | `laptop-exec run` | MCP **~8–12**; mount **~16** |
| **Write/Edit/StrReplace/Delete** | windows-mcp `FileSystem` write | Cursor Write/Edit on `/mounts/` | `laptop-exec write` | MCP **~8–10**; mount **~10**; LE **≤4** |
| **git** | `laptop-exec git` only | — | — | LE **≤4** |
| **Shell build/test** | windows-mcp `PowerShell` | `laptop-exec run` | mount Shell OK | MCP free; LE **≤4** |
| **UI / Screenshot** | windows-mcp only | — | — | MCP free |

**Notes:**
- MCP `FileSystem` search ≠ content Grep. Content via MCP = **Select-String**.
- MCP relative paths resolve to **Desktop** — always absolute under project root.
- MCP Read saturates ~27–28 rps under fan-out; more than ~12 parallel mostly adds latency.
- Mount Read scales past ×64 in benches; prefer **~16–32** independent reads/turn.
- Evidence (approx): cold Read mount≪MCP≪LE; Write MCP≪mount≪LE; load mount wins Read 20/20 paired.

## Parallel (mandatory — maximize wall-clock)

Independent ops in the **same turn** (never drip one-by-one):

| Path | Target fan-out | Cap / notes |
|------|----------------|-------------|
| Mount Read/Grep/Glob | **~16–32** | No mux limit; SSHFS OK under parallel in measured sessions |
| MCP FileSystem read/search | **~8–12** | Beyond ~12, latency rises (throughput plateaus ~28 rps) |
| MCP FileSystem write | **~8–10** | Fastest write path when listed |
| MCP Select-String | **~4–8** | Heavier than FileSystem read |
| MCP PowerShell build/test | as needed | No mux limit |
| laptop-exec any | **≤4** prefer | Hard cap **8** mux slots; never storm |

## HARD STOP

1. Hooks **ALLOW** Read/Grep/Glob/Write/Edit/StrReplace/Delete/EditNotebook/Shell on `/mounts/`.
2. If a tool is denied, **never retry** it — run the `NEXT:` hint in the same turn.
3. Prefer table above when Windows + tools listed; else mount then `laptop-exec -p PROJECT`.

## FAIL-FAST (windows-mcp)

**MCP ready** = tools listed (`windows-mcp` / `user-windows-mcp` with `FileSystem`/`PowerShell`).

**After ONE failure** (`ECONNREFUSED`, fetch failed, not connected):

- Mark MCP **down for this session**.
- Use **mount + laptop-exec** (git still LE).
- **Do not** retry the failed MCP call.
- Tell user once: reconnect / start laptop windows-mcp / Reload Window.

`user-filesystem` ≠ windows-mcp. FileSystem args use `mode=` (not `action=`).

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

`PROJECT` = folder under `~/mounts/PROJECT/`. Always `-p`.

## Paths

- Mount / Cursor: `/home/$USER/mounts/PROJECT/REL`
- windows-mcp: **absolute Windows** under project root (`LAPTOP_REMOTE_PATH` / `laptop-exec path -p ID` / mounts.d `rpath|REMOTE_PATH` + REL)
- laptop-exec: **repo-relative** + `-p PROJECT` (never `/home/.../mounts/...`)

## rg contract

Not ripgrep. `-i`/`-l`/`-n`/`--glob`/`-g` are **rejected**.

```bash
# wrong:  laptop-exec rg -p ID -i foo --glob '*.ts'
# right:  laptop-exec rg -p ID 'foo|Foo' src/
```

Exit `1` = no matches. Timeout **90s**. `write` = full file replace.

## Multi-agent (non-negotiable)

Task spawn is allowed. **Children do not inherit this skill.** Paste into every Task `prompt`:

```
PRIORITY (2026-07-26): READ/GREP=mount first (~16-32 parallel) then MCP (FileSystem / Select-String ~8-12 / ~4-8) then LE ≤4. WRITE/EDIT=MCP FileSystem first (~8-10) then mount (~10) then LE ≤4. Glob=MCP search/list ~8-12 then mount. git=LE only ≤4. UI=MCP only. FAIL-FAST: one MCP error=>MCP down; mount+LE; never retry same MCP call. MCP paths=absolute Windows (not Desktop-relative). LE=-p PROJECT + repo-relative. No rg -i/-l/-n/--glob. user-filesystem≠windows-mcp. FileSystem mode= not action=.
```

## Rationalizations (all false)

| Excuse | Reality |
|--------|---------|
| "SSH-first means always laptop-exec first" | False — table above; LE last for FS |
| "Read must be MCP-first" | False — mount wins Read/Grep under load |
| "Write must be mount-first" | False — MCP write measured faster |
| "Grep/Glob are denied on mounts" | False — hooks ALLOW |
| "MCP FileSystem search = content Grep" | False — Select-String or mount Grep |
| "One MCP call per turn is safer" | False — fan out to caps above |
| "Child inherits session hooks" | Often weak; paste the block |
| "rg -i is fine" | Rejected / historically hung slots |
| "active_mount is already right" | Often wrong — always `-p` |
| "windows-mcp replaces laptop-exec" | False — Mac/git/LE fallback still needed |
| "Retry MCP until it works" | Forbidden — one fail → MCP down for session |
| "user-filesystem is windows-mcp" | False |

## Red flags → stop

Defaulting to LE for ordinary Read/Write · Serial mount/MCP when independent · Retry after deny · Retry MCP after ECONNREFUSED · `rg -i/--glob` · Task without paste block · omit `-p` · Desktop-relative MCP paths · ask for SSHFS/sudo password → `sudo-from-laptop`

Detail: `laptop-exec --help`. Do not paste CLAUDE.md encyclopedia into prompts.
