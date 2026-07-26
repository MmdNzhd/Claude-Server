# claude-server CLI — Design Spec

**Date:** 2026-06-15
**Status:** Approved

---

## Goal

A single CLI tool (`claude-server`) that manages installation, user management, verification, and Claude Code server status in one place. It installs on a new server with one command, and all admin operations run through the same CLI afterward.

---

## Bootstrap (initial install)

```bash
git clone <repo>
cd claude-code-server
sudo bash scripts/server/claude-server install
```

This command:
1. Installs all system dependencies
2. Installs the Claude Code CLI
3. Deploys the wrapper and hooks
4. Installs designer dependencies (Xvfb, x11vnc, noVNC, Chrome)
5. Creates the `designer` user
6. Creates the admin user `smart`
7. Installs `claude-server` itself to `/usr/local/bin/claude-server`

After bootstrap, from anywhere:
```bash
claude-server <command> [options]
```

---

## File layout

```
scripts/server/
├── claude-server              <- dispatcher (installed to /usr/local/bin)
├── commands/
│   ├── install.sh             <- full server install (replaces server-setup.sh + install-designer-deps.sh + setup-designer.sh)
│   ├── add-user.sh            <- create developer user (replaces setup-new-user.sh)
│   ├── verify.sh              <- test all components (replaces check-users.sh)
│   └── status.sh              <- current status (sessions + usage)
├── hooks/
│   ├── claude-hook-pre.sh
│   ├── claude-hook-stop.sh    <- includes STATS logging (per-user tokens)
│   └── claude-hook-logout-block.sh
├── claude-wrapper.sh
├── claude-limits.conf
├── check-tokens.py            <- detailed token report (requires sudo)
└── check-usage.sh             <- prompt count report from log
```

> **Rule:** Any change in any file under this folder must also be reflected in `commands/install.sh` or `commands/add-user.sh`.

---

## Subcommands

### `claude-server install`

Full install on a fresh server. Idempotent — safe to re-run.

**Steps:**
1. Check for root
2. `apt-get update` + install deps: `sshfs curl git python3 xvfb x11vnc fluxbox autocutsel websockify novnc`
3. Install Node.js LTS (if missing)
4. Install Claude Code: `npm install -g @anthropic-ai/claude-code`
5. `claude-real` symlink
6. wrapper -> `/usr/local/bin/claude`
7. hooks -> `/usr/local/bin/claude-hook-*`
8. `claude-automount`, `claude-git-setup`, `claude-mount` -> `/usr/local/bin/` and `/usr/local/lib/`
9. `/etc/claude-limits.conf`
10. `/var/run/claude-active` (chmod 1777)
11. `/var/log/claude-activity.jsonl` (touch + chmod 666)
12. Install Chrome (if missing)
13. User `designer` + setup
14. User `smart` + sudo
15. Enable SSH forwarding
16. `claude-server` itself -> `/usr/local/bin/claude-server`
17. Show next command (token setup)

---

### `claude-server add-user <username>`

```bash
claude-server add-user amir
claude-server add-user parsa --no-password-change
```

**Steps:**
1. Check for root
2. useradd (if missing)
3. Create `/home/<user>/work`
4. `chmod 700 /home/<user>`
5. Install `~/.local/bin/claude-mount`
6. Install `~/.local/bin/claude-git-setup`
7. Write `~/.claude/settings.json` (with full hooks)
8. Prepare `~/.ssh/authorized_keys`
9. Add auto-mount hook to `.bashrc`
10. `chage -d 0` (force password change on first login)

**Options:**
- `--no-password-change` — skip forced password change

---

### `claude-server verify`

Test all components. Exit code 0 = healthy, 1 = problem.

**Checks:**
- `claude-real --version` works
- `/usr/local/bin/claude` symlink/wrapper exists
- `/usr/local/bin/claude-hook-*` all installed and executable
- `/etc/claude-limits.conf` exists
- `/var/run/claude-active` exists and is writable
- `/var/log/claude-activity.jsonl` exists and is writable
- `designer-start status` OK
- For each human user: hooks in settings.json, automount in .bashrc, `claude-mount` installed

Colored output like the current `check-users.sh`.

---

### `claude-server status`

```
=== Claude Server Status ===

Active sessions: 3
  aria.12345.active
  amir.23456.active
  smart.34567.active

=== Usage (last 7 days) ===
  User          Prompts  Sessions  Last active
  aria               13        11  2026-06-15 07:09
  ...

=== Token Usage (from stats cache) ===
  smart          3.8M out   $281.20   7,682 msgs
  hamed.kh       1.3M out   $107.68   2,893 msgs
```

---

### `claude-server --help`

```
Usage: claude-server <command> [options]

Commands:
  install              full server install (must be root)
  add-user <name>      add a new developer user
  verify               test all components
  status               current sessions and usage

Options:
  --help               this help
  --version            version

Examples:
  sudo claude-server install
  sudo claude-server add-user amir
  claude-server verify
  claude-server status
```

---

## Documentation maintenance

Docs files that must be updated:
- `docs/claude-design.md` — designer guide; should also document `designer-start` commands from `claude-server`
- `README.md` (if created) — quick install

---

## Maintenance rules

> Whenever a hook, script, or config changes, `commands/install.sh` and `commands/add-user.sh` must be updated to deploy the change.

This rule must also be documented in `CLAUDE.md`.

---

## Legacy scripts

After implementation, these files are deprecated (not deleted):

| Legacy | Replacement |
|--------|-------------|
| `server-setup.sh` | `claude-server install` |
| `setup-new-user.sh` | `claude-server add-user` |
| `install-designer-deps.sh` | part of `claude-server install` |
| `setup-designer.sh` | part of `claude-server install` |
| `check-users.sh` | `claude-server verify` |
| `deploy-fixes.sh` | `claude-server install` (idempotent) |
