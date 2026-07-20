# FIX-MOUNT-SEC — mount + security leftovers

Date: 2026-07-20  
Project: `-p claude-code-server` (laptop-exec only)  
Deploy: **NO**

## Overall

**PASS** (5/5 in-scope items)

Out of scope residual: security HARD suite CHECK 5 (`git-mode.sh` askpass embeds admin password in `echo` cmdline) — not in this task list.

## Checklist

| # | Item | Result | Evidence |
|---|------|--------|----------|
| 1 | `claude-watchdog.sh`: restore `.git` from `.git.server-session` on tunnel DOWN | **PASS** | DOWN branch calls `"$MOUNT_BIN" down` before fallback umount. `_restore_git` best-effort when TCP still open (ConnectTimeout-bounded); full dead tunnel → recover on reconnect. |
| 2a | `claude-mount.sh` / automount / watchdog: no first-alphabetical `ACTIVE_MOUNT` when empty | **PASS** | No `ACTIVE_MOUNT="$_id"` alphabetical fallback; comments + `_infer_active` / LAST_ACTIVE-only paths. |
| 2b | CR strip `TUNNEL_PORT` in mount load | **PASS** | `_load_global`: `tr -d '\r'` on conf values. |
| 2c | Don't delete real `.git` unsafely | **PASS** | Restore skips real `.git` dir (+ HEAD); only removes worktree pointer (`PathType Leaf` / `-f`). No `Remove-Item -Recurse` on `.git`. |
| 3 | `publish/Get-DeployCredentials.ps1`: no hardcoded `sepidz@Admin` assignment | **PASS** | Throws when password missing (`No hardcoded fallback is allowed`). No `sepidz@Admin` literal. Example `$…SudoPassword = '...'` in throw text only. |
| 4 | `add-user.sh`: no real SQL password in template | **PASS** | `"SQLSERVER_PASSWORD": "CHANGE_ME"` |
| 5 | OAuth / golden perms in install (+ refresh residual) | **PASS** | `install.sh`: golden dir `0700`, `chmod 600 golden/*`, `/etc/claude-code` `0700` + `oauth.env` `0600`. `cursor-auth-refresh.sh` was still writing `0o644` / dir `0o755` — **fixed this pass** → `0o600` / `0o700`. Export already `700`/`600`. |

## Fixes applied this pass

| File | Change |
|------|--------|
| `scripts/server/claude-mount.sh` | `_restore_git`: if full tunnel probe fails, still try when TCP open (watchdog DOWN race); skip immediately if TCP closed (no multi-project SSH hang). |
| `scripts/server/claude-watchdog.sh` | Clarify DOWN path: `claude-mount down` restores when TCP briefly reachable. |
| `scripts/server/cursor-auth-refresh.sh` | Golden writes `mode=0o600`; `GOLDEN_DIR` `chmod 0o700` (was 644/755 — re-poisoned every 6h). |
| `scripts/server/commands/install.sh` | `chmod 600` existing golden files; ensure `/etc/claude-code` `0700` + `oauth.env` `0600`. |
| `scripts/server/test-cursor-auth-lib.py` | Expect golden dir `700` / `auth.json` `600` (was WARN 755/644). |

## Verification

```
test-mount-contracts.ps1     → HARD PASS (6/6)
test-security-contracts.ps1  → CHECK 1–4 PASS; CHECK 5 FAIL (askpass, out of scope); CHECK 6 PASS
bash -n claude-mount.sh      → OK
bash -n claude-watchdog.sh   → OK
bash -n install.sh           → OK
```

## Leftover (not this task)

- Mac `git-mode.sh` askpass: password on `echo` process cmdline (security HARD CHECK 5).
- Live hosts still need deploy/export/refresh for on-disk modes to change (explicitly not deployed here).
