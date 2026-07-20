---
name: laptop-exec
description: >-
  MANDATORY for ANY file/code work under ~/mounts/: never use Cursor Read/Grep/Write/
  Glob/Edit on mounts (hooks deny; retrying wastes turns). First tool MUST be Shell with
  laptop-exec read|rg|write|git|run. Use when opening, searching, editing, building, or
  git on a mounts workspace. Also: project -p resolve, flag order, Windows encoding.
---

# Laptop Exec — use this FIRST (not after deny)

## HARD STOP (read before any tool)

1. Cursor Read/Grep/Glob/Write/Edit on `/mounts/` → **hook deny (expected)**.
2. **Never retry** the blocked tool. Remap to laptop-exec in the same turn.
3. First I/O tool = Shell:

```bash
laptop-exec status
# both flag orders OK:
laptop-exec read -p PROJECT REL
laptop-exec -p PROJECT read REL
laptop-exec rg -p PROJECT PATTERN
laptop-exec write -p PROJECT REL <<'EOF'
...
EOF
laptop-exec git -p PROJECT -- status
```

PROJECT = folder name in `~/mounts/PROJECT/`. Prefer always `-p` (active_mount may be empty).

Deny messages include a copy-paste `NEXT:` command — run that, do not invent retries.

---

# Laptop Exec - deep operational guide

Source of truth: scripts/server/laptop-exec.sh + Cursor hook laptop-exec-guard.sh.

---

## A) Why agents fail (read before tools)

1. Default Cursor tools target the workspace root, often /home/$USER/mounts/<ID>/.
2. Hooks deny those tools on /mounts/ on purpose (SSH-first).
3. Retrying Read/Grep after deny is the wrong loop. Remap to laptop-exec immediately.
4. active_mount is the connect-selected project, not necessarily the open Cursor folder.
5. laptop-exec read paths are on the laptop, not Linux mount paths.

If you internalize only one workflow:

```bash
laptop-exec status
laptop-exec health
# if workspace folder != active_mount:
P=<workspace-folder-name>
laptop-exec read -p "$P" REL
laptop-exec rg   -p "$P" PATTERN
laptop-exec write -p "$P" REL <<'EOF'
...
EOF
laptop-exec git  -p "$P" -- status
```

---

## B) System model (deep)

```
[Cursor Agent on Linux server]
        |  hooks may DENY Read/Grep/Write/Shell-heavy on /mounts/
        v
[laptop-exec] --SSH ControlMaster--> 127.0.0.1:$TUNNEL_PORT
        |                                 |
        | scp/ssh                          v
        +--------------------------> [Laptop disk = source of truth]
                                              ^
[optional SSHFS] ~/mounts/ID/  ---------------+  (UI only; may be STALE)
```

| Layer | Path example | Agent should |
|-------|--------------|--------------|
| Laptop root | D:/Smart/Foo or /Users/.../Foo | I/O via laptop-exec |
| Server mount | /home/u/mounts/foo/... | Do not Read/Grep/Write |
| Server local | /tmp, ~/.cursor, /usr | Normal tools OK |

Session state:

| File | Keys |
|------|------|
| ~/.claude-connect.conf | LAPTOP_USER, TUNNEL_PORT, ACTIVE_MOUNT, GIT_MODE, LAPTOP_OS |
| ~/.claude-mounts.d/<ID>.conf | rpath/REMOTE_PATH (laptop), lpath/LOCAL_PATH (mount). Extra keys (MOUNT_ID/id/label) ignored by loader. |

SSH: key ~/.ssh/claude_laptop, BatchMode, ConnectTimeout=8, ControlMaster=auto, ControlPersist=300, ControlPath=~/.cache/laptop-exec/cm-%C.
Note: _laptop_ssh uses ssh -n (stdin discarded). Writes use scp, not ssh stdin.

---

## C) Hook policy (exact allow/deny) — matches live guard

User hooks only (`~/.cursor/hooks.json`). Project `hooks.json` must stay `{"version":1,"hooks":{}}`.

- `beforeShellExecution` → wrap → guard (all shells)
- `preToolUse` matcher (exact, **no Shell**):

```
Grep|Glob|Read|Write|Edit|EditNotebook|StrReplace|Delete|Task
```

### preToolUse

| Tool | Denied when | Allowed when |
|------|-------------|--------------|
| Read/Write/Edit/EditNotebook/StrReplace/Delete | path under /mounts/ (or no path + workspace/cwd under mounts) | /tmp, ~/.cursor/**, other non-mount paths |
| Grep/Glob | path/target under mounts, or no path + workspace mounts | path /tmp etc. |
| Task | **never** (spawn always `_allow`) | always — children still hit Read/Grep/Shell denies |

Shell is **not** in preToolUse; only `beforeShellExecution`.

### Heavy Shell (beforeShellExecution)

Heavy tools include: git find rg grep dotnet npm npx yarn pnpm bun deno cargo make cmake mvn gradle go build/test/run python -m pytest/unittest pytest jest vitest tsc webpack vite build cat sed awk head tail wc ls -R.

Not heavy: echo, ls (no -R), python3/node (unless pytest), `ls \| head` (pipeline filters stripped), heredocs whose body mentions git/cat.

Escape only when clearly aimed at `/tmp` or non-mount `/home/...` (e.g. `git -C /tmp`, `cat /tmp/x`). **Not** escapes: `git status && echo /tmp`, `… && ls /usr`.

Substring `laptop-exec` → not heavy. Deny messages include `NEXT:` — obey; do not retry.

---

## D) Project resolution (exact)

_resolve_project:

1. -p / --project ID
2. Else id from first mounts path among: -w/--workspace, $LAPTOP_EXEC_WORKSPACE, $CURSOR_WORKSPACE, $CURSOR_PROJECT_DIR, $PWD
   Regex: /mounts/([^/]+)
3. Else $ACTIVE_MOUNT
4. Else die: no project (...)
5. Load ~/.claude-mounts.d/$ID.conf or die unknown project

Cursor often does not set CURSOR_* envs. Prefer explicit -p from the workspace folder name.

```bash
laptop-exec resolve
laptop-exec resolve /home/$USER/mounts/foo/src/a.cs
laptop-exec resolve -w /home/$USER/mounts/foo
```

---

## E) Command reference (behavior-accurate)

### status / health / list

- status: prints fields; exit 1 if no LAPTOP_USER or tunnel DOWN.
- health: status (ignore fail) + projects: + fast list.
- list: default fast (sshfs=(list --full) placeholder). list --full: real sshfs state.
- sshfs probe cached ~45s (~/.cache/laptop-exec/sshfs-cache.tsv).
- Active project marked with " *" in list.

status fields: tunnel_port, laptop_user, laptop_os (windows|mac), active_mount, git_mode (hide|server|off), tunnel UP|DOWN, sshfs for active_mount only, prefer.

### mount-status / path / count

- mount-status [-p ID]: project, local_path, laptop_path, sshfs, tunnel, recommend.
- path [-p ID]: print REMOTE_PATH (laptop root).
- count [-p ID]: file count on laptop.

### read

```bash
laptop-exec read [-p ID] [-w PATH] <file>
```

- Exactly one file. Relative to laptop project root. Backslash -> slash.
- Windows: Get-Content -LiteralPath -Raw over SSH stdout. Mac: cat.
- Never pass /home/.../mounts/... .

Encoding (Windows, deep): on-disk bytes after write/scp are correct. Bringing non-ASCII back through SSH/console may show ? or mojibake. Verify UTF-8 with:

```bash
laptop-exec run -p ID -- powershell -NoProfile -Command \
  "[BitConverter]::ToString([IO.File]::ReadAllBytes('path/file.txt'))"
```

ASCII configs/scripts: read is fine.

### write

```bash
laptop-exec write [-p ID] <file>
```

- stdin required; full replace; temp on server -> scp to laptop:$REMOTE_PATH/$rel.
- Creates parent dirs. Binary-safe on disk. No stdin => write: no stdin.

### rg

```bash
laptop-exec rg [-p ID] <pattern> [pathspec...]
```

1. Git dir .git.server-session or .git (cached ~300s).
2. If git: pattern has []()|+? => git grep -n -E; else -F. pathspecs passed. exit 1 = no matches.
3. Else fallback: Windows Select-String all files; Mac rg or grep -R -E.

No -i flag. .* alone does not enable -E (only []()|+?).

### git

```bash
laptop-exec git [-p ID] [--] <args...>
```

- -- optional. GIT_MODE=server => plain git. Else git --git-dir=<detected> --work-tree=.
- hide mode: SSHFS may hide .git; laptop still has real .git -- always laptop-exec git.

### run

```bash
laptop-exec run [-p ID] [--] <cmd...>
```

- cd project on laptop then cmd. Windows: PowerShell `-EncodedCommand` (UTF-16LE); Mac: `bash -lc`.
- Use -- before flag-like args. Prefer PowerShell for complex quoting.

### test

laptop-exec test -- built-in self-check.

---

## F) Decision trees

Need file contents?
  mounts/project -> laptop-exec read -p ID REL
  /tmp or ~/.cursor -> Cursor Read OK

Need search?
  project -> laptop-exec rg -p ID PATTERN [path]
  server logs under ~/.cursor -> Cursor Grep/Read OK

Need edit?
  read > /tmp/x; edit on server; write < /tmp/x; git -- diff

Tunnel?
  status exit 0 UP -> proceed
  exit 1 DOWN -> user connect.bat/sh; stop
  sshfs STALE + tunnel UP -> still laptop-exec

---

## G) Recipes

Wrong active_mount:

```bash
laptop-exec read -p claude-code-server CLAUDE.md
export LAPTOP_EXEC_WORKSPACE=/home/$USER/mounts/claude-code-server
laptop-exec read CLAUDE.md
```

Find csproj:

```bash
laptop-exec run -p ID -- powershell -NoProfile -Command \
  "Get-ChildItem -Recurse -Filter *.csproj | Select-Object -Expand FullName"
```

Subagent block:

```
SSH-first mandatory. laptop-exec status first.
Use -p PROJECT on every read/rg/git/run/write.
Paths repo-relative on laptop; never /home/.../mounts/...
Cursor Read/Grep/Write on /mounts/ are hook-denied; do not retry.
```

---

## H) Anti-patterns

| Wrong | Right |
|-------|-------|
| Read mounts path after deny | laptop-exec read -p ID REL |
| laptop-exec read -p ID /home/.../mounts/ID/REL | read -p ID REL |
| Ignore workspace vs active_mount | always -p when they differ |
| cd mounts && git/rg/cat | laptop-exec git/rg/read |
| Assume rg -i / rg --glob | unsupported; pattern/pathspec/run |
| Trust UTF-8 via read stdout on Windows | write OK; byte-dump verify |
| `laptop-exec -p ID read` (was broken) | now OK — both flag orders work |
| Ask user to enable laptop-exec | just use when tunnel UP |
| Task explore without laptop-exec instructions | paste subagent block |

---

## I) Errors

| Signal | Action |
|--------|--------|
| Hook SSH-first BLOCKED / Do NOT retry | Remap; continue |
| no connect session | connect.bat/sh |
| status exit 1 / tunnel DOWN | connect.bat/sh |
| unknown project | list |
| no project | pass -p (before or after subcommand) |
| unknown command '-p' | outdated binary; both orders work on current |
| no git repository on laptop | fix -p |
| Get-Content Cannot find path | use relative path |
| write: no stdin | heredoc/pipe |
| rg exit 1 | no matches (normal) |
| Mojibake on read | byte verify / ASCII |

---

## J) Checklist

```
[ ] status UP
[ ] -p if workspace != active_mount
[ ] REL paths only (no /home/.../mounts/)
[ ] read/rg/write/git/run via laptop-exec
[ ] no retry of denied Cursor tools
[ ] after write: git -- diff/status
[ ] non-ASCII: prefer write + byte verify
[ ] project hooks.json is {"version":1,"hooks":{}}
[ ] preToolUse matcher has no Shell
[ ] no 00-no-laptop-exec.mdc in workspace rules
```

## Deploy / sudo (Smart + Sepidz) — NEVER prompt

Gitignored passwords live on the **laptop** only:

| Target | File | Variable |
|--------|------|----------|
| Smart (this server) | `publish/smart-deploy.local.ps1` | `SmartSudoPassword` |
| Sepidz | `publish/sepidz-deploy.local.ps1` | `SepidzSudoPassword` |

**Always** use `sudo-from-laptop` (reads via `laptop-exec`; never print the password):

```bash
# Validate
sudo-from-laptop --smart -v
sudo-from-laptop --sepidz -v

# Local Smart sudo (install / redeploy)
sudo-from-laptop --smart -- install -m 755 /tmp/x /usr/local/bin/x
sudo-from-laptop --smart -- claude-server install

# Remote Sepidz sudo
sudo-from-laptop --sepidz -- bash -lc 'claude-server verify'
```

Do **not** ask the user for sudo password. Do **not** `sudo` interactively.
Wrong: `sudo install ...` then hang on password.
Right: `sudo-from-laptop --smart -- install ...`

Windows publish already uses `Get-DeployCredentials.ps1` → same local files.

---

## MULTI-AGENT (mandatory)

When spawning Task / subagents:

1. Task spawn itself is allowed by hooks.
2. **Every** subagent prompt MUST say: use only `laptop-exec -p PROJECT ...`; never Read/Grep/Glob/Write/Edit/Shell-heavy on `/mounts/`.
3. Parent passes the project id (`-p`) explicitly in the prompt.
4. On deny: run the `NEXT:` laptop-exec command — never retry the denied Cursor tool.
5. Parallel laptop-exec shares one SSH mux with session slots (~8). Waiting is OK; do not open raw `ssh`/`scp` bypasses.
6. Never run concurrent stress/burst tests against the tunnel.



## K) Infrastructure (exact — multi-agent safe)

### Hooks wiring

- User only: `~/.cursor/hooks.json` → `sessionStart` (session.sh), `beforeShellExecution` + `preToolUse` → **`laptop-exec-guard-wrap.sh`** (not raw guard).
- Wrap is **fail-open**: broken/`bash -n` fail/non-JSON/nonzero guard → `{"permission":"allow"}`, always exit 0 (Cursor exit 2 = deny).
- Project `~/mounts/<ID>/.cursor/hooks.json` must stay `{"version":1,"hooks":{}}` (`hooks-project.json` golden). Refilling with user hooks (esp. Shell in preToolUse) double-fires and locks multi-agent.
- `laptop-exec-setup` must not reintroduce nonempty project hooks.

### SSH mux / slots

| Item | Exact |
|------|-------|
| ControlPath | `~/.cache/laptop-exec/cm-%C` |
| Slots | 8 (`slot-0`…`slot-7`); wait ≤ **240×0.2s ≈ 48s** then stderr `session slots full` + return 255 |
| Master bring-up | `flock -w 8` on `cm.lock`; if flock fails → **no** `ssh -fN` |
| Opts | `ConnectTimeout=8`, `ControlPersist=300`, `BatchMode` |
| Cache | `sshfs-cache.tsv` TTL 45s; `git-dir-cache.tsv` TTL 300s; writes under `cache.lock` |
| Laptop sshd (via connect) | `MaxSessions 32`, `MaxStartups 20:50:100` before sshd restart — live only after reconnect |

Never kill a healthy ControlMaster on retry. Never burst-stress the tunnel.

### sessionStart env

When project id inferred: sets `LAPTOP_EXEC_WORKSPACE=/home/$USER/mounts/<ID>` and `LAPTOP_EXEC_PROJECT=<ID>` plus SSH-first + multi-agent `additional_context`.


## Conflict warning

Never add workspace rules that forbid `laptop-exec` (e.g. `00-no-laptop-exec.mdc`). User hooks still deny Read/Grep/Shell on `/mounts/`; forbidding laptop-exec creates a hard deadlock. If such a rule exists, delete it and use this skill.
