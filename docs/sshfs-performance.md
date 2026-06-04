# SSHFS Performance: Problems, Attempts, and Final Solution

## The Setup

- Windows laptops hold project files
- Ubuntu 24 server runs Claude Code
- Files accessed via SSHFS over VPN (SSH reverse tunnel)
- 628 tracked files in the test project (SqlSimulator)

---

## Problem 1: `git status` — 7 Minutes

### Root Cause

`git status` must `stat()` every tracked file to check for modifications.
Each `stat()` = one SFTP request over SSH over VPN.

```
628 files × ~670ms per SSHFS stat = ~7 minutes
user time: 0.048s  ← pure I/O, zero CPU work
```

### Attempts That Failed

| Approach | Why it failed |
|----------|--------------|
| Local `.git` via `git init --separate-git-dir` | Git still stats all working-tree files over SSHFS |
| `core.checkStat = minimal` | Only reduces what's compared, not the number of stat calls |
| `attr_timeout=30` SSHFS cache | Cache expires after 30s; git re-fetches all stats on next run |
| `rsync` Windows → server local disk | rsync itself reads file list from SSHFS — same latency, ~4 min initial |
| FSMonitor | SSHFS doesn't support inotify; no file-change events available |
| `git update-index --assume-unchanged` | Requires manually marking every file; breaks normal workflow |

### Solution: Hide `.git` Before Mount

On mount, SSH to Windows and rename `.git` → `.git.server-session`.
Server sees no `.git` → git commands fail immediately → zero SSHFS stat calls.
On unmount, rename back. Self-healing via `recover` command on reconnect.

```
Before: git status → 7 minutes (628 × stat over SSHFS)
After:  git status → fatal: not a git repository → 0.004s
```

**Speedup: 105,000×**

---

## Problem 2: `claude` Startup — 18 Seconds

### Root Cause

Claude Code reads project config on every startup:

```
.claude/settings.json       → SFTP lstat → ~3s
.claude/settings.local.json → SFTP lstat → ~3s
.mcp.json                   → SFTP lstat → ~3s
.claude/rules/              → SFTP lstat → ~3s
.claude/commands/           → SFTP lstat → ~3s
```

None of these files existed on Windows, so each triggered a separate SFTP
round-trip to confirm non-existence. Five lookups × 3s each = 15s overhead.

Measured with `strace -e trace=openat,stat`:
```
645333 openat(".claude/settings.json", O_RDONLY|O_PATH <unfinished ...>
645333 openat(".mcp.json", O_RDONLY|O_NOCTTY <unfinished ...>
```
All calls show `<unfinished ...>` — blocking on SSHFS network I/O.

Baseline (from `~/work`, local disk): **3.8s**
From SSHFS mount: **18.1s** — 14s pure SSHFS overhead

### Solution: Create Stubs + Warm dcache

On mount, create empty stub directories on Windows:
```
.claude/rules/     ← empty dir
.claude/commands/  ← empty dir
.mcp.json          ← contains {}
```

Then pre-warm SSHFS directory cache in background:
```bash
ls .claude/           # populates dcache
ls .claude/rules/
ls .claude/commands/
```

With `dcache_timeout=60`, all subsequent lookups within these directories
are answered from cache — no SFTP round-trips.

```
Before: claude startup → 18s (5 × SFTP lstat)
After:  claude startup → 4s  (all served from dcache)
```

**Speedup: 4.5×**

---

## Combined Result

| Operation | Before | After |
|-----------|--------|-------|
| `git status` | 7 min 0 sec | **0.004s** |
| `claude --print "hi"` | 18s | **4s** |

---

## Architecture

```
connect.bat (Windows)
  │
  ├── SSH tunnel: server port → Windows:22
  ├── claude-mount recover          ← restore any crashed .git
  └── claude-mount up <project>
        │
        ├── SSH to Windows (1 call):
        │     rename .git → .git.server-session  (hide)
        │     mkdir .claude/rules .claude/commands
        │     create .mcp.json if missing/empty
        │
        ├── sshfs mount
        │
        └── background: ls .claude/ → warm dcache

VSCode opens → claude runs → instant git + fast startup

Disconnect / crash:
  claude-mount down  →  restore .git on Windows
  watchdog           →  detects hung mount, recover + remount
  automount (.bashrc)→  recover on every login
  connect.bat        →  recover before every mount
```

## Key Files

| File | Role |
|------|------|
| `scripts/server/claude-mount.sh` | Core logic: hide/restore/stubs/cache-warm |
| `scripts/server/claude-automount.sh` | Auto-mount + recover on `.bashrc` login |
| `scripts/server/claude-watchdog.sh` | Background monitor: hung mount → recover + remount |
| `scripts/client/windows/connect.ps1` | Client: recover before mount |

## Edge Cases Handled

- Mount fails after hide → immediate restore
- Crash/abnormal disconnect → `recover` on next connect restores `.git`
- "already mounted" path → stubs + cache still warmed (dcache expires between sessions)
- `claude-mount rm` → restore before deleting config (rpath would be lost)
- `claude-mount edit` with new rpath → restore old path first
- Malformed config (empty lpath) → guarded with `[ -n "$lpath" ]` before `mountpoint -q`
- Empty `.mcp.json` → overwritten with `{}` (not just existence check)
- Single quotes in path → escaped for PowerShell single-quoted strings
- Non-git directories (e.g. utility script folders) → stubs skipped (no `.git` = no stubs)
- `sshfs` exit 124 with a real error message → specific error shown, not generic timeout
