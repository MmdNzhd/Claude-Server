---
name: laptop-exec
description: >-
  MANDATORY SSH-first for ~/mounts/ projects. When tunnel UP use laptop-exec for
  ALL read/write/search/git/build — works without SSHFS mount. Run laptop-exec
  status and health first. Use -p or resolve when cwd/active_mount differ.
---

# Laptop Exec — SSH-First (complete)

Code lives on the **laptop**. SSHFS at `~/mounts/<id>/` is optional and often
**slow, stale, or disconnected**. The reverse **tunnel** (connect.bat/sh) is enough.

## Mandatory first steps

```bash
laptop-exec status          # tunnel UP?
laptop-exec health          # all projects + sshfs state
laptop-exec resolve         # project id from cwd (under ~/mounts/ID/)
laptop-exec mount-status -p ID   # when workspace != active_mount
```

## Decision table

| Condition | Agent action |
|-----------|----------------|
| `tunnel: UP` | **All** file ops via laptop-exec — never Read/Write/Grep on `/mounts/` |
| `sshfs: STALE` or `NOT_MOUNTED` | laptop-exec only — do not try SSHFS |
| `tunnel: DOWN` | Tell user: run connect.bat/sh |
| cwd under `~/mounts/foo/` | auto project `foo` (or `laptop-exec resolve`) |
| Agent cwd not under mounts | `-w ~/mounts/PROJECT/...` or `-p PROJECT` |
| cwd project != `active_mount` | always `-p` or `-w` |

## Command reference

```bash
# Discovery
laptop-exec list
laptop-exec resolve /home/user/mounts/myapp/src/foo.cs
laptop-exec path -p myapp

# Files
laptop-exec read [-p P] path/to/file
laptop-exec write [-p P] path/to/file <<'EOF'
content here
EOF

# Dev
laptop-exec rg [-p P] Pattern   # git grep on repos (accurate); multiplex SSH (fast)
laptop-exec git [-p P] -- status
laptop-exec git [-p P] -- diff --stat
laptop-exec run [-p P] -- dotnet build
laptop-exec run [-p P] -- npm test

# Verify
laptop-exec test
```

## Agent workflow (every task)

1. `laptop-exec status` — abort with "run connect.bat" if tunnel DOWN.
2. `laptop-exec resolve` or `-p` from workspace path.
3. Read → `laptop-exec read`; edit → `laptop-exec write`; search → `laptop-exec rg`.
4. Never `Grep`, `Glob`, `Read`, `Write` tools on paths containing `/mounts/`.
5. Never `git`, `find`, `dotnet build` in shell on `/mounts/` paths.
6. After writes → `laptop-exec git -- status`.

## Examples

```bash
# Working in claude-code-server while active_mount is another project:
laptop-exec read -p claude-code-server scripts/server/laptop-exec.sh
laptop-exec rg -p claude-code-server "mount-status"

# Mount disconnected — still works:
laptop-exec mount-status -p claude-code-server
# sshfs: NOT_MOUNTED, tunnel: UP -> laptop-exec ONLY
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Hook blocked Read/Write | Expected — use laptop-exec read/write |
| `no connect session` | connect.bat/sh on laptop |
| `unknown project` | `laptop-exec list` |
| Wrong project | `-p ID` or `cd ~/mounts/ID` first |
