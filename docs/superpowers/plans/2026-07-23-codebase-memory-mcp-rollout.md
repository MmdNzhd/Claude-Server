# Fleet-Wide codebase-memory-mcp Rollout (Replace codegraph) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unused `codegraph` MCP server with `codebase-memory-mcp` for every real developer account on this server (current users + future via `add-user.sh`), safely and reversibly.

**Architecture:** Per-user binary install at `~/.local/bin/codebase-memory-mcp` (vendor's own `install.sh`, which downloads, SHA-256-verifies, extracts, and auto-configures Claude Code + Cursor MCP entries and hooks). `codegraph` is removed first via its own `uninstall -y` command. `add-user.sh` and `CLAUDE.md` are updated in the actual repo (via `laptop-exec`, never direct Write/Edit on `/mounts/`) so new users get `codebase-memory-mcp` instead of `codegraph` going forward.

**Tech Stack:** Bash, `sudo-from-laptop --smart` (root ops, no manual password), `laptop-exec` (repo edits), vendor CLIs (`codegraph`, `codebase-memory-mcp`).

## Global Constraints

- Replace `codegraph` entirely — remove from every current user's configs AND from `add-user.sh` (per user decision: scope=replace).
- Install per-user (`~/.local/bin/codebase-memory-mcp`), not a shared system-wide binary (per user decision: binary_location=per_user).
- Allow `codebase-memory-mcp`'s auto-installed Claude Code hooks (`PreToolUse` Grep/Glob, `SessionStart`, `SubagentStart`) — do not strip them (per user decision: hooks=with_hooks).
- Never touch `/mounts/` with Read/Write/Edit/Grep/Glob/heavy-Shell — repo file edits go through `laptop-exec write` with `-p claude-code-server`.
- Never prompt for or use a manually-pasted sudo password — all root ops via `sudo-from-laptop --smart -- ...`.
- Project-level `hooks.json` must remain `{"version":1,"hooks":{}}` for every project after this change (spot-check, do not regress).
- Pin the exact version installed (record `codebase-memory-mcp --version` output actually installed) so all 19 accounts converge on the same build.
- Real target user list (UID 1000-1018, confirmed via `/etc/passwd`): `administrator mohammad smart hamed aria amirhossein amir mehrdad parsa reza kiana hamed.kh testuser2 tarane mahdie designer danial fateme pouyan` (19 accounts, `smart` already partially migrated).
- `parsa` and `pouyan` currently have a live VS Code Remote-SSH session (unrelated tool) — this plan does not touch `.vscode-server`; only a courtesy note not to run this rollout's steps for them in a way that kills unrelated sessions (installer only touches `.claude*`, `.cursor/mcp.json`, `~/.local/bin` — does not restart their editor process, so this is inherently safe, but call it out in Task 3 admit check anyway).

## Evidence Refs

- `GetMcpTools` catalog at session start: no `codebase-memory-mcp` *or* `codegraph` server was ever exposed to this Cursor agent — confirms `codegraph` was never wired into `~/.cursor/mcp.json` for `smart`.
- `codegraph status` on `/home/smart/mounts/claude-code-server`: only 1 file / 31 nodes indexed for a repo with dozens of scripts; `codegraph daemon` reported "No CodeGraph daemons running" — confirms `codegraph` is not actively used even where installed.
- Sample check across 19 real accounts (`python3 -c 'json...' /home/$u/.claude/settings.json`): `codegraph` present for 15/19 (`mohammad hamed aria amirhossein amir mehrdad parsa reza kiana hamed.kh tarane mahdie danial fateme pouyan smart` = yes; `testuser2 designer administrator` = no / no settings file).
- Live test of `codebase-memory-mcp` v0.9.0 on `/home/smart/claude-code-server-git` (real local git clone, 1132 nodes / 2318 edges): `get_architecture`, `trace_path`, and a raw Cypher dead-code query all returned correct, useful results in seconds.
- Known vendor quirk (observed directly): `install.sh --skip-config` does **not** suppress agent auto-configuration — the binary's own `install` subcommand writes `~/.cursor/mcp.json`, `~/.claude.json`, `~/.claude/.mcp.json`, and 3 Claude Code hooks regardless. This plan accepts that behavior (user chose `with_hooks`) rather than fighting it.
- Disk headroom after the July 23 cleanup: 78 GB free (was 6.8 GB). Binary is 258 MB/user; 19 users ≈ 4.9 GB — well within budget.
- `codegraph uninstall -y` (checked via `--help`): non-interactive, defaults to `--location=global --target=all` — safe for scripted removal.
- **Architecture correction (confirmed by direct inspection, not assumption):** `codegraph` is installed exactly **once, globally**, as `npm install -g @colbymchenry/codegraph` in `scripts/server/commands/install.sh` Step 9 (`/usr/lib/node_modules/@colbymchenry/codegraph`, symlinked `/usr/bin/codegraph` <- `/usr/local/bin/codegraph`, version `1.0.1` on this server). `scripts/server/commands/add-user.sh` never runs a per-user codegraph install — it only writes a static `"codegraph": {"command":"codegraph",...}` JSON block into each new user's `settings.json` template, pointing at that one shared PATH binary. Also found stray root-owned artifacts: `/root/.local/bin/codegraph`, `/root/.codegraph` (root's own project index — root is not one of the 19 real dev accounts and is out of scope for per-user config changes, but the stray global package/binary is in scope for cleanup).

## Anti-Patterns / Hard Rejects

- Do NOT run any installer/uninstaller interactively (always pass `-y`/`--force`/non-interactive flags) — this runs unattended across 19 accounts.
- Do NOT edit `add-user.sh` or `CLAUDE.md` with direct Write/Edit/StrReplace on `/mounts/` — use `laptop-exec write -p claude-code-server`.
- Do NOT skip the vendor's checksum verification — always use the official `install.sh` (already reviewed, mandatory SHA-256 check), never a hand-rolled download.
- Do NOT leave a project's `hooks.json` non-empty as a side effect — `codebase-memory-mcp` only writes user-level `~/.claude/settings.json` and `~/.cursor/mcp.json`, never project `hooks.json`; verify this holds after rollout.
- Do NOT delete a user's pre-existing customizations blindly — snapshot each touched config file before mutation (Task 1) so any single user can be rolled back.
- Do NOT forget the "Sync Rule for Server Scripts" — after editing `scripts/server/commands/add-user.sh`, `sudo claude-server install` must be re-run so `/usr/local/lib/claude-server/` gets the updated copy; otherwise live `claude-server add-user` keeps using the stale version.

## Admit Criteria

- [ ] For every one of the 19 accounts: `~/.claude/settings.json` / `~/.claude.json` no longer contains a `codegraph` key under `mcpServers`, and does contain `codebase-memory-mcp`.
- [ ] For every one of the 19 accounts: `~/.cursor/mcp.json` contains `codebase-memory-mcp` and does not contain `codegraph`.
- [ ] For every one of the 19 accounts: `~/.local/bin/codebase-memory-mcp --version` runs successfully and reports the same pinned version.
- [ ] No live editor/session process was killed or errored as a side effect (spot-check `ps aux` for `parsa`/`pouyan`/`amir`/`aria` before and after; all pre-existing PIDs for `cursor-server`/`vscode-server` still alive after the run).
- [ ] `scripts/server/commands/install.sh` no longer has a "Step 9 - CodeGraph" global install block.
- [ ] `scripts/server/commands/add-user.sh` no longer references `codegraph` anywhere; it now runs a per-user `codebase-memory-mcp` install (pinned version, official `install.sh`, no interactive prompts) for every newly-added account, and its `settings.json` template no longer has a static `codegraph` (or `codebase-memory-mcp`) `mcpServers` entry.
- [ ] `CLAUDE.md` "MCP Servers (installed per-user via add-user.sh)" table row for `codegraph` is replaced with `codebase-memory-mcp`.
- [ ] The global `codegraph` npm package is uninstalled server-wide (`command -v codegraph` fails).
- [ ] `sudo claude-server install` re-run after the `install.sh`/`add-user.sh` edits (per Sync Rule table), confirmed idempotent/no errors.
- [ ] A couple of projects' `hooks.json` spot-checked and still exactly `{"version":1,"hooks":{}}`.
- [ ] Repo changes committed via `laptop-exec git -p claude-code-server` with a clear commit message; diff reviewed before commit.

---

### Task 1: Snapshot current per-user MCP/settings state (rollback safety net)

**Files:** none in repo — writes backups under `/root/cbm-rollout-backup-<date>/` on the server (root-owned, outside any user home, outside `/mounts/`).

- [ ] **Step 1: Back up every touched config file for all 19 users**

```bash
sudo-from-laptop --smart -- bash -c '
BK=/root/cbm-rollout-backup-2026-07-23
mkdir -p "$BK"
USERS="administrator mohammad smart hamed aria amirhossein amir mehrdad parsa reza kiana hamed.kh testuser2 tarane mahdie designer danial fateme pouyan"
for u in $USERS; do
  h="/home/$u"
  mkdir -p "$BK/$u"
  for f in .claude/settings.json .claude.json .claude/.mcp.json .cursor/mcp.json; do
    [ -f "$h/$f" ] && cp --parents -a "$h/$f" "$BK/$u/" 2>/dev/null || true
  done
done
echo "backup complete:"; find "$BK" -type f | wc -l
'
```

Expected: prints a file count > 0 (backups for whichever of the 4 files existed per user).

- [ ] **Step 2: Verify backup readability**

```bash
sudo-from-laptop --smart -- bash -c 'find /root/cbm-rollout-backup-2026-07-23 -name "settings.json" | head -3 | xargs -I{} python3 -c "import json,sys; json.load(open(sys.argv[1])); print(sys.argv[1], \"OK\")" {}'
```

Expected: `OK` printed for each sampled file (valid JSON, readable).

---

### Task 2: Remove `codegraph` from the 15 accounts that have it

**Files:** none in repo — mutates `~/.claude/settings.json` / `~/.claude.json` / `~/.cursor/mcp.json` per user via the vendor's own `codegraph uninstall`.

- [ ] **Step 1: Run `codegraph uninstall -y` for the 15 affected accounts**

```bash
sudo-from-laptop --smart -- bash -c '
CG_USERS="mohammad hamed aria amirhossein amir mehrdad parsa reza kiana hamed.kh tarane mahdie danial fateme pouyan smart"
for u in $CG_USERS; do
  echo "=== $u ==="
  su - "$u" -c "codegraph uninstall -y" 2>&1 | tail -5
done
'
```

Expected: each user prints an uninstall summary (no fatal errors). `testuser2`, `designer`, `administrator` are skipped (never had it).

- [ ] **Step 2: Confirm removal**

```bash
sudo-from-laptop --smart -- bash -c '
for u in mohammad hamed aria amirhossein amir mehrdad parsa reza kiana hamed.kh tarane mahdie danial fateme pouyan smart; do
  f="/home/$u/.claude/settings.json"
  [ -f "$f" ] && python3 -c "import json; d=json.load(open(\"$f\")); print(\"$u:\", \"codegraph\" in d.get(\"mcpServers\",{}))"
done
'
```

Expected: `False` for every user.

- [ ] **Step 3: Remove the global `codegraph` npm package + stray root artifacts (server-wide, one-time cleanup)**

```bash
sudo-from-laptop --smart -- bash -c '
npm uninstall -g @colbymchenry/codegraph 2>&1 | tail -5
rm -rf /root/.local/bin/codegraph /root/.codegraph
echo "codegraph on PATH now:"; command -v codegraph || echo "gone (expected)"
'
```

Expected: `npm uninstall -g` reports removal; final `command -v codegraph` prints nothing (or "gone (expected)") — confirms the shared binary is fully removed, not just unlinked from configs.

---

### Task 3: Install `codebase-memory-mcp` for all 19 accounts

**Files:** none in repo — creates `~/.local/bin/codebase-memory-mcp` and mutates the same config files per user via the vendor's official `install.sh`.

- [ ] **Step 1: Run the official installer as each user (no `--skip-config` — hooks are wanted)**

```bash
sudo-from-laptop --smart -- bash -c '
ALL_USERS="administrator mohammad smart hamed aria amirhossein amir mehrdad parsa reza kiana hamed.kh testuser2 tarane mahdie designer danial fateme pouyan"
for u in $ALL_USERS; do
  echo "=== $u ==="
  su - "$u" -c "curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash" 2>&1 | tail -15
done
'
```

Expected: each user shows `Checksum verified.` and `Installed: codebase-memory-mcp 0.9.0` (or later pinned version — record actual).

- [ ] **Step 2: Verify binary + version consistency**

```bash
sudo-from-laptop --smart -- bash -c '
for u in administrator mohammad smart hamed aria amirhossein amir mehrdad parsa reza kiana hamed.kh testuser2 tarane mahdie designer danial fateme pouyan; do
  v=$(su - "$u" -c "~/.local/bin/codebase-memory-mcp --version" 2>&1)
  echo "$u: $v"
done
'
```

Expected: identical version string for all 19 users, no errors.

- [ ] **Step 3: Verify no live session was disrupted**

```bash
sudo-from-laptop --smart -- bash -c 'ps aux | grep -E "cursor-server|vscode-server" | grep -v grep | wc -l'
```

Expected: same or higher process count than before Task 3 Step 1 (no drop — nothing was killed).

---

### Task 4: Verify Cursor + Claude Code wiring per account

**Files:** none in repo — read-only verification.

- [ ] **Step 1: Confirm `codebase-memory-mcp` present and `codegraph` absent in both config surfaces, all 19 users**

```bash
sudo-from-laptop --smart -- bash -c '
ALL_USERS="administrator mohammad smart hamed aria amirhossein amir mehrdad parsa reza kiana hamed.kh testuser2 tarane mahdie designer danial fateme pouyan"
for u in $ALL_USERS; do
  cj="/home/$u/.cursor/mcp.json"
  sj="/home/$u/.claude/settings.json"
  cb=$( [ -f "$cj" ] && python3 -c "import json; d=json.load(open(\"$cj\")); print(\"cbm\" if \"codebase-memory-mcp\" in d.get(\"mcpServers\",{}) else \"MISSING\", \"cg\" if \"codegraph\" in d.get(\"mcpServers\",{}) else \"clean\")" || echo "no-cursor-mcp-json")
  echo "$u cursor: $cb"
done
'
```

Expected: `cbm clean` for every user (present + codegraph gone). Any `MISSING` or leftover `codegraph` fails this task — re-run the relevant Task 2/3 step for that user only.

- [ ] **Step 2: Confirm the 3 expected Claude Code hooks exist for at least 2 sample users (spot check, since `with_hooks` was chosen)**

```bash
sudo-from-laptop --smart -- bash -c '
for u in smart amir; do
  python3 -c "
import json
d = json.load(open(\"/home/$u/.claude/settings.json\"))
pre = [h for h in d.get(\"hooks\",{}).get(\"PreToolUse\",[]) if h.get(\"matcher\")==\"Grep|Glob\"]
print(\"$u PreToolUse Grep|Glob hook:\", bool(pre))
print(\"$u SessionStart hooks:\", len(d.get(\"hooks\",{}).get(\"SessionStart\",[])))
print(\"$u SubagentStart hooks:\", len(d.get(\"hooks\",{}).get(\"SubagentStart\",[])))
"
done
'
```

Expected: `True` and non-zero counts for both sampled users.

- [ ] **Step 3: Spot-check a project `hooks.json` is still empty (regression guard)**

```bash
laptop-exec read -p claude-code-server .cursor/hooks.json
```

Expected: exactly `{"version":1,"hooks":{}}` (or file absent, which is equally fine — never non-empty).

---

### Task 5: Remove the global `codegraph` install step from `install.sh`

**Files:**
- Modify: `scripts/server/commands/install.sh` (delete the "Step 9 - CodeGraph" block, ~9 lines, immediately before "Step 10: Headroom")

**Ground truth (confirmed by reading the file, not assumed):** the block to delete is exactly:
```bash
# --- Step 9: CodeGraph (code intelligence MCP) ------------------------------
step "9 - CodeGraph"
if command -v codegraph &>/dev/null; then
    ok "CodeGraph: already installed ($(codegraph --version 2>/dev/null || echo 'ok'))"
else
    curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh
    ok "CodeGraph installed"
fi

```
immediately followed by the existing `# --- Step 10: Headroom ...` block (keep Step 10 untouched, just remove the Step 9 block above it). Because `codebase-memory-mcp` is per-user (Task 3/6), it has no equivalent global-install step to add here — this task only removes the old one.

- [ ] **Step 1: Confirm current line range**

```bash
laptop-exec rg -p claude-code-server 'Step 9: CodeGraph' scripts/server/commands/install.sh
```

Expected: 1 match, confirming the block still starts with this exact comment.

- [ ] **Step 2: Fetch the file, delete the block, write it back**

```bash
laptop-exec read -p claude-code-server scripts/server/commands/install.sh
```

Remove the 9-line block shown in "Ground truth" above from the fetched content (leave everything else, including Step 10, byte-identical), then:

```bash
laptop-exec write -p claude-code-server scripts/server/commands/install.sh <<'EOF'
<full updated file content, Step 9 block removed>
EOF
```

- [ ] **Step 3: Verify**

```bash
laptop-exec rg -p claude-code-server 'CodeGraph|codegraph' scripts/server/commands/install.sh
```

Expected: no matches (exit code `1`).

---

### Task 6: Update `add-user.sh` — swap the static `codegraph` JSON entry for a per-user `codebase-memory-mcp` install step

**Files:**
- Modify: `scripts/server/commands/add-user.sh`

**Ground truth (confirmed by reading the file — exact names, do not re-derive):**
- The user-name variable is `$USERNAME` (set via `useradd -m -s /bin/bash "$USERNAME"` at line 53), **not** `$NEWUSER`.
- Helper functions already defined at the top of the file: `ok() { echo -e "  ${GREEN}+${NC} $1"; }`, `warn() { echo -e "  ${YELLOW}!${NC} $1"; }`, `step() { echo -e "\n${BOLD}=== $1 ===${NC}"; }`.
- The `settings.json` heredoc template is written in "Step 4 - Claude settings + hooks" (`step "4 - Claude settings + hooks"`); the block to delete is at lines 176-180:
  ```json
      "codegraph": {
        "type": "stdio",
        "command": "codegraph",
        "args": ["serve", "--mcp"]
      },
  ```
  (the following entry is `"headroom": {...}` at line 181 — leave it and everything else in the template untouched).
- Step 4 finishes with `chown "$USERNAME:$USERNAME" "/home/$USERNAME/.claude/settings.json"` followed by `ok "~/.claude/settings.json written"` (lines 216-217), then the very next step is `step "5 - SSH"` (line 253). **Insert the new install step between these two** — `.claude` is fully written and owned by `$USERNAME` by then, and `useradd` (Step 1) has already run, so `su - "$USERNAME"` resolves a valid `$HOME`.

- [ ] **Step 1: Fetch the current file**

```bash
laptop-exec read -p claude-code-server scripts/server/commands/add-user.sh
```

- [ ] **Step 2: Apply the edit locally, then push**

In the fetched content:
1. Delete the 5-line `"codegraph": {...}` block shown above from the `settings.json` template. Do **not** add a replacement static block for `codebase-memory-mcp` — its own installer writes `~/.claude.json` / `~/.claude/.mcp.json` / `~/.cursor/mcp.json` itself (same auto-config behavior already verified in Task 3), so a static template entry would be redundant and could drift from what the installer actually writes.
2. Insert this new step immediately after `ok "~/.claude/settings.json written"` (Step 4's last line) and before `step "5 - SSH"`:
   ```bash
   step "4b - codebase-memory-mcp"
   su - "$USERNAME" -c "curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash" > /tmp/cbm-install-$USERNAME.log 2>&1        && ok "codebase-memory-mcp installed for $USERNAME"        || warn "codebase-memory-mcp install failed for $USERNAME - see /tmp/cbm-install-$USERNAME.log, or run manually: su - $USERNAME -c "curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash""
   ```

Push:
```bash
laptop-exec write -p claude-code-server scripts/server/commands/add-user.sh <<'EOF'
<full updated file content>
EOF
```

- [ ] **Step 3: Verify**

```bash
laptop-exec rg -p claude-code-server 'codegraph' scripts/server/commands/add-user.sh
```
Expected: no matches (exit code `1`).

```bash
laptop-exec rg -p claude-code-server 'codebase-memory-mcp' scripts/server/commands/add-user.sh
```
Expected: 1+ match (the new install step).

---

### Task 7: Update `CLAUDE.md` MCP Servers table

**Files:**
- Modify: `CLAUDE.md` (the "MCP Servers (installed per-user via add-user.sh)" table)

- [ ] **Step 1: Locate the current table row**

```bash
laptop-exec rg -p claude-code-server 'codegraph' CLAUDE.md
```

Expected: 1 match — the table row `| \`codegraph\` | Code knowledge graph — fewer tool calls, cheaper sessions | step 9 in \`install.sh\` |` and the `codegraph init` mention under "CodeGraph per-project indexing".

- [ ] **Step 2: Replace the row and the per-project-indexing note**

Fetch current `CLAUDE.md` via `laptop-exec read -p claude-code-server CLAUDE.md`, replace:
```markdown
| `codegraph` | Code knowledge graph — fewer tool calls, cheaper sessions | step 9 in `install.sh` |
```
with:
```markdown
| `codebase-memory-mcp` | Code knowledge graph — fewer tool calls, cheaper sessions (158-language tree-sitter + Hybrid LSP, replaced `codegraph` 2026-07-23 — see `docs/superpowers/plans/2026-07-23-codebase-memory-mcp-rollout.md`) | official `install.sh`, run per-user by `add-user.sh` |
```
and replace the `codegraph init` manual-trigger note:
```markdown
**CodeGraph per-project indexing** — runs automatically on login via `claude-automount`. Manual trigger:
```bash
codegraph init # run inside project dir if .codegraph/ is missing
```
```
with:
```markdown
**codebase-memory-mcp indexing** — not auto-triggered on login (unlike the old codegraph). Manual trigger inside a project:
```bash
codebase-memory-mcp cli index_repository --repo-path "$(pwd)"
```
```

Push via `laptop-exec write -p claude-code-server CLAUDE.md <<'EOF' ... EOF`.

- [ ] **Step 3: Verify**

```bash
laptop-exec rg -p claude-code-server 'codebase-memory-mcp' CLAUDE.md
```

Expected: 2+ matches (table row + indexing note).

---

### Task 8: Redeploy + commit

**Files:** none new — deploy + git operations only.

- [ ] **Step 1: Re-run `claude-server install` so `/usr/local/lib/claude-server/` picks up the new `add-user.sh`** (per "Sync Rule for Server Scripts": `scripts/server/commands/add-user.sh` changes require this)

```bash
sudo-from-laptop --smart -- claude-server install 2>&1 | tail -30
```

Expected: completes without error (idempotent install).

- [ ] **Step 2: Review the full diff before committing**

```bash
laptop-exec git -p claude-code-server -- diff
```

Expected: shows only the intended changes to `scripts/server/commands/add-user.sh` and `CLAUDE.md`.

- [ ] **Step 3: Commit and push**

```bash
laptop-exec git -p claude-code-server -- add scripts/server/commands/add-user.sh scripts/server/commands/install.sh CLAUDE.md docs/superpowers/plans/2026-07-23-codebase-memory-mcp-rollout.md
laptop-exec git -p claude-code-server -- commit -m "Replace unused codegraph MCP server with codebase-memory-mcp fleet-wide

- Removed codegraph (never wired into Cursor, near-empty index, no daemon
  running) from all 15 accounts that had it, plus the global npm package
  and stray root artifacts.
- Installed codebase-memory-mcp v0.9.0 for all 19 real accounts via the
  official install.sh (checksum-verified), including its Claude Code hooks.
- install.sh: removed the old global 'Step 9 - CodeGraph' install.
- add-user.sh: removed the static codegraph settings.json entry; added a
  per-user codebase-memory-mcp install step for new accounts.
- Updated CLAUDE.md MCP Servers table + indexing instructions.

See docs/superpowers/plans/2026-07-23-codebase-memory-mcp-rollout.md for the
full evidence trail and rollback backups (/root/cbm-rollout-backup-2026-07-23
on the server)."
laptop-exec git -p claude-code-server -- push
```

Expected: clean push, no conflicts.

---

## Rollback

**Per-user (config only):** restore the account's 4 config files from `/root/cbm-rollout-backup-2026-07-23/<user>/` (Task 1 backup), then `su - <user> -c "~/.local/bin/codebase-memory-mcp uninstall -y"` to cleanly remove the new hooks/config.

**Full revert to codegraph (only if actually desired — unlikely given the evidence in this plan):** the global npm package was removed in Task 2 Step 3, so first `sudo-from-laptop --smart -- npm install -g @colbymchenry/codegraph`, restore the backed-up config files, then re-run `codegraph install -y` for the affected account(s). Also revert the `install.sh`/`add-user.sh`/`CLAUDE.md` edits via `laptop-exec git -p claude-code-server -- revert <commit>` (or `git checkout <prev-commit> -- <files>`) if Task 8 was already pushed.
