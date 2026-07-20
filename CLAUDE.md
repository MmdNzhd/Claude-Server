# Claude Code Server — Project Rules

## Language Rule

**No Persian text in scripts.** Persian is allowed only in documentation files (CLAUDE.md, READMEs).
All scripts (`*.sh`, `*.ps1`, `*.bat`) must use English only — comments, variable names, error messages.

## Architecture Overview

SSH reverse tunnel: client laptop → server, port = `20000 + server_UID`.
**Source of truth = laptop disk.** Optional SSHFS under `~/mounts/<ID>/` is for Cursor UI only and may be STALE or NOT_MOUNTED.

**Agents must use SSH-first `laptop-exec`** (not Cursor Read/Grep/Write on `/mounts/`). Connect UI `sshx()` / `SshX()` open one-shot SSH (no mux). `laptop-exec` uses a shared SSH ControlMaster through the same reverse tunnel.

```
Laptop ──SSH──▶ Server (port 22) + reverse tunnel (20000+UID)
Cursor agent on server ──laptop-exec (ControlMaster)──▶ 127.0.0.1:TUNNEL_PORT ──▶ laptop disk
Optional: Server ──SSHFS──▶ Laptop (UI; may be stale — never prefer over laptop-exec)
```

## File Map

```
scripts/
  client/
    mac/connect.sh                # Mac launcher (bash, runs in Terminal)
    windows/connect.ps1           # Windows launcher (PowerShell, self-elevates to admin)
    connect-ui.sh / connect-ui.ps1 # Shared connect UI + server-only logging
    editor-launch.ps1 / .sh       # Shared VS Code/Cursor launch (dot-sourced by connect)
    git-mode.ps1 / git-mode.sh    # Shared GIT_MODE helpers + Mac SSH diag upload
    tests/                        # Client regression tests (run-all.bat)
    users/designer/               # Designer-only (noVNC, no editor) — separate product
    users/designer/connect.sh     # Designer Mac launcher: SSHFS + noVNC port forward
    users/designer/connect.ps1    # Designer Windows launcher
    users/designer/connect.bat    # Double-click launcher for Windows
    users/designer/README.md      # End-user quick-start included in designer package
  server/
    claude-server                 # CLI dispatcher → /usr/local/bin/claude-server
    commands/
      install.sh                  # Full server install (idempotent)
      add-user.sh                 # Add a developer account
      verify.sh                   # Test all components
      status.sh                   # Show sessions and usage
      sync-auth.sh                # Push OAuth token to all users
      deploy-auth.sh              # Install setup-token + sync + probe + audit log
      sync-cursor-auth.sh         # Push Cursor golden identity to all users
      diagnose-auth.sh            # Auth / login diagnostics
      update-server.sh            # git pull + redeploy
    hooks/                        # Claude Code hooks → /usr/local/bin/
    claude-wrapper.sh
    claude-limits.conf
    claude-automount.sh
    claude-auth-sync.sh             # OAuth → ~/.claude/settings.json + empty credentials.json
    claude-auth-lib.py              # OAuth audit log, API probe, deploy helpers
    claude-auth-probe.sh            # Cron/manual token probe → /var/log/claude-auth.log
    cursor-auth-export.sh           # Export golden Cursor identity → /etc/cursor-auth/golden/
    cursor-auth-sync.sh             # Golden identity → ~/.config/Cursor/ per user
    cursor-auth-refresh.sh          # Refresh OAuth tokens + re-sync (cron every 6h)
    cursor-auth-lib.py              # Shared Python helpers for export/sync/refresh
    claude-mount.sh               # Pushed to server ~/.local/bin/claude-mount on connect
    claude-git-setup.sh           # Local git mirror; skipped when GIT_MODE=server
    laptop-exec.sh                # SSH-first CLI → /usr/local/bin/laptop-exec + per-user ~/.local/bin
    laptop-exec-setup.sh          # Idempotent user/project hook+skill install (project hooks stay EMPTY)
    sudo-from-laptop.sh           # Non-interactive sudo (Smart local / Sepidz via SSH)
    cursor-hooks/                 # Guard wrap, shell-scan, sessionStart, hooks-user/project JSON
    skills/laptop-exec/SKILL.md   # Agent skill (mandatory remap to laptop-exec)
    cursor-rules/laptop-exec.mdc  # Cursor rule (SSH-first)
    commands/deploy-laptop-exec.sh
    claude-connect-logs-cleanup.sh # Hourly: delete ~/.claude/logs older than 1 day
docs/
  client-connect.md               # Client user + developer guide (GIT_MODE, logs, hotkeys, tests)
  sshfs-performance.md            # SSHFS git hide investigation + GIT_MODE
  claude-design.md                # connect-design (claude.ai/design) — separate from users/designer
publish/
  publish.ps1                     # Builds Smart + Sepidz ZIPs (run via publish.bat)
  publish.bat                     # Double-click launcher for publish.ps1
  README.txt                      # Smart package README (IP 192.168.210.240)
  README-sepidz.txt               # Sepidz package README (IP 192.168.250.70) -> claude-code/README.md
```

## Server Commands

```bash
sudo claude-server install        # Full install/redeploy (idempotent, safe to re-run)
sudo claude-server add-user <name>
sudo claude-server verify
sudo claude-server status
sudo claude-server sync-auth      # After token change — pushes OAuth to all ~/.claude/
sudo claude-server deploy-auth <token>  # Install setup-token + sync + probe + audit log
sudo claude-server sync-cursor-auth  # Push Cursor golden identity to all ~/.config/Cursor/
sudo claude-server deploy-mount-fix  # Redeploy mount + automount (ACTIVE_MOUNT single-project)
sudo claude-server deploy-client-bundle  # Publish client scripts for laptop auto-update
sudo claude-server audit-cursor-golden  # Deep golden metadata audit (no secrets printed)
sudo claude-server diagnose-auth  # Find login / OAuth problems
sudo claude-server update-server  # git pull + full redeploy
```

**OAuth auth (automatic after install):** Server token lives root-only in `/etc/claude-code/oauth.env` (mode `0600`). Do **not** put it in world-readable `/etc/environment`. `deploy-auth` / `sync-auth` / `add-user` call `claude-auth-sync` which writes `env.CLAUDE_CODE_OAUTH_TOKEN` into each user's `~/.claude/settings.json` (required for VS Code extension) and resets `~/.claude/.credentials.json` to `{}` (Claude 2.1.x prefers credentials file over env var). Audit log `/var/log/claude-auth.log` is mode `0600`.

**Cursor golden auth (IDE via Remote SSH):** One shared Cursor account + one virtual device for all developers. Golden bundle lives in `/etc/cursor-auth/golden/` (`auth.json`, `state-keys.json`, `storage.json`, `machine-id.txt`) with directory `0700` and files `0600` (root-only). Root `add-user` / `sync-cursor-auth` / cron refresh push copies into each `~/.config/Cursor/`. Bootstrap once on the server (`agent login` or one Remote SSH session), then sync to everyone:

```bash
# After first Remote SSH session or: agent login
sudo cursor-auth-export --from-user smart
sudo claude-server sync-cursor-auth
```

`add-user`, `claude-automount`, `sync-cursor-auth`, and cron (`cursor-auth-refresh` every 6h) keep `~/.config/Cursor/User/globalStorage/` aligned. Laptops only need `cursor.exe` + Remote-SSH — **no per-laptop Cursor login**.

**Chat uses laptop globalStorage — via an isolated profile:** Remote SSH Chat reads the *local* Cursor globalStorage on Windows, not the server's `.cursor-server` storage. `connect.ps1` opens Cursor with `--user-data-dir <LOCALAPPDATA>\ClaudeServerCursorProfile` (`Get-CursorRemoteProfileDir` in `editor-launch.ps1`) — a dedicated profile, separate from the developer's default `%APPDATA%\Cursor` profile. `cursor-auth-sync --force` runs on the server, then `cursor-auth-laptop.ps1` **merges** auth keys into that isolated profile's `state.vscdb` via SQLite UPSERT (never replaces the whole file, never closes any Cursor window). Many server-profile windows share one profile dir — one merge updates all of them. Personal Cursor (`%APPDATA%\Cursor`) is **never read, overwritten, or closed**.

**Corruption safety:** Auth sync does not close or kill any Cursor process (personal or server-profile). Keys are merged in-place into the open `state.vscdb`; WAL sidecar files are never deleted. Profile isolation keeps personal and server logins in separate `--user-data-dir` trees so they can run concurrently without file-lock conflicts on the personal profile.

**Risks:** Cursor ToS prohibits sharing one login across multiple people; concurrent sessions may conflict on refresh tokens. Official alternative: Cursor Teams/Enterprise. See [`scripts/server/CURSOR-AUTH-PILOT.md`](scripts/server/CURSOR-AUTH-PILOT.md) for validation checklist.

**First-time bootstrap** (before `claude-server` is on PATH):
```bash
sudo bash scripts/server/commands/install.sh
# After this, sudo claude-server install works normally
```

**If claude-server not on PATH** (run scripts directly from repo):
```bash
REPO=/path/to/claude-code-server
bash "$REPO/scripts/server/commands/add-user.sh" <name>
```

## MCP Servers (installed per-user via add-user.sh)

Every user gets these MCP servers wired into `~/.claude/settings.json` automatically:

| MCP Server | Purpose | Install |
|---|---|---|
| `codegraph` | Code knowledge graph — fewer tool calls, cheaper sessions | step 9 in `install.sh` |
| `headroom` | Context compression — reduces tokens sent to LLM | `pip3 install headroom-ai[mcp]` (step 10) |
| `sqlserver` | SQL Server query access via MCP | `npm install -g @bilims/mcp-sqlserver` |

**SQL Server connection settings** — stored in `~/.claude/settings.json` under `mcpServers.sqlserver.env`. Each user can edit their own file to change the connection:

```json
"sqlserver": {
  "type": "stdio",
  "command": "/usr/bin/mcp-sqlserver",
  "args": [],
  "env": {
    "SQLSERVER_HOST": "192.168.210.124",
    "SQLSERVER_USER": "Mohammad",
    "SQLSERVER_PASSWORD": "CHANGE_ME"
  }
}
```

To update the IP for all users at once (run as root on server):
```bash
for user in smart amir amirhossein aria danial hamed hamed.kh kiana mahdie mehrdad mohammad parsa reza tarane; do
  f="/home/$user/.claude/settings.json"
  [ -f "$f" ] && sed -i 's/OLD_IP/NEW_IP/g' "$f" && echo "✓ $user"
done
```

**CodeGraph per-project indexing** — runs automatically on login via `claude-automount`. Manual trigger:
```bash
codegraph init   # run inside project dir if .codegraph/ is missing
```

## Plugins (installed per-user via add-user.sh)

Every user gets these plugins enabled in `~/.claude/settings.json`:

| Plugin | Purpose | Source |
|---|---|---|
| `superpowers@claude-plugins-official` | Skills system — structured workflows, TDD, debugging, planning | official marketplace |
| `ecc@ecc` | Everything Claude Code — 261 skills, 64 agents, 84 commands | github: affaan-m/ECC |

The `settings.json` template lives in `add-user.sh` step 4 — if you add/remove MCP servers or plugins, update that template.

**Gotcha:** `add-user.sh` must NOT use `chown -R` on `~/home/$user` — SSHFS mounts under `~/mounts/` are owned by the remote user and will fail with `Operation not permitted`, aborting the script. Always chown specific subdirs only (`.claude/`, `.config/Cursor/`, `.local/bin/`, `.ssh/`).

## Connect session logs

**Policy:** zero-loss offline-first. The laptop keeps a **durable local day log** and watermark-syncs to the server when SSH works. Session end does **not** delete the local day file.

| Artifact | Path |
|---|---|
| Laptop day log (durable) | Win: `%USERPROFILE%\.config\claude-connect\logs\connect-YYYYMMDD.log` · Mac: `~/.config/claude-connect/logs/connect-YYYYMMDD.log` |
| Server (synced) | `~/.claude/logs/connect-YYYYMMDD.log` |
| Laptop SSH failure diag | `~/.claude/logs/laptop-ssh-diag-latest.txt` (+ timestamped copies) |
| Retention | Server: client flush + cron `claude-connect-logs-cleanup` delete `-mtime +1`; local day logs stay for offline audit |

Client UI helpers: `scripts/client/connect-ui.sh` / `connect-ui.ps1`. Deploy: `sudo claude-server install` installs cleanup + `/etc/cron.d/claude-connect-logs`. Details: [`docs/client-connect.md`](docs/client-connect.md).


## SSH-First / laptop-exec (agents)

Verified against live `laptop-exec` / hooks. Numbers and matchers are exact.

### Mental model

```
[Cursor agent on Linux]
   Read/Grep/Write/… path under /mounts/     → preToolUse DENY (+ NEXT:)
   Grep/Glob with no path but workspace_roots under /mounts/ → DENY
   Shell heavy + (cwd or cmd touches /mounts/) → beforeShellExecution DENY
   Shell containing substring "laptop-exec"  → not heavy
   Task spawn                                  → always ALLOW
        |
        v
[laptop-exec]  ControlPath=~/.cache/laptop-exec/cm-%C
               8 flock slots (slot-0 … slot-7); cm.lock for master only
        |
        +-- SSH ControlMaster --> 127.0.0.1:$TUNNEL_PORT --> laptop disk (truth)
Optional SSHFS ~/mounts/<ID>/ may be STALE/NOT_MOUNTED — UI only; never prefer over laptop-exec.
```

Session: `~/.claude-connect.conf` (`LAPTOP_USER`, `TUNNEL_PORT`, `LAPTOP_OS`, `ACTIVE_MOUNT`, `GIT_MODE`).  
Key `~/.ssh/claude_laptop`. KnownHosts `~/.ssh/known_hosts_claude_mount`.  
Cache dir `~/.cache/laptop-exec/` (`cm-*`, `cm.lock`, `slot-*.lock`, `cache.lock`, `sshfs-cache.tsv`, `git-dir-cache.tsv`).

### Project resolve order (exact)

1. `-p` / `--project` (also **before** subcommand: `laptop-exec -p ID read REL`)
2. `-w` / `--workspace` if path contains `/mounts/`
3. Else first of `LAPTOP_EXEC_WORKSPACE`, `CURSOR_WORKSPACE`, `CURSOR_PROJECT_DIR`, `PWD` containing `/mounts/`
4. Else `ACTIVE_MOUNT`
5. Else die: `no project`

Cursor often does not export `CURSOR_*`. Prefer always `-p`. Both flag orders work.

`sessionStart` (when project id inferred) also sets env: `LAPTOP_EXEC_WORKSPACE=/home/$USER/mounts/<ID>`, `LAPTOP_EXEC_PROJECT=<ID>`.

### Hard rules

1. Denied on mounts: **Grep, Glob, Read, Write, Edit, EditNotebook, StrReplace, Delete** — do not retry; run `NEXT:`.
2. **Task** matched but always allowed to spawn.
3. First I/O = Shell + `laptop-exec`. Paths for `read|write|rg` are **laptop repo-relative**.
4. Tunnel DOWN → stop; user `connect.bat` / `connect.sh`. Do not ask to enable SSHFS.
5. No tunnel stress/burst. No sudo password prompts (`sudo-from-laptop`).
6. Windows `read` stdout may mangle non-ASCII; `write`/scp binary-safe — verify with byte dump via `run` if needed.
7. After `write`: `laptop-exec git -p ID -- status` / `diff` (when relevant).
8. Every Task prompt must require laptop-exec-only + `-p`.

### Decision tree

```
Need file contents?
  under ~/mounts/ID → laptop-exec read -p ID REL
  /tmp or ~/.cursor or non-mount /home → Cursor Read OK

Need search?
  project → laptop-exec rg -p ID PATTERN [pathspec]
  server-only paths → Cursor Grep OK

Need edit?
  read → edit locally (/tmp) → laptop-exec write -p ID REL < file
  then git -- diff/status

Need build/test?
  laptop-exec run -p ID -- …   (or git/test)
  not: cd mounts && dotnet/npm/pytest

Tunnel?
  status UP → proceed (even if sshfs STALE)
  status DOWN / exit 1 → user connect; stop
```

### CLI — behavior-accurate

Subcommands: `status`, `health`, `list` [`--full`], `resolve`, `mount-status`, `path`, `count`, `read`, `write`, `run`, `git`, `rg`, `test`, `help`.

#### status / health / list

- `status`: `tunnel_port`, `laptop_user`, `laptop_os` (`windows|mac`), `active_mount`, `git_mode` (`hide|server|off`), `tunnel` UP|DOWN, `sshfs` for active only, `prefer`. Exit **1** if no `LAPTOP_USER` or tunnel DOWN.
- `health`: status (tolerate fail) + projects + fast list.
- `list`: default fast (`sshfs=(list --full)` placeholder). `list --full`: real sshfs probe. Active marked ` *`.
- sshfs probe cache TTL **45s** (`sshfs-cache.tsv`).

#### mount-status / path / count

- `mount-status [-p ID]`: project, local_path, laptop_path, sshfs, tunnel, recommend.
- `path [-p ID]`: print laptop `REMOTE_PATH`.
- `count [-p ID]`: file count on laptop.

#### read

```bash
laptop-exec read [-p ID] [-w PATH] <file>     # exactly one file
```

Relative to laptop project root; `\` → `/`. Windows: `Get-Content -LiteralPath -Raw` over SSH. Mac: `cat`. Never `/home/.../mounts/...`.

UTF-8 verify (Windows):

```bash
laptop-exec run -p ID -- powershell -NoProfile -Command \
  "[BitConverter]::ToString([IO.File]::ReadAllBytes('REL'))"
```

#### write

```bash
laptop-exec write [-p ID] <file>   # stdin required; full file replace
```

Server temp → scp → laptop `$REMOTE_PATH/$rel`; creates parents; binary-safe. No stdin → `write: no stdin`.

```bash
laptop-exec write -p ID path/file <<'EOF'
...
EOF
```

#### rg

```bash
laptop-exec rg [-p ID] <pattern> [pathspec...]
```

1. Detect git dir `.git.server-session` or `.git` (cache TTL **300s**).
2. If git: pattern contains `[]()|+?` → `git grep -n -E`; else `-F`. Exit **1** = no matches (normal).
3. Else Windows: `Select-String` (all files); Mac: `rg` or `grep -R -E`.

No `-i`. `.*` alone does **not** force `-E`.

#### git

```bash
laptop-exec git [-p ID] [--] <args...>
```

`GIT_MODE=server` → plain `git`. Else `git --git-dir=<detected> --work-tree=.`. Hide mode: SSHFS may hide `.git`; laptop still has it — always use `laptop-exec git`.

#### run

```bash
laptop-exec run [-p ID] [--] <cmd...>
```

cd to project on laptop then run. Windows: PowerShell `-EncodedCommand` (UTF-16LE). Mac: `bash -lc`. Use `--` before flag-like args.

#### test

`laptop-exec test` — built-in self-check.

#### SSH transport (exact)

| Item | Value |
|---|---|
| Opts | `BatchMode`, `ConnectTimeout=8`, `ServerAliveInterval=15`, `ServerAliveCountMax=3`, `ControlMaster=auto`, `ControlPersist=300`, `ControlPath=cm-%C` |
| Slots | 8 (`0..7`); wait up to **240×0.2s=48s**; then stderr + return **255** |
| Master | `flock -w 8` on `cm.lock`; flock fail → **no** `ssh -fN`; bring-up `ConnectTimeout=3` |
| Retry | ≤4 on exit 255; sleep ~0.5–0.9s; delete mux sockets **only if** master `ssh -O check` fails |
| Cache lock | `cache.lock` around TSV rewrites |

`GIT_MODE` normalize: `server|on|yes|1|slow` → server; `hide|fast` → hide; else `off`.

### Hooks (complete)

**User** `~/.cursor/hooks.json` → absolute wrap/session paths.

| Event | Command | Notes |
|---|---|---|
| `sessionStart` | `…/laptop-exec-session.sh` | `additional_context` + optional env |
| `beforeShellExecution` | `…/laptop-exec-guard-wrap.sh` | all shells |
| `preToolUse` | `…/laptop-exec-guard-wrap.sh` | matcher below |

Exact `preToolUse` matcher (no Shell):

```
Grep|Glob|Read|Write|Edit|EditNotebook|StrReplace|Delete|Task
```

**Project** hooks must be exactly `{"version":1,"hooks":{}}`. `laptop-exec-setup` `_ensure_project_hooks` writes only that (no guard copies under mounts). Golden: `cursor-hooks/hooks-user.json`, `hooks-project.json`.

**Wrap:** always exit 0; missing/broken/`bash -n` fail/non-JSON/nonzero → `{"permission":"allow"}`. Stamp `.guard-syntax-ok` skips `bash -n` when newer than guard.

**Guard:** `set -uo pipefail`; `trap '_allow' ERR`; deny via jq then `exit 0` (Cursor treats exit **2** as deny — wrap prevents that).

**Path targeting (`_tool_path_blob`):** `tool_input`/`input` fields `path`, `target_directory`, `file_path`, `target_notebook`, arrays `paths`. **Not** Shell `working_directory` as a file path (avoids false-deny `echo` with cwd under mounts).

If those paths empty: Grep/Glob/Read/Write/Edit/EditNotebook/StrReplace/Delete fall back to `workspace_roots` + `cwd` touching `/mounts/`.

Shell uses `tool_input.command`/`command` + `tool_input.working_directory`/`cwd` with `_shell_should_block` only.

**Scan:** strip heredocs, quotes, `\| head|tail|wc …`. Fast path (no `<<`, no quotes): bash `sed` only (skip python).

### Heavy shell (exact)

Interpreters `python|python2|python3|node|nodejs|ruby|perl|python3.*` → allow unless `python -m pytest|unittest`.

Heavy alternation (guard):

```
git|find|rg|grep|dotnet|npm|npx|yarn|pnpm|bun|deno|cargo|make|cmake|mvn|gradle|
go[[:space:]]+(build|test|run)|python[[:space:]]+-m[[:space:]]+(pytest|unittest)|
pytest|jest|vitest|tsc|webpack|vite[[:space:]]+build|cat|sed|awk|head|tail|wc|ls[[:space:]]+-R
```

Anchor: BOL, or after space/`&`;/`|`, or after `/` (`/usr/bin/git`).

Substring `laptop-exec` → not heavy.

**Block:** (1) not heavy → allow (2) heavy + cmd touches mounts → deny (3) heavy + cwd mounts → deny unless escape (4) else allow.

**Escape (`_cmd_has_non_mount_abs`):** strip `#` comments; allow only `git -C /tmp…`, or `(cat|sed|awk|find|rg|grep|git|npm|dotnet) /tmp…`, or `(cat|sed|awk|find|rg|grep) /home/…` where token does not touch mounts. **Not** escapes: `git status && echo /tmp`, `cat README && ls /usr`.

False-deny fixed historically: heredoc body with word `git`; `ls | head`; `echo` with mounts cwd.

### Multi-agent — failure chain (exact)

| # | Failure | Mechanism | Mitigation |
|---|---|---|---|
| 1 | Double fire | user + nonempty project hooks | project hooks `{}` |
| 2 | Shell double-gate | Shell in preToolUse + beforeShell | matcher without Shell |
| 3 | Task denied | explore/shell blocked | Task → `_allow` |
| 4 | Mux overflow | default MaxSessions **10** | **8** slots |
| 5 | Cascade | old `ssh -O exit` / wipe `cm-*` | reset only if master dead |
| 6 | Master race | `flock \|\| true` + `-fN` | flock must succeed |
| 7 | Deny storm | children retry Read/Grep | session + skill Task prompts |
| 8 | Tunnel drop | MaxStartups / TCP storm | shared mux; no stress tests |
| 9 | Cache race | concurrent TSV | `cache.lock` |

Connect sets laptop `sshd_config` **`MaxSessions 32`**, **`MaxStartups 20:50:100`** before sshd restart (`Ensure-OpenSshMuxLimits` / `ensure_openssh_mux_limits`). File ≠ live until reconnect. Agents must not restart sshd while tunnel is needed.

### Recipes

Wrong `active_mount`:

```bash
laptop-exec read -p claude-code-server CLAUDE.md
export LAPTOP_EXEC_WORKSPACE=/home/$USER/mounts/claude-code-server
```

Find files on Windows laptop:

```bash
laptop-exec run -p ID -- powershell -NoProfile -Command \
  "Get-ChildItem -Recurse -Filter *.csproj | Select-Object -Expand FullName"
```

Edit loop:

```bash
laptop-exec read -p ID REL > /tmp/x
# edit /tmp/x
laptop-exec write -p ID REL < /tmp/x
laptop-exec git -p ID -- diff -- REL
```

Task / subagent prompt block (paste verbatim):

```
SSH-first mandatory. laptop-exec status first.
Use -p PROJECT on every read/rg/git/run/write.
Paths repo-relative on laptop; never /home/.../mounts/...
Cursor Read/Grep/Write on /mounts/ are hook-denied; do not retry.
On deny: run the NEXT: laptop-exec command immediately.
```

### Errors

| Signal | Action |
|---|---|
| Hook SSH-first BLOCKED / Do NOT retry / `NEXT:` | Remap; do not retry Cursor tool |
| `no connect session` / status exit 1 / tunnel DOWN | user connect.bat/sh |
| `unknown project` | `laptop-exec list` |
| `no project` | pass `-p` |
| `unknown command '-p'` | stale binary; current accepts both orders |
| `no git repository on laptop` | wrong `-p` or no git on laptop |
| `Get-Content Cannot find path` | use relative REL |
| `write: no stdin` | heredoc/pipe |
| `rg` exit 1 | no matches (normal) |
| Mojibake on read | byte verify / prefer write |
| `session slots full` | wait ≤48s; reduce parallel `run` |
| Sepidz sudo auth fail | fix `sepidz-deploy.local.ps1`; deploy via laptop SSH |

### Deploy / sudo (complete)

| Target | Reach | Auth file (gitignored on laptop) |
|---|---|---|
| Smart | local sudo | `publish/smart-deploy.local.ps1` → `SmartSudoPassword` |
| Sepidz `192.168.250.70` | laptop SSH `Host claude-server-sepidz` (Smart server often cannot route) | `publish/sepidz-deploy.local.ps1` → `SepidzSudoPassword`, `SepidzSshUser` |

```bash
sudo-from-laptop --smart -v
sudo-from-laptop --sepidz -v
sudo-from-laptop --smart -- claude-server deploy-laptop-exec
sudo-from-laptop --smart -- install -m 755 /tmp/x /usr/local/bin/x
```

Never ask the user for sudo password. Never interactive `sudo` that hangs on a prompt.

Per-user: `~/.local/bin/laptop-exec`, `~/.cursor/hooks/{guard,wrap,scan,session}.…`, hooks.json as above, empty project hooks, skill + rule.  
Golden: `/usr/local/bin/laptop-exec`, `laptop-exec-setup`, `/usr/local/lib/claude-server/cursor-hooks/`, skills/rules.  
After hooks.json change: Cursor **Reload Window** / new chat.

### Checklist

```
[ ] laptop-exec status → UP
[ ] -p if workspace != active_mount
[ ] REL paths only (no /home/.../mounts/)
[ ] read/rg/write/git/run via laptop-exec
[ ] no retry of denied Cursor tools
[ ] Task prompts include laptop-exec-only block
[ ] after write: git -- diff/status
[ ] non-ASCII: write + byte verify if needed
[ ] project hooks.json is {"version":1,"hooks":{}}
[ ] preToolUse matcher has no Shell
```

### Anti-patterns

| Wrong | Right |
|---|---|
| Retry Read/Grep after deny | `NEXT:` laptop-exec |
| `laptop-exec read -p ID /home/.../mounts/ID/REL` | `read -p ID REL` |
| Ignore workspace ≠ active_mount | always `-p` |
| `cd mounts && git/npm/cat` | `laptop-exec git/run/read` |
| Assume `rg -i` / rich globs | unsupported; use pattern/pathspec/`run` |
| Trust UTF-8 via Windows read stdout | write OK; byte-dump verify |
| Fill project hooks with user hooks | keep `{}` |
| `Shell` in preToolUse matcher | Shell only in beforeShellExecution |
| Burst parallel laptop-exec / raw ssh tests | slots + shared mux; no stress |
| Ask user for sudo password | `sudo-from-laptop` |
| Restart laptop sshd from agent to apply MaxSessions | user re-runs connect |

### Related paths

`scripts/server/laptop-exec.sh`, `laptop-exec-setup.sh`, `cursor-hooks/*` (guard, wrap, scan, session, hooks-user/project), `skills/laptop-exec/SKILL.md`, `cursor-rules/laptop-exec.mdc`, `sudo-from-laptop.sh`, `commands/deploy-laptop-exec.sh`, `scripts/client/windows/connect.ps1`, `scripts/client/mac/connect.sh`, `publish/*-deploy.local.ps1`.

Deep agent skill (also installed per-user): [`scripts/server/skills/laptop-exec/SKILL.md`](scripts/server/skills/laptop-exec/SKILL.md). Client guide: [`docs/client-connect.md`](docs/client-connect.md).

## Sync Rule for Server Scripts

When any of these files change, update `scripts/server/commands/install.sh` (the deploy section) and re-run `sudo claude-server install`:

| Changed file | Section to update |
|---|---|
| `scripts/server/hooks/claude-hook-*.sh` | deploy hooks |
| `scripts/server/claude-wrapper.sh` | deploy wrapper |
| `scripts/server/claude-limits.conf` | deploy config |
| `scripts/server/claude-automount.sh` | deploy scripts — `claude-automount` + cron unchanged |
| `scripts/server/claude-auth-sync.sh` | deploy scripts — `install -m 755 … /usr/local/bin/claude-auth-sync` |
| `scripts/server/claude-auth-lib.py` | deploy scripts — `/usr/local/lib/claude-server/claude-auth-lib.py` |
| `scripts/server/claude-auth-probe.sh` | deploy scripts — `claude-auth-probe` + `/etc/cron.d/claude-auth-probe` |
| `scripts/server/cursor-auth-export.sh` | deploy scripts — `cursor-auth-export` + golden dir |
| `scripts/server/cursor-auth-sync.sh` | deploy scripts — `cursor-auth-sync` |
| `scripts/server/cursor-auth-refresh.sh` | deploy scripts — `cursor-auth-refresh` + cron |
| `scripts/server/cursor-auth-lib.py` | deploy scripts — `/usr/local/lib/claude-server/cursor-auth-lib.py` |
| `scripts/server/cursor-auth-source-path.sh` | deploy scripts — `cursor-auth-source-path` |
| `scripts/server/audit-cursor-golden-deep.py` | deploy scripts — `/usr/local/lib/claude-server/audit-cursor-golden-deep.py` |
| `scripts/server/laptop-exec.sh` | deploy scripts — `laptop-exec` + skill + `cursor-rules/laptop-exec.mdc` + `cursor-hooks/` |
| `scripts/server/cursor-hooks/*` | deploy scripts — guard, wrap, shell-scan, session, hooks-user/project (project empty) |
| `scripts/server/claude-connect-logs-cleanup.sh` | deploy scripts — `claude-connect-logs-cleanup` + `/etc/cron.d/claude-connect-logs` |
| `scripts/server/sudo-from-laptop.sh` | deploy scripts — `sudo-from-laptop` (Smart/Sepidz sudo via laptop `*.local.ps1`) |
| `scripts/server/laptop-exec-setup.sh` | deploy scripts — `laptop-exec-setup` |
| `scripts/server/claude-mount.sh` | pushed on connect; also deploy via install.sh → `/usr/local/lib/claude-mount` |
| `scripts/server/claude-git-setup.sh` | pushed on connect; skipped when GIT_MODE=server |
| `scripts/server/commands/add-user.sh` | verify settings.json template |
| `scripts/server/commands/deploy-mount-fix.sh` | deploy scripts — `claude-server deploy-mount-fix` |
| `scripts/server/commands/deploy-client-bundle.sh` | deploy scripts — `claude-server deploy-client-bundle` |
| `scripts/server/commands/*.sh` | install copies all to `/usr/local/lib/claude-server/` |

## Client Script Invariants

**Never break these — they are load-bearing:**

| Invariant | Location | Why |
|---|---|---|
| `PORT = 20000 + server_UID` | mac:9, win:361 | Port formula; guard: `20000 < PORT ≤ 65535` |
| `CM='$HOME/.local/bin/claude-mount'` | mac:12, win:28 | Single-quoted — `$HOME` must expand on the REMOTE shell |
| `already_down` / `$alreadyDown` flag | mac:432, win:560 | Prevents double-cleanup in EXIT/finally traps |
| `_editor_opened` / `$editorOpened` flag | mac:434, win:557 | Prevents editor re-opening on tunnel reconnect |
| `_tunnel_alive()` ps state check | mac:590 | `kill -0` returns 0 for zombie processes — must check `ps -o state=` and filter `Z` |
| Single-quote sanitization on user input | mac:294,350-352 win:224,439 | `tr "'" '-'` (bash) / `-replace "'"` (PS) before passing to remote shell |
| `timeout 8 ssh ...` in cleanup | mac:441 | Bounds hang if remote `claude-mount down` gets stuck |
| Both EXIT and SIGTERM traps | mac:444-445 | `kill <pid>` won't trigger EXIT alone |
| `[Console]::Key` + `KeyChar` checks | win:610,728,784 | Physical key check so R/Q/C/X work under Persian/Arabic keyboard layouts |
| `[Uri]::EscapeDataString` for Gateway URL | win:695 | PS5.1+PS7 safe; avoids `System.Web` dependency |
| `$script:ConnectVersion = '20260720.1'` | win connect.ps1 | Must match connect.bat guard |
| `@(Choose-Project -Mounts $mounts)[-1]` | win connect.ps1 | Prevents pipeline leak → Join-Path ChildPath prompt |
| `@(Resolve-EditorChoice -CfgDir $CfgDir)[-1]` | win connect.ps1 | Same pipeline-safe capture |
| `return ,($obj)` in Choose-Project | win connect.ps1 | Unary comma suppresses pipeline output |
| `[System.IO.Path]::Combine` in editor-launch | editor-launch.ps1 | Do not use Join-Path for editor.conf paths |
| connect.bat guards | windows/connect.bat | Requires git-mode.ps1, Path.Combine, @(Choose-Project, version |
| Dot-source git-mode.ps1 / git-mode.sh | all Windows/Mac launchers | GIT_MODE must not be duplicated in forks |
| Push GIT_MODE to ~/.claude-connect.conf | connect.ps1/sh | Server claude-mount reads hide vs server |
| `CONNECT_VERSION='20260720.1'` | mac connect.sh | Must match published client version |
| Dot-source `connect-ui.ps1` / source `connect-ui.sh` | all launchers | UI tables, header, session box |
| Always elevate at start of connect.ps1 (UAC) unless already admin | win | Non-admin relaunches via `RunAs`; `-AdminFix` is the elevated child / repair path; `Ensure-LaptopSshReady` still used mid-session |
| Publish client package **12 files** | publish.ps1 | +connect-ui, editor-launch.sh (mac) |
| `CONNECT_PORT_BASE=20000` | mac connect.sh | Port formula base; guard: `base < PORT ≤ 65535` |
| `exit_requested` menu loop + M/C/X | mac connect.sh | Post-disconnect menu parity with Windows |
| `clear_session_mount` on disconnect | mac via git-mode.sh | Close editor + down + clear ACTIVE_MOUNT |
| `initialize_server_session` | mac via git-mode.sh | Parallel scp + single "Server setup" step |
| EXIT + SIGTERM + **SIGHUP** traps | mac connect.sh | Terminal close must cleanup mount |
| `Push-ServerConnectConf -ActiveMount` | win + designer | Single-project mount; clear on disconnect |

## Designer Script Invariants (`users/designer/`)

**Additional invariants for the designer connect scripts:**

| Invariant | Location | Why |
|---|---|---|
| EXIT + SIGTERM + **SIGHUP** traps | designer/connect.sh | Terminal close sends SIGHUP — without it, server mount is left dangling |
| `_novnc_opened=1` inside success branch only | designer/connect.sh | Set only when noVNC opens successfully; stays 0 on failure so reconnect retries |
| `$novncOpened = $true` inside success branch only | designer/connect.ps1 | Same — do NOT set in the else/fail branch |
| `$autoFixCount` reset to 0 on manual R reconnect | designer/connect.ps1 | Prevents permanent loss of auto-fix attempts across reconnects; do NOT reset on auto-reconnect `continue` |
| `grep -E "^${MOUNT_ID}\|"` with escaped pipe | designer/connect.sh | ERE mode required; unescaped `\|` in BRE alternation breaks on `grep -E` aliases |
| Conf validated after source: `LAPTOP_USER` + `LAPTOP_PATH` non-empty | both | `set -uo pipefail` / PowerShell dies with cryptic error on unset vars — explicit die with clear message |
| `$SshDir` ACL grants both `$env:USERNAME` AND `$LaptopUser` when they differ | designer/connect.ps1 | Windows sshd reads `authorized_keys` under `$LaptopUser` token — directory must be listable by that user |
| `-L "127.0.0.1:${NOVNC_PORT}:127.0.0.1:${NOVNC_PORT}"` in tunnel | both | noVNC websockify binds `127.0.0.1` only — must forward via SSH local port, not direct LAN |

## macOS SSH Detection (Three Layers)

`pgrep -x sshd` is unreliable on macOS with on-demand launchd SSH. Use this order:

1. `nc -zw1 127.0.0.1 22` — fastest
2. `launchctl print system/com.openssh.sshd | grep -q 'state = running'`
3. `launchctl list com.openssh.sshd >/dev/null 2>&1` — exit code only (grep on output is a false positive)
4. `systemsetup -getremotelogin` — slow fallback, requires sudo on newer macOS

## Client Codebase (Smart + Sepidz)

**One codebase** — `windows/connect.ps1` + `mac/connect.sh`. Same alias (`claude-server`), cfg (`~/.config/claude-connect`), port base (`20000 + UID`).

**Sepidz vs Smart differs only at publish time:** `publish.ps1` builds two ZIPs; the Sepidz package copies the same client scripts with `SERVER_IP` patched (`192.168.210.240 -> 192.168.250.70`) in `connect.ps1`, `connect.sh`, and designer connect scripts. Package READMEs: `publish/README.txt` (Smart) vs `publish/README-sepidz.txt` (Sepidz). **Do not** maintain a separate `users/sepidz/` fork.

**Designer** (`users/designer/`) is a separate product (noVNC, no editor) — also gets IP patch in the Sepidz ZIP only.

**Client sync rule:** Editor-launch changes go in `scripts/client/editor-launch.ps1` only. Git-mode changes go in `scripts/client/git-mode.ps1` / `git-mode.sh`. All launchers dot-source them. `publish.ps1` copies them into ZIP packages.

## Self-Healing Behaviours

The client scripts handle these automatically without user intervention:

| Problem | Auto-fix |
|---|---|
| SSH key rejected by laptop | Reinstall server's `claude_laptop.pub` into `authorized_keys` and retry |
| Windows sshd stopped | `Start-Service sshd` with up-to-20s readiness wait |
| Windows OpenSSH Server not installed | `Add-WindowsCapability` install; fallback to `winget`; Windows Update service auto-started if needed |
| Windows firewall SSH rule missing/disabled | `New-NetFirewallRule` / `Enable-NetFirewallRule` (Profile Any enforced) |
| Stale SSHFS mount | `claude-mount recover` before each `up` |
| Cursor login despite auth ok (Mac) | Soft-stop server profile after auth; write `machineid`; require full remote path for folder match |
| Mac SSH allow-list blocked | Remove user from `com.apple.access_ssh-disabled`; add to `com.apple.access_ssh` |
| Tunnel drops during session | Auto-reconnect loop; editor not re-opened on reconnect |
| SSH permission errors (Windows) | `icacls` fixes on `.ssh/`, `authorized_keys`, `config`, `administrators_authorized_keys` |
| sshd restart kills tunnel | Re-check `Test-Tunnel` before retrying mount after forced restart |
| macOS Remote Login OFF | `systemsetup -setremotelogin on` + 10s wait for sshd to accept connections |
| Git hide fails (Cursor lock) | Retry rename 3×; stop git.exe on attempt 2; warn user; `G` remount |
| GIT_MODE=server selected | Skip claude-git-setup mirror; `.git` visible on SSHFS (slow) |
| Stale foreign `LAPTOP_USER` in conf (tunnel port down) | Clear `~/.claude-connect.conf` and continue |
| Mac/Windows-incompatible mount `rpath` | Purge incompatible `~/.claude-mounts.d/*.conf` entries |
| Laptop SSH auth failure (Mac) | `diagnose_laptop_ssh_failure` uploads diag to server `~/.claude/logs/` |
| Multi-agent “everyone blocked” | Ensure project `hooks.json` empty; user hooks use wrap; no Shell in `preToolUse`; slots/mux healthy; Task prompts force laptop-exec |
| Tunnel flapping / MaxStartups | Stop concurrent SSH storms; `connect` raises MaxSessions/MaxStartups; do not stress-test tunnel |
| Guard syntax error locking tools | Wrap fail-opens; fix guard; never point hooks at raw guard without wrap |
| Project hooks refilled | `laptop-exec-setup` must write empty project hooks only; re-empty `~/mounts/*/.cursor/hooks.json` |
| Mac admin password prompts | At most once per run (45s timeout); skip Remote Login cycle if already on |

## Client Regression Tests

Location: `scripts/client/tests/`

```bat
scripts\client\tests\run-all.bat
```

| Script | Purpose |
|---|---|
| `test-pipeline-deep.ps1` | PowerShell pipeline semantics |
| `test-pipeline-repro.ps1` | Join-Path bug reproduction |
| `test-select-project.ps1` | Post-select capture pattern |
| `test-connect-pipeline.ps1` | connect.ps1 invariants |
| `test-git-mode-deep.ps1` | GIT_MODE client + server |
| `test-editor-launch.ps1` | Editor CLI on PATH |
| `audit-local-connect.ps1` | Find stale connect.ps1 copies on laptop |

Shared helpers: `tests/_paths.ps1`. Full guide: [`docs/client-connect.md`](docs/client-connect.md).

## Publish Workflow

Run on **smart's Windows laptop** to build distributable packages:

```
publish\publish.bat
```

Outputs to `Desktop\claude-publish\`:

| Package | Contents | Notes |
|---|---|---|
| `claude-code-client-YYYYMMDD.zip` | `windows/` + `mac/` + `README.txt` | Smart IP `192.168.210.240`; client only - **no `server/`** |
| `claude-code-sepidz-YYYYMMDD.zip` | `claude-code/` + `designer/` + READMEs | Sepidz IP `192.168.250.70`; scripts IP-patched; README from `README-sepidz.txt` |

**Client-only rule:** Published ZIPs must never contain `server/`, `deploy-mount-fix.sh`, or `deploy-server-mount-fix.*`. Server deploy runs from repo `scripts/client/deploy-server-mount-fix.bat` (admin, smart laptop).

**IP patching (Sepidz package only):** `publish.ps1` replaces `192.168.210.240 -> 192.168.250.70` in `connect.ps1`, `connect.sh`, and designer connect scripts. Package READMEs stay separate (`publish/README.txt` vs `publish/README-sepidz.txt`). Logging policy is the same on both sites. No separate alias, cfg dir, or port base.

**Sepidz package structure:**
```nclaude-code-sepidz-YYYYMMDD/
  claude-code/          # windows/ + mac/ (IP patched) + README.md from README-sepidz.txt
  designer/             # designer scripts (IP patched) + README.md
```

## Designer: Chrome Download Directory

Chrome is configured via **managed policy** (not Preferences) so the setting survives Chrome restarts:

```
/etc/opt/chrome/policies/managed/designer-download.json
DownloadDirectory = /home/designer/mounts/laptop
```

**Gotcha:** Do NOT edit Chrome Preferences directly — Chrome overwrites them on close.
The managed policy is set automatically by `install.sh`.
After running deploy, designer must disconnect/reconnect once for Chrome to pick it up.

## Removed Legacy Scripts

These were deleted from the repo — use `claude-server` instead:

| Old (removed) | Replacement |
|---|---|
| `server-setup.sh` | `claude-server install` |
| `setup-new-user.sh` | `claude-server add-user <name>` |
| `install-designer-deps.sh` | part of `claude-server install` |
| `setup-designer.sh` | part of `claude-server install` |
| `check-users.sh` | `claude-server verify` |
| `deploy-fixes.sh` | `claude-server install` (idempotent) |
