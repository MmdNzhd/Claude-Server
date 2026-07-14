---
name: laptop-exec
description: >-
  Use laptop-exec for scan, git, build, and bulk I/O on SSHFS-mounted projects.
  Use when grep/find/git/dotnet/npm over ~/mounts/ is slow or when the user
  asks to build, test, or run git on their laptop.
---

# Laptop Exec — Fast Path for SSHFS Projects

Developers connect via `connect.bat` / `connect.sh`. Their code lives on the
laptop but appears on the server at `~/mounts/<project>/` over SSHFS.

**Benchmarked rule:** SSHFS is fine for reading/editing single files. For
everything else, use `laptop-exec` to run on the laptop directly.

## When to Use What

| Task | Tool | Why |
|------|------|-----|
| Read/edit one file | SSHFS `~/mounts/...` | Simple, works with editor |
| `grep` / `rg` / `find` across project | `laptop-exec rg` or `laptop-exec run` | 3–20× faster (findstr on Windows) |
| Read file from laptop | `laptop-exec read <file>` | works with `/` paths |
| `git status` / `diff` / `commit` / `push` | `laptop-exec git` | Mirror still hits SSHFS worktree |
| `dotnet build` / `npm test` / run app | `laptop-exec run` | SSHFS build often hangs |
| `git log` (history only) | Server mirror OK | `GIT_DIR=~/.git-repos/*.git` |

## Prerequisites

1. User has `connect.bat` / `connect.sh` running (tunnel alive).
2. Check: `laptop-exec status` → `tunnel: UP`.
3. Default project = `ACTIVE_MOUNT` from current session. Override with `-p`.

## Commands

```bash
# Session check
laptop-exec status
laptop-exec test                 # self-test (7 checks)

# Read file from laptop
laptop-exec read CLAUDE.md
laptop-exec read scripts/server/laptop-exec.sh

# Laptop path for active project
laptop-exec path
laptop-exec path -p claude-code-server

# Git on laptop (preferred over git on ~/mounts)
laptop-exec git -- status
laptop-exec git -- diff --stat
laptop-exec git -- log -10 --oneline
laptop-exec git -p review -- status

# Search on laptop
laptop-exec rg claude-mount
laptop-exec rg "function Foo" --glob "*.cs"

# Arbitrary command in project dir on laptop
laptop-exec run -- dotnet build
laptop-exec run -- npm test
laptop-exec run -p review -- dotnet build path/to/project.csproj
```

## Agent Workflow

1. **Before** a heavy operation on `~/mounts/`, run `laptop-exec status`.
2. If tunnel is UP → use `laptop-exec` for scan/git/build.
3. If tunnel is DOWN → tell user to run `connect.bat`/`connect.sh`; fall back
   to SSHFS only for single-file read/edit.
4. **Never** `dotnet build` or `npm install` directly on `~/mounts/` paths.
5. After editing files via SSHFS, run `laptop-exec git -- status` to verify.

## Edit vs Execute Split

```
Edit code     →  Read/Write ~/mounts/<project>/   (SSHFS)
Verify/scan   →  laptop-exec rg / git / run       (laptop SSH)
Build/test    →  laptop-exec run -- <build-cmd>  (laptop SSH)
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `no connect session` | User must run connect launcher |
| `tunnel: DOWN` | Reconnect; check laptop OpenSSH |
| `unknown project` | `claude-mount list` or use `-p` with mount id |
| Windows path issues | `laptop-exec path` shows correct `D:/...` path |
